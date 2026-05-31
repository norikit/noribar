<p align="center">
  <img src="https://img.shields.io/badge/status-active-32C572?style=flat-square" alt="Status: active"/>
  <img src="https://img.shields.io/badge/ecosystem-norikit-32C572?style=flat-square" alt="Ecosystem: norikit"/>
  <img src="https://img.shields.io/badge/license-AGPL--3.0-blue?style=flat-square" alt="License: AGPL-3.0"/>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/norikit/norikit/main/assets/noribar/hero/dark_theme.svg"/>
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/norikit/norikit/main/assets/noribar/hero/light_theme.svg"/>
    <img src="https://raw.githubusercontent.com/norikit/norikit/main/assets/noribar/hero/light_theme.svg" alt="noribar" width="100%"/>
  </picture>
</p>

<p align="center">
  A fast, fully-customizable <strong>macOS menu bar replacement</strong> for the ricing community —<br/>
  written in Swift, inspired by <a href="https://github.com/FelixKratz/SketchyBar">sketchybar</a>,<br/>
  and built around <strong>native, fully-animated SF Symbols</strong>.<br/>
  Part of the <strong><a href="https://github.com/norikit">norikit</a></strong> ecosystem.
</p>

> [!NOTE]
> Active development. The first product skeleton (M1) is built and running. Not yet a daily driver — see [project status](docs/knowledge-base/status.md).

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

Both foundational de-risking spikes are **complete (GO)**, and **M1 — the integration tracer
bullet** has landed: the spikes are joined into the first product code under
[`Sources/`](Sources/).

- [Spike A](tasks/spike-a/task.md) — AppKit symbol effects inside a SkyLight-empowered
  window. **✅ GO** ([D6](docs/knowledge-base/decisions.md)).
- [Spike B](tasks/spike-b/task.md) — embedded Lua driving a live, hot-reloadable bar.
  **✅ GO** ([D7](docs/knowledge-base/decisions.md)).
- [M1](tasks/m1-tracer-bullet/task.md) — Lua command stream → SkyLight-hosted symbol-effect
  tree. **✅ built:** a `config.lua` drives the bar, the `FrontAppProvider` swaps an icon with
  a native effect, and the one-animation-per-view rule (D6) is enforced by `SymbolAnimator`
  and verified under a live 0.1 s stress loop with no RenderBox crash. See its
  [findings](tasks/m1-tracer-bullet/FINDINGS.md).

All work is tracked on the [task board](tasks/README.md); progress in
[status.md](docs/knowledge-base/status.md).

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

Requires macOS 13+ and a Swift toolchain.

```sh
# Headless self-test (no window): the D6 animation-safety invariant, Lua crash isolation,
# and a hot-reload leak check. Suitable for CI.
swift run noribar --selftest

# The live bar. NOTE: native SF Symbol effects need a real .app bundle — the animation
# engine (RenderBox) crashes from a bare executable — so to SEE effects, bundle first:
./bundle.sh && open noribar.app

# Stress the one-animation-per-view rule (D6) on a real display:
./bundle.sh && ./noribar.app/Contents/MacOS/noribar --stress
```

Edit [`config.lua`](config.lua) while noribar runs to **hot-reload** it. Product code lives
under [`Sources/`](Sources/) (`CLua` = vendored Lua; `noribar` = the app, split into
`Window` / `Render` / `Model` / `Lua` / `Providers`). The throwaway spike code under
[`tasks/`](tasks/) is **not** the product.

## License

[AGPL-3.0](LICENSE).
