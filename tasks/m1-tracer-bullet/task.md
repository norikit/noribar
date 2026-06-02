---
id: m1-tracer-bullet
name: "Integration tracer bullet: Lua → SkyLight-hosted symbol-effect bar"
type: milestone
status: complete
verdict: n/a
created: 2026-05-30
updated: 2026-05-30
resolves: [Q4]                    # Q4 fully (→D8); Q5 + front-app slice of Q3 partially
decisions: [D8]
depends_on: [spike-a, spike-b]
artifacts: ../../Sources          # first product code (NOT throwaway) — lives at repo root
findings: ./FINDINGS.md
---

# M1 — Integration tracer bullet: Lua → SkyLight-hosted symbol-effect bar

> **This is a self-contained brief for an autonomous coding agent.** Everything you need is
> below or linked. **Unlike the spikes, this is NOT throwaway** — it is the **first real
> product code**, the seed of `noribar`'s `Sources/` tree. Write it clean, keep it, and
> expect it to grow. But keep the **scope** tight: prove the seam, don't build the whole bar.

## Background

`noribar` is an open-source macOS menu-bar replacement written in **Swift**, inspired by
`sketchybar`, aimed at the "ricing" community. Its headline feature is **native, animated
SF Symbols** driven by a **user's embedded Lua config**.

Seven decisions are **locked** (see [`ai-docs/decisions.md`](../../ai-docs/decisions.md)) —
treat them as constraints, do not relitigate:

- **D1** Swift, **D5** macOS 13 floor with graceful degradation.
- **D2** Rendering: AppKit + CALayer view tree (so native SF Symbol effects work).
- **D3 / D6** Window: a borderless **non-activating `NSPanel`** owns the AppKit view tree;
  its `CGWindowID` is **additively** retagged via private SkyLight (SLS), symbols bound with
  `dlsym(RTLD_DEFAULT, …)`, all behind a `WindowBackend` boundary.
- **D4 / D7** Config: **embedded vanilla Lua 5.4.7** (SwiftPM C target), one `lua_State` on a
  **dedicated serial queue**, callbacks emit commands marshalled to `DispatchQueue.main`,
  `lua_pcall` + instruction-count hook for crash isolation, kqueue hot-reload.

**Both de-risking spikes are complete (GO)** and their code already lives in-repo:
- [Spike A](../spike-a/task.md) — [findings](../spike-a/FINDINGS.md),
  code in [`tasks/spike-a/code/`](../spike-a/code/): the SLS bridge
  ([`SLS.swift`](../spike-a/code/Sources/SpikeA/SLS.swift)), the panel
  ([`BarPanel.swift`](../spike-a/code/Sources/SpikeA/BarPanel.swift)), the symbol strip
  ([`SymbolStrip.swift`](../spike-a/code/Sources/SpikeA/SymbolStrip.swift)).
- [Spike B](../spike-b/task.md) — [findings](../spike-b/FINDINGS.md),
  code in [`tasks/spike-b/code/`](../spike-b/code/): the Lua VM
  ([`LuaVM.swift`](../spike-b/code/Sources/SpikeB/LuaVM.swift)), the command model
  ([`BarModel.swift`](../spike-b/code/Sources/SpikeB/BarModel.swift)), the hot-reload
  watcher ([`HotReload.swift`](../spike-b/code/Sources/SpikeB/HotReload.swift)), and the
  vendored Lua ([`tasks/spike-b/code/Sources/CLua/`](../spike-b/code/Sources/CLua/)).

## The risk this milestone resolves

The two spikes were **deliberately decoupled so they could run concurrently**: Spike A drove
a **hard-coded** symbol strip in an SLS panel; Spike B drove its `BarCommand` stream into a
**plain `NSWindow`** with no symbol effects. **Nobody has yet driven the Lua command stream
into the SLS-hosted CALayer tree and fired a native symbol effect from a Lua callback.**

That seam is the last structural unknown before real product work, and it is where the two
spikes' constraints **collide**:

- **D6's hard rule** — *one in-flight symbol animation per `NSImageView`* (stacking a
  `.replace` transition and a discrete effect on one view in the same run-loop turn crashes
  RenderBox). The command applier must **serialize / coalesce symbol mutations per item**.
- **D7's threading rule** — Lua emits commands on its serial queue; they must be marshalled
  to `.main` and applied there, and **rapid `:set`s must coalesce** so a fast Lua timer can't
  stack two animations on one view in one turn.

## The precise goal (definition of done)

> A single `noribar` app process where a **user-editable `config.lua`** declares bar items;
> a **Lua timer and a real native provider** mutate them at runtime; those mutations flow
> Lua-queue → `BarCommand` → main thread → an **AppKit/CALayer item in the SLS-retagged
> `NSPanel`**; and at least one mutation **fires a native SF Symbol effect** (e.g. magic
> `.replace` or `.bounce`) **without ever crashing RenderBox** — all hot-reloadable and
> crash-isolated, at ~0% idle CPU.

If that runs end-to-end, the architecture is proven integrated and the product skeleton
exists.

## What to build

Promote the proven pieces of both spikes into a clean product package and wire the seam
between them. **Reuse, don't rewrite**, the parts the spikes already validated.

### Package layout (proposed — adjust if you have a better structure)

```
Package.swift                 SwiftPM, macOS 13+, products: CLua (C) + noribar (executable)
Sources/
  CLua/                       lifted verbatim from tasks/spike-b/code (vendored Lua 5.4.7 + shims)
  noribar/
    main.swift                NSApplication bootstrap, .accessory policy / LSUIElement
    Window/
      WindowBackend.swift     protocol boundary (D3/D6) — abstracts the surface
      SkyLightPanel.swift     non-activating NSPanel + additive SLS retag (from Spike A)
      SLS.swift               dlsym SLS bridge (lifted from Spike A)
    Render/
      BarView.swift           layer-backed NSView host; left/center/right regions
      ItemView.swift          one NSImageView + label per item; the single-animator unit
      SymbolAnimator.swift    per-item serialization / coalescing of symbol mutations (D6)
    Model/
      BarItem.swift           item schema (Q5, minimal)
      BarCommand.swift        .add / .set / .remove / .clear (+ effect) (from Spike B)
      BarStore.swift          main-thread item registry; applies commands
    Lua/
      LuaRuntime.swift        lua_State on serial queue, pcall, hook, hot-reload (from Spike B)
      Bindings.swift          bar.add / item:set / bar.every / bar.subscribe
    Providers/
      Provider.swift          protocol: a native source that emits events into Lua
      FrontAppProvider.swift  NSWorkspace front-app changes → "front_app_switched"
  config.lua                  sample: clock via bar.every + a symbol effect on front-app switch
bundle.sh                     wrap into noribar.app (Spike A has a working template)
```

### The seam (the actual new work)

1. **`BarStore` on main** holds `id → ItemView`. It is the single place that applies
   `BarCommand`s. `LuaRuntime.emit` does `DispatchQueue.main.async { store.apply(cmd) }`
   (exactly Spike B's marshalling rule).
2. **`SymbolAnimator` enforces D6.** Each `ItemView` is a **single-animator unit**: at most
   one in-flight symbol animation. When a `:set` changes the icon and/or requests an effect,
   the animator **coalesces** rapid updates (collapse multiple queued `:set`s for the same id
   within a run-loop turn) and **never** applies a content-transition and a discrete effect to
   the same view in the same turn. This is the rule that prevents the RenderBox crash — build
   it deliberately and test it under a fast (`bar.every(0.1, …)`) effect loop.
3. **Bindings expose a symbol effect.** Extend `item:set` to accept an `effect` (e.g.
   `effect = "bounce" | "pulse" | "replace"`), gated behind `if #available(macOS 14, *)` with
   a static fallback on macOS 13 (D5). This is what makes a Lua callback fire a native effect.
4. **One real provider replaces the simulated event.** `FrontAppProvider` observes
   `NSWorkspace.shared.didActivateApplicationNotification`, hops onto the Lua queue, and fires
   `front_app_switched` with `{ app = <name> }` — proving the provider → Lua → render path end
   to end (Spike B only simulated this from a timer).

### Sample `config.lua` (target behavior)

```lua
local clock = bar.add({ position = "right", icon = "clock", label = "" })
local front = bar.add({ position = "left",  icon = "app.dashed", label = "—" })

bar.every(1.0, function() clock:set({ label = os.date("%H:%M:%S") }) end)

-- a real native provider drives this; the icon swap fires a native symbol effect
bar.subscribe("front_app_switched", function(p)
  front:set({ label = p.app, icon = "app.badge", effect = "replace" })
end)
```

## Hard constraints & guardrails

- **Honor D6 and D7 exactly.** They are why this milestone is hard; the whole point is to
  satisfy both at the seam. Add `dispatchPrecondition` guards (Lua queue / main) as Spike B did.
- **Keep the `WindowBackend` boundary (D3).** All SLS / `dlsym` calls live behind it so the
  per-OS forks and private APIs stay contained. The rest of the app talks to the protocol.
- **Graceful degradation (D5):** every symbol-effect path gated behind `if #available`; on
  macOS 13 the bar renders static symbols and still runs.
- **This is product code:** clear naming, no dead spike scaffolding, a short `README`. Lift
  the spikes' proven code but clean it as you promote it. Record Lua's MIT vendoring (carry
  [`VENDORING.md`](../spike-b/code/Sources/CLua/VENDORING.md) forward).

## Explicitly out of scope (defer — do NOT build)

- The full item model (graphs, sliders, groups, popups, menu-bar aliases) — **Q5**; build only
  label + icon + position for now.
- The full SF Symbol effect matrix and rendering-mode spec — **Q6**; one or two effects suffice.
- Multi-display, the notch, replacing Apple's menu bar — **Q7**.
- More than one provider; battery/network/audio/Spaces providers — **Q3** beyond the single
  front-app proof.
- Signing / notarization / Homebrew distribution — **Q8** (ad-hoc sign + `LSUIElement` is fine,
  as in Spike A).
- sketchybar-config compatibility — **Q10**.

## Open decisions to surface (don't silently pick — flag them in the findings)

1. **Lua config sandbox policy** (D7 / Q8): are `os.execute` / `io` / `require` available to
   user configs? For M1, document what you left open; do not invent a final policy.
2. **Item schema shape** (Q5): the minimal `BarItem` fields you chose and what you deliberately
   left out, so Q5 can be finalized from a concrete starting point.
3. **Render-loop lifecycle** (Q4): how the display-link / animator idles to ~0% CPU and how the
   per-item coalescing window is defined (per run-loop turn? debounced?).

## Tasks

1. Scaffold the SwiftPM package above (macOS 13 min). Lift `CLua` and the Lua runtime verbatim
   from Spike B; lift the SLS bridge + panel from Spike A behind `WindowBackend`.
2. Build the `BarStore` / `SymbolAnimator` seam honoring D6 + D7.
3. Extend the bindings with `effect`; add `FrontAppProvider`.
4. Ship the sample `config.lua`; confirm the clock ticks and a front-app switch swaps the icon
   **with a visible native effect**.
5. **Stress the D6 rule:** add a temporary `bar.every(0.1, …)` that swaps an icon + effect on
   one item and confirm **no RenderBox crash** over a few minutes. Keep this as a test/flag.
6. Re-confirm crash isolation (a deliberately broken callback logs and the app survives) and
   hot reload (edit `config.lua`, see it rebuild) survive the integration.
7. **Measure** (same axes as the spikes): idle CPU, CPU under the 0.1 s effect loop, RSS, and
   end-to-end event→visual latency.
8. **Manual 2-minute check (carried over from Spike A, still unconfirmed):** run the app, switch
   Spaces (Ctrl-←/→) and put an app fullscreen, and confirm the bar persists / floats and never
   steals focus.

## Deliverables

1. The runnable product skeleton under `Sources/` + `Package.swift` + `config.lua` + `bundle.sh`.
2. A `FINDINGS.md` (lead with a one-line verdict) covering: the seam design, how D6 coalescing
   was implemented and stress-tested, the three open decisions above with what you chose/left
   open, measurements, the manual-check result, and risks/surprises for the next milestone.
3. **Knowledge-base updates in the same change** (standing project rule, see
   [`CLAUDE.md`](../../CLAUDE.md)): append to [`status.md`](../../ai-docs/status.md);
   fold the resolved parts of **Q4/Q5** (and the front-app slice of **Q3**) from
   [`open-questions.md`](../../ai-docs/open-questions.md) into
   [`architecture.md`](../../ai-docs/architecture.md) / a new decision; update
   [`README.md`](../../README.md) build steps now that there's a buildable app.

## Acceptance criteria

- `swift run noribar` shows the bar in the SLS panel; the clock ticks; a front-app switch swaps
  an icon **with a native symbol effect**; editing `config.lua` hot-reloads; a broken callback
  is logged and survived; the 0.1 s effect loop runs with **no RenderBox crash**; idle CPU ≈ 0%.
- The manual Spaces / fullscreen / focus check passes (or its failure is documented precisely).

## References

- Decisions D1–D7: [`ai-docs/decisions.md`](../../ai-docs/decisions.md)
- Architecture: [`ai-docs/architecture.md`](../../ai-docs/architecture.md)
- Open questions Q3–Q10: [`ai-docs/open-questions.md`](../../ai-docs/open-questions.md)
- Spike A findings: [`tasks/spike-a/FINDINGS.md`](../spike-a/FINDINGS.md)
- Spike B findings: [`tasks/spike-b/FINDINGS.md`](../spike-b/FINDINGS.md)
