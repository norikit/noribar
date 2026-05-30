# Architecture (evolving)

> **Status: provisional.** This describes the intended design. It will firm up as the
> spikes return and components are built. Update this file whenever the design changes.
> Locked constraints come from [decisions.md](decisions.md).

## High-level shape

A single long-lived app process composed of layered subsystems:

```
        ┌──────────────────────────────────────────────┐
        │  Lua runtime (config + live logic)            │  D4
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
        │  Window backend (private SkyLight / SLS)      │  D3
        │  - all-Spaces, over-fullscreen, non-activating│
        │  - ABSTRACTED behind a protocol boundary      │
        └──────────────────────────────────────────────┘

        ┌──────────────────────────────────────────────┐
        │  Providers (workspace, battery, net, audio,   │
        │  clock, …) → emit events into the Lua layer   │
        └──────────────────────────────────────────────┘
```

## Subsystems

### Window backend (D3)
Owns the on-screen surface via private SkyLight APIs. **Must be isolated behind a
protocol** (`WindowBackend`) so: (a) per-macOS-version SLS forks are contained, and
(b) a public-API fallback could be slotted in later. Approach **confirmed by
[Spike A](../spikes/spike-a-render-window.md)** (locked as [D6](decisions.md)): a
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
[Spike A](../spikes/spike-a-render-window.md) (D6):** serialize symbol mutations to
**one in-flight animation per item view** — stacking a `.replace` transition and a
discrete effect on one `NSImageView` in the same run-loop turn crashes RenderBox.

### Lua runtime (D4)
Single `lua_State` on a dedicated serial queue. User callbacks/timers produce
state-change commands marshalled to the main thread; inbound events are funnelled onto
the Lua queue. All Lua entries wrapped in `pcall` so user-script errors never crash the
host. Hot-reload supported. Being de-risked by
[Spike B](../spikes/spike-b-lua-runtime.md).

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

## Open architectural questions

See [open-questions.md](open-questions.md) — notably the event/provider system (#3),
render-loop scoping (#4), and the item data model (#5). (The AppKit-in-SLS bridge,
former Q1, is resolved — [D6](decisions.md).)
