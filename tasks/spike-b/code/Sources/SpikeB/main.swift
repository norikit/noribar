import AppKit
import CLua

// Spike B entry point.
//   (no args)    live GUI: render the bar, watch config.lua for hot reload, and
//                inject a simulated `front_app_switched` event on a timer.
//   --selftest   headless measurement + hot-reload + crash-isolation battery,
//                prints a report, then exits. Used to populate FINDINGS.md.

/// Resolve config.lua next to the package (works from `swift run` and from a built binary).
func configURL() -> URL {
    let fm = FileManager.default
    // 1) explicit override
    if let env = ProcessInfo.processInfo.environment["SPIKE_B_CONFIG"] {
        return URL(fileURLWithPath: env)
    }
    // 2) alongside the package root (../../config.lua relative to the source dir layout)
    let here = URL(fileURLWithPath: #filePath) // .../Sources/SpikeB/main.swift
        .deletingLastPathComponent()           // Sources/SpikeB
        .deletingLastPathComponent()           // Sources
        .deletingLastPathComponent()           // spike-b
        .appendingPathComponent("config.lua")
    if fm.fileExists(atPath: here.path) { return here }
    // 3) cwd fallback
    return URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("config.lua")
}

final class AppController {
    let vm = LuaVM()
    let renderer = BarRenderer()
    let config = configURL()
    private var watcher: ConfigWatcher?
    private var eventTimer: Timer?
    private let apps = ["Safari", "Xcode", "Terminal", "Finder", "Music"]
    private var appIndex = 0

    func wireMarshalling() {
        // The marshalling boundary: Lua-queue commands → main-thread view tree.
        vm.emit = { [weak self] cmd in
            DispatchQueue.main.async { self?.renderer.apply(cmd) }
        }
        vm.onError = { msg in
            FileHandle.standardError.write(Data(("⚠️  lua: " + msg + "\n").utf8))
        }
    }

    func runLive() {
        wireMarshalling()
        renderer.show()
        vm.start(configURL: config)

        watcher = ConfigWatcher(url: config) { [weak self] in
            guard let self else { return }
            Metrics.shared.noteReload()
            FileHandle.standardError.write(Data("↻ hot reload\n".utf8))
            self.vm.start(configURL: self.config)
        }
        watcher?.start()

        // Simulated system event: cycle the "front app" every 2s.
        eventTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.appIndex = (self.appIndex + 1) % self.apps.count
            self.vm.fire(event: "front_app_switched", payload: ["app": self.apps[self.appIndex]])
        }
        FileHandle.standardError.write(Data("noribar spike-b live. config: \(config.path)\nEdit config.lua to hot-reload.\n".utf8))
    }

    // MARK: Self-test battery

    func runSelfTest() {
        wireMarshalling()
        renderer.show()
        let baselineMem = Metrics.residentMemoryMB()
        log("=== Spike B self-test ===")
        log(String(format: "baseline rss (pre-VM): %.1f MB", baselineMem))

        vm.start(configURL: config)
        // Fence on the Lua queue so the state has actually been built before we read.
        vm.onQueue {
            let mem = Metrics.residentMemoryMB()
            DispatchQueue.main.async { [weak self] in
                self?.log(String(format: "rss with VM + libs + config loaded: %.1f MB", mem))
                let iterations = 20_000
                self?.vm.benchmark(iterations: iterations) { [weak self] in
                    DispatchQueue.main.async { self?.afterBenchmark(iterations: iterations) }
                }
            }
        }
    }

    private func afterBenchmark(iterations: Int) {
        log("--- per-tick overhead (\(iterations) iterations) ---")
        log(Metrics.shared.snapshot())

        // 2) Crash isolation: three deliberately broken callbacks.
        log("--- crash isolation (expect 3 caught errors, no crash) ---")
        vm.evaluate(#"error("boom — deliberate")"#, name: "test:explicit-error")
        vm.evaluate(#"local t = nil; return t.field"#, name: "test:nil-index")
        vm.evaluate(#"while true do end"#, name: "test:infinite-loop")

        // 3) Hot reload x100 (leak check).
        vm.onQueue {
            DispatchQueue.main.async { [weak self] in self?.hotReloadStress(remaining: 100) }
        }
    }

    private func hotReloadStress(remaining: Int) {
        if remaining == 0 {
            vm.onQueue {
                let mem = Metrics.residentMemoryMB()
                DispatchQueue.main.async { [weak self] in self?.finishSelfTest(post100Mem: mem) }
            }
            return
        }
        vm.start(configURL: config)
        Metrics.shared.noteReload()
        DispatchQueue.main.async { [weak self] in self?.hotReloadStress(remaining: remaining - 1) }
    }

    private func finishSelfTest(post100Mem: Double) {
        log("--- after 100 hot reloads ---")
        log(String(format: "rss: %.1f MB (reloads counted: %d)", post100Mem, Metrics.shared.reloadCount))
        log("=== self-test complete; app survived all of the above ===")
        NSApp.terminate(nil)
    }

    private func log(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }
}

// MARK: - App bootstrap

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon; this is a bar, not an app window

let controller = AppController()

final class AppDelegate: NSObject, NSApplicationDelegate {
    let selfTest: Bool
    init(selfTest: Bool) { self.selfTest = selfTest }
    func applicationDidFinishLaunching(_ note: Notification) {
        if selfTest { controller.runSelfTest() } else { controller.runLive() }
    }
}

let isSelfTest = CommandLine.arguments.contains("--selftest")
let delegate = AppDelegate(selfTest: isSelfTest)
app.delegate = delegate
app.run()
