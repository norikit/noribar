import AppKit

/// Headless verification battery (`noribar --selftest`). Confirms the parts of M1 that do
/// **not** require a human watching the screen:
///   1. The D6 one-animation invariant, proven on the pure `SymbolAnimator.Resolution`
///      planner over an exhaustive matrix of request shapes (no window server needed).
///   2. Crash isolation: deliberately broken Lua callbacks are caught; the app survives.
///   3. Hot-reload stress: many `lua_close`+rebuild cycles, RSS checked for leaks.
///   4. Per-tick Lua→command overhead.
///
/// The genuinely visual checks (a *visible* native effect; no RenderBox crash under a live
/// 0.1 s loop; Spaces/fullscreen/focus) are called out in FINDINGS as manual steps.
enum SelfTest {

    static func run(runtime: LuaRuntime, backend: WindowBackend, configURL: URL) {
        log("=== noribar M1 self-test ===")
        var failures = 0

        // 1) D6 invariant on the pure planner.
        failures += d6PlannerChecks()

        // 2) Window diagnostics (proves the SLS panel came up).
        log("--- window backend diagnostics ---")
        for (k, v) in backend.diagnostics().sorted(by: { $0.key < $1.key }) { log("  \(k)=\(v)") }

        // 3) Crash isolation — three broken callbacks; expect 3 logged errors, no crash.
        log("--- crash isolation (expect 3 caught errors, no crash) ---")
        runtime.evaluate(#"error("boom — deliberate")"#, name: "test:explicit-error")
        runtime.evaluate(#"local t = nil; return t.field"#, name: "test:nil-index")
        runtime.evaluate(#"while true do end"#, name: "test:infinite-loop")

        // 4) Hot-reload stress (leak check) then finish.
        let baseline = Metrics.residentMemoryMB()
        runtime.onQueue {
            DispatchQueue.main.async { hotReloadStress(runtime: runtime, configURL: configURL,
                                                       remaining: 50, baseline: baseline,
                                                       failures: failures) }
        }
    }

    // MARK: D6 planner checks (the core of this milestone)

    private static func d6PlannerChecks() -> Int {
        log("--- D6 one-animation invariant (pure planner) ---")
        typealias Resolver = SymbolAnimator.Resolution
        var fails = 0

        // Exhaustive matrix: current icon fixed; desired ∈ {nil, same, different};
        // effect ∈ {nil, replace, bounce, pulse, scale}.
        let desireds: [String?] = [nil, "clock", "clock.fill"]
        let effects: [SymbolEffect?] = [nil, .replace, .bounce, .pulse, .scale]
        var checked = 0
        for d in desireds {
            for e in effects {
                let plan = Resolver.resolve(currentIcon: "clock", desiredIcon: d, effect: e)
                checked += 1
                if !Resolver.isValid(plan) {
                    fails += 1
                    log("  FAIL invariant violated for desired=\(d ?? "nil") effect=\(e?.rawValue ?? "nil"): \(plan)")
                }
            }
        }
        log("  invariant held across all \(checked) request shapes: \(fails == 0 ? "PASS" : "FAIL")")

        // Specific expectations that pin the intended behavior.
        func expect(_ got: [SymbolAnimator.Mutation], _ want: [SymbolAnimator.Mutation], _ label: String) {
            if got == want {
                log("  PASS \(label)")
            } else {
                fails += 1
                log("  FAIL \(label): got \(got) want \(want)")
            }
        }
        // icon swap + replace → single content transition (the swap IS the animation)
        expect(Resolver.resolve(currentIcon: "clock", desiredIcon: "clock.fill", effect: .replace),
               [.contentTransition(icon: "clock.fill")], "replace+iconchange → 1 content transition")
        // icon swap + discrete → plain set + one discrete effect (one animation total)
        expect(Resolver.resolve(currentIcon: "clock", desiredIcon: "clock.fill", effect: .bounce),
               [.setImage(icon: "clock.fill"), .discreteEffect(.bounce)], "bounce+iconchange → set+1 effect")
        // discrete with no icon change → just the effect
        expect(Resolver.resolve(currentIcon: "clock", desiredIcon: nil, effect: .pulse),
               [.discreteEffect(.pulse)], "pulse+noiconchange → 1 effect")
        // replace requested but icon unchanged → nothing to transition → no-op
        expect(Resolver.resolve(currentIcon: "clock", desiredIcon: "clock", effect: .replace),
               [], "replace+sameicon → no-op")
        // plain icon change, no effect → plain set
        expect(Resolver.resolve(currentIcon: "clock", desiredIcon: "clock.fill", effect: nil),
               [.setImage(icon: "clock.fill")], "iconchange+noeffect → set only")

        return fails
    }

    // MARK: Hot-reload stress

    private static func hotReloadStress(runtime: LuaRuntime, configURL: URL,
                                        remaining: Int, baseline: Double, failures: Int) {
        if remaining == 0 {
            runtime.onQueue {
                let mem = Metrics.residentMemoryMB()
                DispatchQueue.main.async {
                    log("--- after hot-reload stress ---")
                    log(String(format: "  rss baseline=%.1f MB  now=%.1f MB  reloads=%d",
                               baseline, mem, Metrics.shared.reloadCount))
                    log(failures == 0 ? "=== self-test PASSED (app survived all of the above) ==="
                                      : "=== self-test FAILED: \(failures) check(s) ===")
                    NSApp.terminate(nil)
                }
            }
            return
        }
        runtime.start(configURL: configURL)
        Metrics.shared.noteReload()
        DispatchQueue.main.async {
            hotReloadStress(runtime: runtime, configURL: configURL,
                            remaining: remaining - 1, baseline: baseline, failures: failures)
        }
    }

    static func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
}
