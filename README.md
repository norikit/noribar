# noribar

A fast, fully-customizable **macOS menu bar replacement** for the ricing community —
written in Swift, inspired by [sketchybar](https://github.com/FelixKratz/SketchyBar),
and built around **native, fully-animated SF Symbols**.

A [**norikit**](https://github.com/norikit) project.

> **Status:** de-risking complete — both foundational spikes are GO; building the first
> product skeleton. Not yet usable. See [project status](docs/knowledge-base/status.md).

## Why another bar?

`sketchybar` set the bar (pun intended) for customizable macOS status bars, but it draws
everything with raw CoreGraphics — which means SF Symbols are static font glyphs. It
cannot use Apple's symbol animation engine.

`noribar` is built on an **AppKit + CALayer** rendering core specifically so it can
render **fully-featured SF Symbols** with native effects — draw-on / draw-off,
magic `.replace`, variable color, hierarchical/palette/multicolor rendering — while
keeping the low-latency, all-Spaces, over-fullscreen window behavior power users expect.

## Why noribar?

Beyond the animated symbols, choosing Swift + AppKit + embedded Lua over sketchybar's
C + CoreGraphics + shell-script model buys you:

- **Animated SF Symbols, natively.** Apple's symbol-effect engine — a category
  sketchybar's static font glyphs simply can't enter.
- **No shell-script zoo.** System info (battery, network, audio, workspace, front app)
  comes from in-process native providers, not by spawning `pmset` / `ifconfig` /
  `osascript` on every tick — lower latency, richer data, nothing to glue together.
- **Real configuration.** Embedded Lua gives you variables, functions, reusable modules,
  and hot-reload — shareable configs for the ricing community, not imperative CLI calls.
- **Stays out of your way.** Display-synced rendering that idles to **~0% CPU** when
  nothing is animating (measured at 0.0% in the rendering spike).
- **Built to last & to hack on.** A memory-safe Swift codebase that's friendlier to
  contribute to, and that degrades gracefully back to macOS 13.

The full engineering rationale (with honest trade-offs vs. sketchybar) lives in
[why-swift.md](docs/knowledge-base/why-swift.md).

## Goals

- **Native SF Symbol effects** as a first-class feature, not an afterthought.
- **Low latency & smooth animations** — display-synced rendering, idle to ~0% CPU.
- **Powerful, shareable configuration** via embedded **Lua** (Hammerspoon / AwesomeWM
  style), not per-event shell-script spawning.
- **Ricing-grade window control** — all Spaces, over fullscreen, non-activating,
  capable of replacing the system menu bar.
- A clean, documented, contributor-friendly open-source codebase.

## Core design decisions (locked)

| Axis | Decision |
|---|---|
| Language / platform | Swift, macOS |
| Rendering backend | AppKit + CALayer view tree |
| Window layer | Private SkyLight (SLS/CGS) APIs |
| Configuration | Embedded Lua |
| Minimum macOS | 13 (Ventura); newer features degrade gracefully (SF Symbol effects 14+; draw-on/off macOS 26 / SF Symbols 7) |

Full rationale: [decisions.md](docs/knowledge-base/decisions.md).

## Project status

Both foundational de-risking spikes are **complete (GO)** — the two riskiest unknowns are
resolved and the project is moving to its first product skeleton:

- [Spike A](tasks/spike-a/task.md) — AppKit symbol effects inside a SkyLight-empowered
  window. **✅ GO:** native effects at 0.0% idle CPU in a non-activating `NSPanel` with SLS
  applied additively (locked as [D6](docs/knowledge-base/decisions.md)).
- [Spike B](tasks/spike-b/task.md) — embedded Lua driving a live, hot-reloadable bar.
  **✅ GO:** vanilla Lua 5.4.7 on a dedicated serial queue, ~1.7 µs/tick, crash-isolated and
  hot-reloadable (locked as [D7](docs/knowledge-base/decisions.md)).

**Next:** [M1 — the integration tracer bullet](tasks/m1-tracer-bullet/task.md), wiring the
Lua command stream into the SkyLight-hosted symbol-effect tree. All work is tracked on the
[task board](tasks/README.md); progress in [status.md](docs/knowledge-base/status.md).

## Documentation

All design knowledge lives in the **[knowledge base](docs/knowledge-base/)**:

- [Decisions](docs/knowledge-base/decisions.md) — locked architectural choices + rationale
- [Why Swift](docs/knowledge-base/why-swift.md) — perf comparison + stack benefits vs. sketchybar
- [Architecture](docs/knowledge-base/architecture.md) — system design (evolving)
- [Open questions](docs/knowledge-base/open-questions.md) — unresolved design forks
- [sketchybar reference](docs/knowledge-base/sketchybar-reference.md) — how the inspiration works
- [Glossary](docs/knowledge-base/glossary.md) — SLS, ricing, SF Symbol terms
- [Status](docs/knowledge-base/status.md) — current phase + changelog

Active work (spikes, milestones, chores) is tracked as task folders under
[`tasks/`](tasks/) — see the [task board](tasks/README.md).

> **Working in this repo with an AI agent?** Start at [`CLAUDE.md`](CLAUDE.md).

## Building

_Not yet — the de-risking spikes are complete but the product skeleton hasn't been built.
Each piece of work lives as a task folder under [`tasks/`](tasks/) (brief + findings +
any throwaway PoC code); that spike code is **not** the product._

## License

[AGPL-3.0](LICENSE).
