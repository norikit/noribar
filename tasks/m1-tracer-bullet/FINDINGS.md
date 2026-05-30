# M1 findings — integration tracer bullet

**Verdict: the seam works.** A single `noribar` process drives an AppKit/CALayer bar hosted
in a private-SkyLight `NSPanel` from a hot-reloadable Lua config; a real native provider
(`FrontAppProvider`) and a Lua timer mutate items at runtime; mutations flow Lua-queue →
`BarCommand` → main thread → `ItemView`; and an icon swap fires a **native SF Symbol
effect** while honoring **D6's one-animation-per-view rule** — verified under a live 0.1 s
icon+effect+content-transition stress loop with **no RenderBox crash**, crash-isolated and
hot-reloadable, at ~0% idle CPU. The product skeleton under `Sources/` now exists.

## What was built

The two spikes' proven pieces were promoted into `Sources/` (CLua and the Lua runtime from
Spike B; the SLS bridge + non-activating panel from Spike A) and the new seam was written:

- **`SymbolAnimator`** (`Render/SymbolAnimator.swift`) — the new intellectual core. One per
  `ItemView` icon view; the single-animator unit that enforces D6.
- **`BarStore`** (`Model/BarStore.swift`) — main-thread item registry, the single applier of
  `BarCommand`s (D7's marshalling target).
- **`item:set{ … effect = }`** — bindings extended so a Lua callback can request a native
  effect (`Lua/Bindings.swift`).
- **`FrontAppProvider`** (`Providers/`) — the first *real* provider, replacing Spike B's
  simulated timer event.
- **`WindowBackend`** protocol with **`SkyLightPanel`** — keeps all SLS/`dlsym` behind the
  D3 boundary.

## How the D6 coalescing was implemented and stress-tested

**The rule (from Spike A / D6):** at most one in-flight symbol animation per `NSImageView`;
stacking a content transition (`.replace`) and a discrete effect (`.bounce`) on one view in
one run-loop turn crashes Apple's RenderBox thread.

**The implementation** is a two-part design with a *pure, testable* core:

1. **Coalescing.** `SymbolAnimator.request(icon:effect:)` accumulates the latest desired
   icon/effect and schedules a single `DispatchQueue.main.async` flush. A burst of `:set`s
   already queued on main (e.g. from a fast Lua timer) collapses to **one** apply per
   run-loop turn — last-writer-wins for the effect.
2. **Resolution** (`SymbolAnimator.Resolution.resolve`, a pure function) turns
   `(currentIcon, desiredIcon, effect)` into a mutation plan with the invariant **≤ 1
   animating mutation, never a content transition *and* a discrete effect together**:
   - `replace` + icon actually changes → one `.contentTransition` (the swap *is* the
     animation);
   - discrete effect + icon changes → `.setImage` (non-animated) **then** one
     `.discreteEffect` (one animation total);
   - discrete effect, icon unchanged → one `.discreteEffect`;
   - `replace` but icon unchanged → no-op (nothing to transition to);
   - icon change, no effect → plain `.setImage`.

Because `resolve` is pure, the D6 invariant is unit-tested headlessly (`--selftest`) across
an exhaustive request matrix — no window server needed. The **live** confirmation is the
`--stress` soak (`config-stress.lua`): one item hammered every 0.1 s with an icon swap + a
discrete effect *and* a second timer requesting a `.replace` transition on the same item.

## Measurements

| Axis | Result | How |
|---|---|---|
| D6 invariant (pure planner) | **PASS** — held across all 15 request shapes + 5 pinned expectations | `swift run noribar --selftest` |
| Live D6 stress (RenderBox) | **No crash** over a 20 s soak driving icon+effect+`.replace` on one view, clean exit | bundled app `--stress --seconds 20` on a real display |
| CPU (sample config) | **~0.2 %** (only the 1 s clock + 0.5 s heartbeat timers; no app frame loop) | `top -l 2` on the running bundled app |
| RSS | **~12 MB** live | same |
| Crash isolation | 3/3 broken callbacks caught (`error()`, nil-index, infinite-loop) — app survived | `--selftest` |
| Hot reload | survived 50 `lua_close`+rebuild cycles; RSS 8.6 → 11.5 MB | `--selftest` |
| SLS panel | real `WINDOWID`, `.accessory` policy, `PANEL_IS_KEY=false` (non-activating) | `--selftest` diagnostics |

Note on RSS under reload: it grew ~3 MB across 50 rapid back-to-back reloads (Spike B saw it
flat over 100 reloads of Lua *alone*). The delta here is most likely AppKit view/autorelease
accumulation during the tight loop (each reload also tears down/rebuilds the view tree via
`.clear`), not a Lua leak — worth a confirming long-soak later, not a blocker.

## The three open decisions (surfaced, not silently picked)

1. **Lua config sandbox policy (D7 / Q8) — left open.** M1 calls `luaL_openlibs`, so user
   configs currently have full `os` / `io` / `require`. This is fine for a single-user,
   local, user-authored config, but a shareable-config ecosystem needs a deliberate policy
   (allowlist? strip `os.execute`/`io`? opt-in?). **Not decided here** — flagged for Q8.
2. **Item schema shape (Q5) — minimal, deliberately.** `BarItem` is `id` + immutable
   `position` (left/center/right) + mutable `icon`/`label`; `:set` also takes a transient
   `effect`. **Left out:** graphs/sliders/groups/popups/menu-bar aliases, per-item styling
   (color/font/padding), explicit ordering, click handlers. This is a concrete starting
   point for finalizing Q5, not the final schema.
3. **Render-loop lifecycle (Q4) — resolved for this architecture.** Because effects are
   **CoreAnimation-driven**, noribar runs **no app-managed display link / frame loop** at
   all (unlike sketchybar's CVDisplayLink + CGContext redraw). Idle CPU is therefore ~0% by
   construction — the only wakeups are Lua timers and discrete, self-completing effect
   animations. The **coalescing window is one run-loop turn**, defined by a single
   `DispatchQueue.main.async` flush per animator. ProMotion/120 Hz is handled by
   CoreAnimation for us. (A future graph/slider item that needs continuous animation may
   reintroduce a display link scoped to those items — out of scope for M1.)

## Manual checks still required (need a human at the screen)

The headless + bounded-live checks above are green; these last two genuinely need eyes and
are **not yet confirmed**:

1. **Visible effect.** Build the bundle and switch the frontmost app; confirm the left item's
   icon visibly animates (magic `.replace`). `./bundle.sh && open noribar.app`, then Cmd-Tab
   around. (The engine path is proven not to crash; only the *visual* result is unconfirmed.)
2. **Spaces / fullscreen / focus (carried over from Spike A, still open).** With the bar up,
   switch Spaces (Ctrl-←/→) and put an app fullscreen; confirm the bar persists / floats over
   fullscreen and never steals keyboard focus. Note: the `--selftest` `SPACES_FOR_WINDOW`
   diagnostic read **0**, but it is sampled immediately after `orderFrontRegardless()` before
   the WindowServer has committed the window to its spaces — so it is not meaningful headless;
   confirm live.

## Risks / surprises for the next milestone

- **Bundle requirement is load-bearing.** Symbol effects crash from a bare executable
  (no `CFBundleIdentifier`). `bundle.sh` is mandatory for any visual run; CI can only run the
  pure `--selftest`. Keep this in mind for any "just run the binary" tooling.
- **Coalescing semantics are a product decision.** "Last effect wins per turn" is reasonable
  but means a deliberately-stacked pair of effects within one turn silently drops one. If a
  future item type wants queued/sequential effects, the animator needs an explicit queue, not
  just collapse-to-one.
- **Binding robustness debt (from Spike B) is still open.** `stringField` silently defaults
  missing/mistyped fields; a typed reader + `luaL_argerror` validation is still a follow-up.
- **Q5/Q6 will pull hard.** Real items (graphs, variable color, the full effect matrix) will
  stress both the schema and the single-animator model; M1 only proves one icon + one effect.
