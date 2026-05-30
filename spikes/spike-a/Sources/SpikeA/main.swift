//
//  main.swift — Spike A entry point.
//
//  Usage:
//    SpikeA [--approach a1|a2] [--anim|--idle] [--seconds N] [--space]
//
//    --approach a1   public AppKit only            (default: a2)
//    --approach a2   A1 + private SLS retag
//    --anim          fire symbol effects on a timer (default)
//    --idle          do NOT animate (for idle-CPU measurement)
//    --seconds N     auto-quit after N seconds      (default: stay up)
//    --space         use the dedicated-space stickiness route (A2 only)
//
//  On launch it prints machine-readable diagnostics (WINDOWID=, SPACES=, …) so an
//  external harness can screenshot the window and verify behavior.
//

import AppKit

struct Args {
    var approach: Approach = .a2
    var animate = true
    var seconds: Double? = nil
    var dedicatedSpace = false
    var only: String? = nil
}

func parseArgs() -> Args {
    var a = Args()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        switch arg {
        case "--approach": if let v = it.next(), let ap = Approach(rawValue: v) { a.approach = ap }
        case "--anim":  a.animate = true
        case "--idle":  a.animate = false
        case "--space": a.dedicatedSpace = true
        case "--seconds": if let v = it.next(), let s = Double(v) { a.seconds = s }
        case "--only": a.only = it.next()
        default: break
        }
    }
    return a
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let args: Args
    var bar: Bar!
    var animTimer: Timer?
    var quitTimer: Timer?

    init(args: Args) { self.args = args }

    func applicationDidFinishLaunching(_ note: Notification) {
        bar = Bar(approach: args.approach, useDedicatedSpace: args.dedicatedSpace)
        bar.strip.only = args.only
        bar.show()
        printDiagnostics()

        if args.animate {
            // ~1.25 s cycle: fast enough to observe, slow enough to read each effect.
            animTimer = Timer.scheduledTimer(withTimeInterval: 1.25, repeats: true) { [weak self] _ in
                self?.bar.strip.fireEffects()
            }
            bar.strip.fireEffects()
        }

        if let s = args.seconds {
            quitTimer = Timer.scheduledTimer(withTimeInterval: s, repeats: false) { [weak self] _ in
                if let wid = self?.bar.windowID {
                    print("SPACES_FOR_WINDOW_AT_QUIT=\(SLS.spaceCount(forWindow: wid))")
                }
                print("FRONTMOST_APP_AT_QUIT=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
                Self.printEffectTable()
                NSApp.terminate(nil)
            }
        }
    }

    func printDiagnostics() {
        let p = bar.panel
        let cid = SLS.mainConnectionID
        let wid = bar.windowID
        print("=== SPIKE-A DIAGNOSTICS ===")
        print("APPROACH=\(args.approach.rawValue)")
        print("PID=\(ProcessInfo.processInfo.processIdentifier)")
        print("WINDOWID=\(wid)")
        print("SLS_CID=\(cid)")
        print("ACTIVATION_POLICY=\(NSApp.activationPolicy().rawValue) (0=regular,1=accessory,2=prohibited)")
        print("APP_IS_ACTIVE=\(NSApp.isActive)")
        print("PANEL_IS_KEY=\(p.isKeyWindow)  CAN_BECOME_KEY=\(p.canBecomeKey)")
        print("PANEL_LEVEL=\(p.level.rawValue)")
        print("COLLECTION_BEHAVIOR=\(p.collectionBehavior.rawValue)")
        print("SPACES_FOR_WINDOW=\(SLS.spaceCount(forWindow: wid))  (count of spaces this window is on)")
        if bar.dedicatedSpace != 0 { print("DEDICATED_SPACE=\(bar.dedicatedSpace)") }
        if !SLS.missing.isEmpty { print("SLS_MISSING_SYMBOLS=\(SLS.missing.sorted().joined(separator: ","))") }
        print("===========================")
        fflush(stdout)
    }

    static func printEffectTable() {
        print("=== SYMBOL EFFECT LOG ===")
        for (k, v) in SymbolStrip.effectLog.sorted(by: { $0.key < $1.key }) {
            print("EFFECT \(k) = \(v)")
        }
        print("=========================")
        fflush(stdout)
    }
}

// --- bootstrap ---
let args = parseArgs()
let app = NSApplication.shared
// .accessory => no Dock icon, not in Cmd-Tab, does not steal activation on launch.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(args: args)
app.delegate = delegate
app.run()
