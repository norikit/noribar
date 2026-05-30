import AppKit

// noribar — entry point.
//
// Modes:
//   (default)    live bar: SkyLight panel + Lua config + hot reload + FrontAppProvider.
//   --selftest   headless battery (D6 invariant, crash isolation, hot-reload leak check),
//                prints a report to stderr, then exits.
//   --stress     live, but loads config-stress.lua (a 0.1 s icon+effect loop) to exercise
//                the D6 coalescing rule under load. Watch for RenderBox crashes.
//   --config P   use config file at path P.

/// Resolve the config file (works from `swift run` and from a bundled binary).
func resolveConfig(named name: String = "config.lua") -> URL {
    let fm = FileManager.default
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--config"), i + 1 < args.count {
        return URL(fileURLWithPath: args[i + 1])
    }
    if let env = ProcessInfo.processInfo.environment["NORIBAR_CONFIG"] {
        return URL(fileURLWithPath: env)
    }
    // Inside the .app bundle's Resources (bundle.sh copies the sample configs there) so the
    // bundled app — the only way to run the symbol-effect engine, see FINDINGS — is self-contained.
    if let res = Bundle.main.resourceURL?.appendingPathComponent(name), fm.fileExists(atPath: res.path) {
        return res
    }
    // Alongside the package root (../.. from this source file at Sources/noribar/main.swift).
    let here = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Sources/noribar
        .deletingLastPathComponent()   // Sources
        .deletingLastPathComponent()   // package root
        .appendingPathComponent(name)
    if fm.fileExists(atPath: here.path) { return here }
    return URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(name)
}

/// Owns the wired-together app: window backend, store, Lua runtime, watcher, providers.
final class AppController {
    let backend: WindowBackend = SkyLightPanel()
    let runtime = LuaRuntime()
    private let store: BarStore
    private let config: URL
    private let selfTest: Bool
    private var watcher: ConfigWatcher?
    private let providers: [Provider] = [FrontAppProvider()]

    init(config: URL, selfTest: Bool) {
        self.config = config
        self.selfTest = selfTest
        self.store = BarStore(barView: backend.barView)
    }

    func start() {
        // The marshalling boundary (D7): Lua-queue commands → main-thread view tree.
        runtime.emit = { [weak self] cmd in
            DispatchQueue.main.async { self?.store.apply(cmd) }
        }
        runtime.onError = { msg in
            FileHandle.standardError.write(Data(("⚠️  lua: " + msg + "\n").utf8))
        }

        backend.show()
        runtime.start(configURL: config)

        if selfTest {
            SelfTest.run(runtime: runtime, backend: backend, configURL: config)
            return   // self-test drives its own lifecycle and terminates.
        }

        // Hot reload.
        watcher = ConfigWatcher(url: config) { [weak self] in
            guard let self else { return }
            Metrics.shared.noteReload()
            FileHandle.standardError.write(Data("↻ hot reload\n".utf8))
            self.runtime.start(configURL: self.config)
        }
        watcher?.start()

        // Native providers feed events into Lua.
        for p in providers {
            p.start { [weak self] event, payload in self?.runtime.fire(event: event, payload: payload) }
        }

        let banner = "noribar live. config: \(config.path)\n"
            + "Edit the config to hot-reload; switch apps to fire a symbol effect.\n"
        FileHandle.standardError.write(Data(banner.utf8))

        // Optional auto-quit (for bounded/automated runs, e.g. a timed --stress soak).
        if let i = CommandLine.arguments.firstIndex(of: "--seconds"),
           i + 1 < CommandLine.arguments.count, let secs = Double(CommandLine.arguments[i + 1]) {
            Timer.scheduledTimer(withTimeInterval: secs, repeats: false) { _ in
                FileHandle.standardError.write(Data("auto-quit after \(secs)s — no crash\n".utf8))
                NSApp.terminate(nil)
            }
        }
    }
}

// MARK: - Bootstrap

let isSelfTest = CommandLine.arguments.contains("--selftest")
let isStress = CommandLine.arguments.contains("--stress")
let configURL = resolveConfig(named: isStress ? "config-stress.lua" : "config.lua")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon; not in Cmd-Tab; doesn't steal focus

let controller = AppController(config: configURL, selfTest: isSelfTest)

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        controller.start()
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
