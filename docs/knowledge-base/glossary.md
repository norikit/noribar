# Glossary

Domain terms used across noribar's docs and code.

- **Ricing** — community practice of heavily customizing a desktop's appearance (from
  "race-inspired cosmetic enhancements"). noribar's target audience.
- **SkyLight / SLS / CGS** — the private macOS framework
  (`/System/Library/PrivateFrameworks/SkyLight.framework`) that hosts WindowServer.
  `SLS*` / `CGS*` functions are its private window/space/compositing APIs. Powerful but
  unstable across OS versions and incompatible with the App Sandbox. ([D3](decisions.md))
- **WindowServer** — the macOS display compositor and input-event router; backed by
  SkyLight.
- **CGWindowID** — the window-server identifier for a window (`NSWindow.windowNumber`).
  The handle SLS functions operate on.
- **Space** — a macOS virtual desktop. "All-Spaces" / "sticky" windows appear on every
  Space; sketchybar achieves this by creating its own space at an absolute level.
- **CVDisplayLink** — a CoreVideo timer synced to the display refresh rate; the
  recommended driver for smooth, frame-accurate animation. (Successor APIs exist on newer
  macOS — see [Q4](open-questions.md).)
- **ProMotion** — Apple's adaptive high-refresh (up to 120 Hz) displays. Animations must
  stay smooth at 120 Hz.
- **SF Symbols** — Apple's system icon set, integrated with system fonts; supports
  rendering modes and animated effects.
- **Symbol effect** — a native SF Symbol animation via `SymbolEffect` /
  `NSImageView.addSymbolEffect(...)`. Examples below. **macOS 14+** for the API.
  - **Rendering modes:** monochrome, **hierarchical**, **palette**, **multicolor**.
  - **Variable color** — animate layers by a 0…1 value (`variableValue`).
  - **Replace / magic replace** — swap one symbol for another with a matched transition
    (`setSymbolImage(_:contentTransition: .replace)`).
  - **Draw-on / draw-off** — stroke a symbol in/out. **SF Symbols 7 / macOS 26+.**
  - Others: appear, disappear, bounce, pulse, scale, wiggle, rotate, breathe.
- **Lua** — lightweight embeddable scripting language; noribar's config + live-logic
  layer ([D4](decisions.md)). MIT-licensed.
- **Provider** — a native Swift source of system state (battery, network, workspace,
  clock, …) that emits events into the Lua layer. noribar's replacement for
  sketchybar's per-event script spawning ([Q3](open-questions.md)).
- **Spike** — a throwaway, timeboxed experiment to answer one technical risk question.
  See [../spikes/](../spikes/).
