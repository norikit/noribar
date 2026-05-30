// ipc-poc.swift — Spike C proof-of-concept for noribar's IPC + threading model.
//
// What this proves (headless, no AppKit required):
//
//   1. A single long-lived process owns the bar state. An external, short-lived CLI
//      ("noribar -m ...") talks to it over a **Unix domain socket** — sketchybar's model.
//   2. The socket accept/read loop runs on a **background GCD queue** via DispatchSource,
//      so a slow or misbehaving client can never stall the UI.
//   3. Every command is parsed off-main, then its *application* (the part that would
//      mutate the Lua state and the CALayer view tree) is marshalled onto the **main
//      queue** — modelling the rule "Lua state + view tree are main-thread-confined".
//   4. Messages are **length-prefixed** (4-byte big-endian length + UTF-8 payload),
//      giving clean request/reply framing over the stream socket.
//
// It also exercises the unifying **event model**: a timer source and the socket both
// funnel into the same main-thread event dispatcher, which is where item callbacks and
// redraw coalescing will live in the real product.
//
// Run:   swift ipc-poc.swift
// Expect: the server starts, a timer "event" fires, a client sends three framed
//         commands (one a query with a reply), and ALL state mutation is observed to
//         happen on the main thread. Process exits 0 on success, non-zero on any
//         assertion failure.

import Foundation
#if canImport(Glibc)
import Glibc
#endif

// MARK: - Framing helpers (length-prefixed messages)

enum Frame {
    /// Write a 4-byte big-endian length, then the UTF-8 payload. Returns false on error.
    static func write(_ fd: Int32, _ message: String) -> Bool {
        let payload = Array(message.utf8)
        var len = UInt32(payload.count).bigEndian
        let header = withUnsafeBytes(of: &len) { Array($0) }
        return writeAll(fd, header) && writeAll(fd, payload)
    }

    /// Read one length-prefixed message, or nil on EOF/error.
    static func read(_ fd: Int32) -> String? {
        guard let header = readAll(fd, 4) else { return nil }
        let len = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard len > 0, len < 1_048_576 else { return len == 0 ? "" : nil }
        guard let body = readAll(fd, Int(len)) else { return nil }
        return String(decoding: body, as: UTF8.self)
    }

    private static func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var off = 0
        return bytes.withUnsafeBytes { raw in
            while off < bytes.count {
                let n = Foundation.write(fd, raw.baseAddress!.advanced(by: off), bytes.count - off)
                if n <= 0 { if errno == EINTR { continue }; return false }
                off += n
            }
            return true
        }
    }

    private static func readAll(_ fd: Int32, _ count: Int) -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: count)
        var off = 0
        let ok = buf.withUnsafeMutableBytes { raw -> Bool in
            while off < count {
                let n = Foundation.read(fd, raw.baseAddress!.advanced(by: off), count - off)
                if n == 0 { return false }          // EOF
                if n < 0 { if errno == EINTR { continue }; return false }
                off += n
            }
            return true
        }
        return ok ? buf : nil
    }
}

// MARK: - Thread-checking helper

func assertMain(_ where_: String) {
    precondition(Thread.isMainThread, "VIOLATION: \(where_) ran OFF the main thread")
}

// MARK: - The bar "core" — owns all state, main-thread-confined.

/// Stand-in for the real product's Lua state + CALayer item tree. Only ever touched on
/// the main thread; the PoC asserts this on every access.
final class BarCore {
    private(set) var items: [String: String] = ["clock": "--:--", "front_app": "?"]
    private(set) var redraws = 0
    private(set) var eventsHandled = 0

    /// The single dispatch point. Timers, system events, and CLI commands all arrive here.
    /// Returns an optional reply string (for query commands).
    @discardableResult
    func handle(event: String, _ args: [String]) -> String? {
        assertMain("BarCore.handle(\(event))")
        eventsHandled += 1
        switch event {
        case "set":
            guard args.count >= 2 else { return "error: set <item> <value>" }
            items[args[0]] = args[1]
            scheduleRedraw()
            return "ok"
        case "query":
            guard let name = args.first else { return "error: query <item>" }
            return items[name] ?? "nil"
        case "tick":                       // a timer-sourced event
            items["clock"] = args.first ?? "tick"
            scheduleRedraw()
            return nil
        default:
            return "error: unknown event \(event)"
        }
    }

    /// In the real product this marks items dirty and coalesces a CATransaction redraw on
    /// the next loop pass. Here we just count it — and assert main-thread.
    private func scheduleRedraw() {
        assertMain("scheduleRedraw")
        redraws += 1
    }
}

// MARK: - Socket server (background accept loop, main-thread command application).

final class ControlSocket {
    let path: String
    private var listenFD: Int32 = -1
    private let queue = DispatchQueue(label: "noribar.control.accept")
    private let core: BarCore

    init(path: String, core: BarCore) { self.path = path; self.core = core }

    func start() throws {
        unlink(path)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw POCError.sys("socket") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            path.withCString { cs in
                strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cs,
                        MemoryLayout.size(ofValue: addr.sun_path) - 1)
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, len) }
        }
        guard bound == 0 else { throw POCError.sys("bind") }
        // Lock down to the owning user only (no entitlements, file-permission security).
        chmod(path, 0o600)
        guard listen(listenFD, 16) == 0 else { throw POCError.sys("listen") }

        // Accept loop on a background queue — never blocks the main/UI thread.
        queue.async { [weak self] in self?.acceptLoop() }
    }

    private func acceptLoop() {
        while true {
            let client = accept(listenFD, nil, nil)
            if client < 0 { if errno == EINTR { continue }; break }
            handleClient(client)   // serial here for the PoC; real product can fan out.
        }
    }

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }
        // Parse OFF the main thread...
        guard let msg = Frame.read(fd) else { return }
        let parts = msg.split(separator: " ").map(String.init)
        guard let event = parts.first else { _ = Frame.write(fd, "error: empty"); return }
        let args = Array(parts.dropFirst())

        // ...then apply ON the main thread, synchronously so we can return a reply.
        var reply: String?
        DispatchQueue.main.sync { reply = self.core.handle(event: event, args) }
        _ = Frame.write(fd, reply ?? "ok")
    }

    func stop() { if listenFD >= 0 { close(listenFD); unlink(path) } }
}

enum POCError: Error { case sys(String) }

// MARK: - Minimal client ("noribar -m ...")

func sendCommand(path: String, _ message: String) -> String? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        path.withCString { cs in
            strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cs,
                    MemoryLayout.size(ofValue: addr.sun_path) - 1)
        }
    }
    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
    }
    guard ok == 0 else { return nil }
    guard Frame.write(fd, message) else { return nil }
    return Frame.read(fd)
}

// MARK: - Driver

let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp/"
let sockPath = (tmp as NSString).appendingPathComponent("noribar-poc-\(getpid()).sock")

let core = BarCore()
let server = ControlSocket(path: sockPath, core: core)

do { try server.start() } catch { FileHandle.standardError.write(Data("server start failed: \(error)\n".utf8)); exit(1) }
print("server listening on \(sockPath)")

// A timer source — proves system/timer events funnel into the SAME main-thread dispatcher.
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now() + .milliseconds(50), repeating: .never)
timer.setEventHandler { core.handle(event: "tick", ["12:00"]) }
timer.resume()

// A background "client" issuing CLI commands, then we assert results back on main.
DispatchQueue.global().async {
    let r1 = sendCommand(path: sockPath, "set front_app Safari")
    let r2 = sendCommand(path: sockPath, "set clock 12:01")
    let r3 = sendCommand(path: sockPath, "query front_app")
    let r4 = sendCommand(path: sockPath, "bogus arg")

    DispatchQueue.main.async {
        var failures = 0
        func check(_ cond: Bool, _ label: String) {
            print(cond ? "  PASS \(label)" : "  FAIL \(label)"); if !cond { failures += 1 }
        }
        print("results:")
        check(r1 == "ok", "set front_app -> ok (got \(r1 ?? "nil"))")
        check(r2 == "ok", "set clock -> ok (got \(r2 ?? "nil"))")
        check(r3 == "Safari", "query front_app -> Safari (got \(r3 ?? "nil"))")
        check(r4?.hasPrefix("error:") == true, "bogus -> error (got \(r4 ?? "nil"))")
        check(core.items["clock"] == "12:01", "clock state == 12:01 (got \(core.items["clock"] ?? "nil"))")
        check(core.eventsHandled >= 4, "events handled >= 4 (got \(core.eventsHandled))")
        check(core.redraws >= 1, "redraws coalesced/counted (got \(core.redraws))")
        server.stop()
        print(failures == 0 ? "\nALL PASS — IPC + threading model validated." : "\n\(failures) FAILURE(S).")
        exit(failures == 0 ? 0 : 1)
    }
}

// Safety net: bail if the run hangs.
DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
    FileHandle.standardError.write(Data("timeout — PoC hung\n".utf8)); exit(2)
}

dispatchMain()
