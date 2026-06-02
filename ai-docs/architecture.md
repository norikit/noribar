# Architecture (evolving)

> **Status: provisional.** This describes the intended design. The two foundational bridges
> (window/render, Lua runtime) are now proven and locked ([D6](decisions.md)/[D7](decisions.md));
> the rest firms up as components are built. Update this file whenever the design changes.
> Locked constraints come from [decisions.md](decisions.md).

## High-level shape

A single long-lived app process composed of layered subsystems:

```
        ┌──────────────────────────────────────────────┐
        │  Lua runtime (config + live logic)            │  D4·D7
        │  - loads user config, runs timers/callbacks   │
        │  - single lua_State on a dedicated queue      │
        └───────────────┬──────────────────────────────┘
                        │ state-change commands (marshalled to main)
        ┌───────────────▼──────────────────────────────┐
        │  Core / bar-state model (main thread)         │
        │  - item tree, layout (left/center/right)      │
        │  - applies commands, drives animations        │
        └───────────────┬──────────────────────────────┘
                        │
        ┌───────────────▼──────────────────────────────┐
        │  Render layer: AppKit + CALayer               │  D2
        │  - NSView/NSImageView item tree               │
        │  - native SF Symbol effects                   │
        │  - display-synced redraw, idle→~0% CPU        │
        └───────────────┬──────────────────────────────┘
                        │ hosted in
        ┌───────────────▼──────────────────────────────┐
        │  Window backend (private SkyLight / SLS)      │  D3·D6
        │  - all-Spaces, over-fullscreen, non-activating│
        │  - ABSTRACTED behind a protocol boundary      │
        └──────────────────────────────────────────────┘

        ┌──────────────────────────────────────────────┐
        │  Providers (workspace, battery, net, audio,   │
        │  clock, …) → emit events into the Lua layer   │
        └──────────────────────────────────────────────┘
```

## Subsystems

### Window backend (D3 · D6)
Owns the on-screen surface via private SkyLight APIs. **Must be isolated behind a
protocol** (`WindowBackend`) so: (a) per-macOS-version SLS forks are contained, and
(b) a public-API fallback could be slotted in later. Approach **confirmed by
[Spike A](../../tasks/spike-a/task.md)** (locked as [D6](decisions.md)): a
borderless non-activating `NSPanel` owns the AppKit view tree; its `CGWindowID` is
retagged *additively* via SLS (prevents-activation, expose-fade, above-fullscreen
level). Private symbols are bound with `dlsym(RTLD_DEFAULT, …)` (SkyLight has no on-disk
binary). The pure-SLS viewless window is rejected — symbol effects need the AppKit host.

### Render layer (D2)
AppKit `NSView`/`NSImageView` tree on a layer-backed host. Native SF Symbol effects.
Principles to carry over from sketchybar:
- Drive animation off a **display link** synced to refresh (incl. ProMotion 120 Hz).
- **Idle to ~0% CPU** — tear down the frame driver when nothing animates.
- **Dirty-item redraw** (per-item layers) rather than full-bar repaint where possible.

### Core / bar-state model
Main-thread-owned tree of items (label, symbol/icon, graph, slider, group, popup,
menu-bar alias — TBD; see [open-questions.md](open-questions.md) #5). Receives
state-change commands, applies them, and triggers animations. **Constraint from
[Spike A](../../tasks/spike-a/task.md) (D6):** serialize symbol mutations to
**one in-flight animation per item view** — stacking a `.replace` transition and a
discrete effect on one `NSImageView` in the same run-loop turn crashes RenderBox.

### Lua runtime (D4 · D7)
Single `lua_State` on a dedicated serial queue. User callbacks/timers produce
state-change commands marshalled to the main thread; inbound events are funnelled onto
the Lua queue. All Lua entries wrapped in `pcall` so user-script errors never crash the
host. Hot-reload supported. Approach **confirmed by
[Spike B](../../tasks/spike-b/task.md)** (locked as [D7](decisions.md)): vanilla
**Lua 5.4.7** vendored as a SwiftPM C target (public API surfaced via an umbrella header
plus a `static inline` shim for Lua's function-like macros); bindings carry their Swift
context as a light-userdata upvalue and store callbacks as registry refs; crash isolation
is `pcall` **plus an instruction-count hook** (`lua_sethook`) so even an infinite loop is
aborted without freezing the UI; hot reload is `lua_close` + rebuild (leak-free over 100
reloads). Measured per-tick Lua→Swift overhead ~1.7 µs.
**To build for production (from Spike B findings):** a typed table-field reader +
`luaL_argerror` validation in the binding layer; a **sandbox policy** for user configs
(`os`/`io`/`require`); and per-item coalescing of `item:set` icon changes to honor D6's
one-animation-per-view rule.

### Providers
Native Swift sources of system state (workspace/Spaces, battery, network, audio, clock,
front app). Emit events into the Lua layer. Replaces sketchybar's per-event shell-script
spawning. Design pending (open question #3).

## Threading model (intended)

- **Main thread:** all AppKit/CALayer mutation, the bar-state model, the animator.
- **Lua queue:** the single `lua_State`; never touched off this queue.
- **Providers:** may run on their own queues; events hop to the Lua queue, resulting
  commands hop to main.

## Cross-cutting principles

- **Latency budget:** ~0% idle CPU; sub-frame input→draw; smooth at 120 Hz.
- **Graceful degradation (D5):** gate symbol effects behind `if #available`.
- **Containment:** private APIs and per-OS forks live behind boundaries, never sprayed
  through the codebase.

## The integration seam (built — M1)

Spike A and Spike B were deliberately decoupled; **[M1](../../tasks/m1-tracer-bullet/task.md)**
joined them into the first product code under `Sources/`. The seam — `BarCommand` →
main-thread renderer honoring D6's one-animation-per-view rule — now exists and is verified
(see [findings](../../tasks/m1-tracer-bullet/FINDINGS.md), locked as [D8](decisions.md)).

```
Sources/
  CLua/                 vendored Lua 5.4.7 (MIT), SwiftPM C target            (D7)
  noribar/
    Window/  WindowBackend protocol · SkyLightPanel · SLS (dlsym bridge)      (D3·D6)
    Render/  BarView (regions) · ItemView (single-animator unit) · SymbolAnimator (D2·D6·D8)
    Model/   BarItem (schema, Q5) · BarCommand · BarStore (main-thread applier) (D7·D8)
    Lua/     LuaRuntime (lua_State on serial queue) · Bindings · ConfigWatcher  (D4·D7)
    Providers/ Provider · FrontAppProvider (front-app slice of Q3)
```

Flow: `LuaRuntime` (serial queue) emits `BarCommand`s → `DispatchQueue.main.async` →
`BarStore.apply` → `ItemView`; icon/effect changes route through that item's `SymbolAnimator`,
which coalesces per run-loop turn and applies ≤1 animation (D8). `FrontAppProvider` observes
`NSWorkspace` front-app changes and fires `front_app_switched` into the Lua layer.

## Open architectural questions

See [open-questions.md](open-questions.md). Resolved so far: the AppKit-in-SLS bridge
(former Q1 → [D6](decisions.md)), the Lua runtime/threading model (former Q2 →
[D7](decisions.md)), and the render/update-loop model (former Q4 → [D8](decisions.md)). M1
also landed a concrete *minimal* item schema (a starting point for Q5) and the front-app
slice of the provider system (Q3). Still open: the full item model (Q5), the event/provider
taxonomy and external-plugin question (Q3), and the SF Symbol rendering spec (Q6).
