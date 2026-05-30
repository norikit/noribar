# Architectural decisions

Locked decisions are **constraints**. Do not relitigate without explicit owner direction.
When a new decision is made, add an entry here (newest at the bottom of its section) and,
if it resolves an [open question](open-questions.md), remove that entry there.

Format: each decision has a status, the decision, and the rationale.

> The cross-cutting rationale for D1/D2/D4 — how we compare to sketchybar on performance
> and what the Swift/AppKit/Lua stack buys us beyond it — is gathered in
> [why-swift.md](why-swift.md).

---

## D1 — Language & platform: Swift / macOS

- **Status:** Locked (2026-05-30)
- **Decision:** Native Swift application targeting macOS.
- **Rationale:** First-class access to AppKit, CoreAnimation, and the SF Symbols /
  `SymbolEffect` APIs that are central to the product. Swift is the modern, contributor-
  approachable choice for a new macOS app.

## D2 — Rendering backend: AppKit + CALayer

- **Status:** Locked (2026-05-30)
- **Decision:** The bar is an `NSView` / `NSImageView` tree on a layer-backed host,
  using AppKit + CoreAnimation. **Not** raw CoreGraphics drawing (sketchybar's approach).
- **Rationale:** This is the whole reason the project exists. sketchybar draws static
  font glyphs and therefore **cannot** use Apple's symbol-effect engine. An AppKit view
  tree gets `NSImageView.addSymbolEffect(...)`, magic `.replace`, draw-on/off, and
  variable color **for free**. See [sketchybar-reference.md](sketchybar-reference.md).
- **Consequence / risk:** AppKit views must be hosted inside a private-SkyLight window
  (see D3). That bridge is novel — it was de-risked by
  [Spike A](../../tasks/spike-a/task.md) and **confirmed viable** (see D6).

## D3 — Window strategy: private SkyLight (SLS/CGS) APIs

- **Status:** Locked (2026-05-30)
- **Decision:** Create/manage the bar window with private SkyLight APIs, sketchybar/
  yabai-style: all-Spaces, over-fullscreen, non-activating, able to replace the real
  menu bar, blur support.
- **Rationale:** These behaviors are non-negotiable for power users and are impossible
  with public AppKit alone.
- **Consequences:** No App Sandbox, no Mac App Store, per-macOS-version code forks
  (Monterey/Ventura/Sonoma/Tahoe), fragility across OS updates, permission prompts.
  **Mitigation:** isolate all SLS calls behind a window-backend boundary so a public
  fallback could be added and OS forks are contained.
- **Spike A refinement (see D6):** the SLS surface is *additive hardening* on top of a
  public `NSPanel`, not the thing that hosts the views. The private symbols are reached
  via `dlsym(RTLD_DEFAULT, …)` — `SkyLight.framework` has no on-disk binary (dyld-cache
  only), so `-framework SkyLight` is fragile.

## D4 — Configuration: embedded Lua

- **Status:** Locked (2026-05-30)
- **Decision:** Users configure and drive the bar with an embedded Lua runtime
  (Hammerspoon / AwesomeWM style), not sketchybar's imperative shell-CLI + per-event
  script spawning.
- **Rationale:** More powerful, more shareable, and far less per-tick overhead than
  spawning a process per event. Strong fit for the ricing community.
- **Consequence / risk:** Must embed and bridge a Lua runtime and define a safe
  Lua↔main-thread threading model. **Resolved** by [Spike B](../../tasks/spike-b/task.md) —
  the embedding, threading, crash-isolation and hot-reload mechanics are locked in **D7** below.

## D5 — Minimum macOS 13, graceful degradation

- **Status:** Locked (2026-05-30)
- **Decision:** Deployment target macOS 13 (Ventura). Newer capabilities degrade
  gracefully on older systems rather than blocking them.
- **Rationale:** Reach vs. features. But note: the `SymbolEffect` API is **macOS 14+**,
  and draw-on/off (SF Symbols 7) is **macOS 26+**. On macOS 13 symbols render static.
- **Consequence:** All symbol-effect code paths must be gated behind `if #available`
  with sensible static fallbacks.

## D6 — Window/render bridge: public `NSPanel` + additive SLS retag (Spike A outcome)

- **Status:** Locked (2026-05-30) — resolves former open question Q1, via
  [Spike A](../../tasks/spike-a/task.md) ([findings](../../tasks/spike-a/FINDINGS.md)).
- **Decision:** The bar surface is a borderless **non-activating `NSPanel`**
  (`.accessory` activation policy / `LSUIElement`) that **owns the AppKit/CALayer view
  tree** — so native SF Symbol effects (incl. macOS 26 draw-on/off) work. SkyLight is
  applied **additively** to the panel's real `CGWindowID` for hardening only:
  `kCGSPreventsActivationTagBit`, `kCGSExposeFadeTagBit`, and `SLSSetWindowLevel`
  (`CGShieldingWindowLevel()`) for above-fullscreen. Private symbols are bound at runtime
  with `dlsym(RTLD_DEFAULT, …)` behind the `WindowBackend` boundary. The pure-SLS
  viewless window (Spike A "A3") is **rejected**: native symbol effects are bound to
  AppKit's `NSView` + `NSScreen` display-link → RenderBox pipeline and are unreachable
  without an AppKit host.
- **Verified:** native effects ran inside the SLS-retagged panel at **0.0 % idle CPU**,
  without stealing focus / Dock / Cmd-Tab. (All-Spaces & over-fullscreen are configured
  via the documented mechanism; final on-screen confirmation is a pending manual check.)
- **🔴 Hard constraint for the item model:** **one in-flight symbol animation per
  `NSImageView`.** Stacking a content-transition (`.replace`) and a discrete effect
  (`.drawOn`) on the *same* view in the *same* run-loop turn crashes Apple's RenderBox
  animation thread (`EXC_BAD_ACCESS` in `RB::Symbol::Animation::apply`). The bar-state
  model must serialize symbol mutations per item.

## D7 — Lua embedding & threading: vanilla 5.4 C target + dedicated queue (Spike B outcome)

- **Status:** Locked (2026-05-30) — resolves former open question Q2, via
  [Spike B](../../tasks/spike-b/task.md) ([findings](../../tasks/spike-b/FINDINGS.md)).
- **Decision:**
  - **Distribution:** vanilla **Lua 5.4.7** vendored as a SwiftPM **C target** (`CLua`),
    MIT-licensed (AGPL-compatible). Public API surfaced to Swift via an umbrella header;
    Lua's function-like macros (`lua_pcall`, `lua_pop`, …, invisible to the Clang importer)
    are re-exported through a single `static inline` shim header (`cl_*`). **Not** a Swift
    wrapper package, **not** LuaJIT (5.1 semantics, speed irrelevant for a status bar).
  - **Threading:** one `lua_State` owned by a **dedicated serial `DispatchQueue`**, never
    touched off it. Lua callbacks emit `BarCommand` values; `emit` marshals them to
    `DispatchQueue.main` where they apply to the AppKit view tree. Timers
    (`DispatchSourceTimer` on the Lua queue) and events (hopped onto the queue first) are
    the only inbound paths. The dedicated queue (vs. main-thread-only) is justified by
    crash containment, not throughput.
  - **Crash isolation:** every entry into Lua goes through `lua_pcall` + a traceback
    message handler, and the state carries an **instruction-count hook**
    (`lua_sethook(LUA_MASKCOUNT)`) that aborts a runaway call. A buggy user script is
    logged and survived, never fatal.
  - **Hot reload:** a kqueue file watcher triggers `emit(.clear)` → cancel timers →
    `lua_close` → fresh state → re-run. Handles in-place **and** atomic-rename saves; no
    leak across 100 reloads.
- **Verified:** per-tick Lua→Swift round-trip **~1.7 µs** (p99 < 3 µs); Lua adds **<1 MB**
  RSS; flat memory across 100 hot reloads; `error()`, nil-index, and infinite-loop faults
  all caught with the app surviving.
- **Consequence for later work:**
  - The production binding layer needs a typed table-field reader and `luaL_argerror`-based
    validation (the spike hand-juggled the stack and silently defaulted bad args).
  - The runtime owner must decide a **sandbox policy** for user configs (`os.execute`,
    `io`, `require`) — open in the spike, a security decision for the product (see
    [Q8](open-questions.md)).
  - `item:set` icon changes must **coalesce/serialize symbol mutations per item** on the
    main side to respect [D6](#d6--windowrender-bridge-public-nspanel--additive-sls-retag-spike-a-outcome)'s
    one-animation-per-`NSImageView` rule.

## D8 — Render/update model: no app-managed frame loop; per-item single-animator coalescing (M1 outcome)

- **Status:** Locked (2026-05-30) — resolves former open question Q4, via
  [M1](../../tasks/m1-tracer-bullet/task.md) ([findings](../../tasks/m1-tracer-bullet/FINDINGS.md)).
- **Decision:**
  - **No app-managed display link / frame loop.** Unlike sketchybar (CVDisplayLink + manual
    CGContext redraw), noribar lets **CoreAnimation drive symbol effects**. The app schedules
    no per-frame work; idle CPU is ~0% by construction (measured ~0.2% under the sample
    config, whose only wakeups are Lua timers). A future continuously-animating item type
    (graph/slider) may reintroduce a display link **scoped to those items** — not global.
  - **`BarStore` (main thread) is the single applier** of `BarCommand`s (the D7 marshalling
    target: `LuaRuntime.emit` → `DispatchQueue.main.async { store.apply(cmd) }`).
  - **`SymbolAnimator` is the per-`NSImageView` single-animator unit that enforces D6.** It
    (a) **coalesces** rapid `:set`s into one apply per run-loop turn (one
    `DispatchQueue.main.async` flush; last-writer-wins for the effect), and (b) resolves the
    desired state into **≤ 1 animating mutation, never a content transition *and* a discrete
    effect together** (a `.replace` swap is itself the animation; a discrete effect is a plain
    image set + one `addSymbolEffect`). The resolver is a **pure function**, unit-tested
    headlessly; the live guarantee was confirmed by a 0.1 s icon+effect+`.replace` stress soak
    with no RenderBox crash.
- **Consequence:** the coalescing window is "one run-loop turn." "Last effect wins per turn"
  silently drops a second effect stacked in the same turn — acceptable for M1; a future item
  type wanting sequential effects needs an explicit per-item queue, not collapse-to-one.

> **Item schema (Q5)** is **partially** addressed by M1: a concrete minimal `BarItem`
> (id + immutable position + mutable icon/label, `:set` taking a transient `effect`) is
> locked as the starting point, but the full type/property model remains open — see
> [open-questions.md](open-questions.md) Q5.

---

## License

- **Status:** Locked (inherited) — **AGPL-3.0** (`LICENSE` at repo root).
