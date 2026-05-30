---
id: spike-a
name: SkyLight window hosting live AppKit + SF Symbol effects
type: spike
status: complete
verdict: GO
created: 2026-05-30
updated: 2026-05-30
resolves: [Q1]
decisions: [D6]
depends_on: []
artifacts: ./code
findings: ./FINDINGS.md
---

# Spike A — SkyLight window hosting live AppKit + SF Symbol effects

> **This is a self-contained brief for an autonomous coding agent.** You have no prior
> context on this project. Everything you need is below. This is a **throwaway
> de-risking spike**, not production code. Do not build the real product. Answer the
> question, measure, and report.

## Background

`noribar` is an open-source macOS menu-bar replacement written in **Swift**,
inspired by `sketchybar`, aimed at the "ricing" (desktop customization) community.

Four foundational decisions are **already locked** and are not up for debate:

1. **Rendering backend: AppKit + CALayer.** The bar is a tree of `NSView` /
   `NSImageView` on a layer-backed host. We chose this specifically so we get Apple's
   **native SF Symbol effects for free** (`addSymbolEffect`, magic `.replace`,
   draw-on/off, variable color) — the headline feature that `sketchybar` cannot do
   because it draws static font glyphs with raw CoreGraphics.
2. **Window strategy: private SkyLight (SLS/CGS) APIs**, sketchybar/yabai-style —
   all-Spaces, over-fullscreen, non-activating, capable of replacing the real menu bar.
3. **Config: embedded Lua** (not relevant to this spike).
4. **macOS floor: 13 (Ventura)**, with newer features degrading gracefully. SF Symbol
   effects require macOS 14+; the newest draw-on/off effects require macOS 26 /
   SF Symbols 7. Symbols render static on 13.

## The risk this spike must resolve

The central architectural risk: **`sketchybar` draws CoreGraphics directly into a raw
SkyLight window — it has no AppKit view tree.** We instead want a real AppKit view /
CALayer hierarchy (so `NSImageView.addSymbolEffect(...)` works) **hosted in a window
that still has SkyLight ricing powers** (all-Spaces, over-fullscreen, non-activating).

Nobody on the team has proven these two are compatible. **That is the only question
this spike answers.**

## The precise question (go/no-go)

> Can a single on-screen window **simultaneously**:
> 1. host a live AppKit/CALayer view tree running **native** SF Symbol effects
>    (at minimum: `.replace`/magic-replace, `.variableColor`, `.bounce`; bonus:
>    `.drawOn`/`.drawOff`),
> 2. sit pinned across the top of the screen in/over the menu-bar region,
> 3. appear on **all Spaces**,
> 4. **never steal keyboard focus / app activation** (no Dock icon, no Cmd-Tab),
> 5. ideally **float above fullscreen apps**,
>
> and if so, **which window construction approach** achieves it with the least
> fragility?

## Approaches to compare

Build and evaluate these in order. Stop escalating once one approach satisfies all
five criteria, but **document how far each got**.

- **A1 — Public APIs only (baseline).** Borderless `NSPanel`
  (`.nonactivatingPanel`), `collectionBehavior = [.canJoinAllSpaces, .stationary,
  .fullScreenAuxiliary, .ignoresCycle]`, `level` above `.mainMenu`,
  `hidesOnDeactivate = false`. Host an `NSImageView` and run symbol effects. Record
  exactly which of the 5 criteria this alone satisfies (focus stealing, all-Spaces,
  over-fullscreen are the likely gaps).
- **A2 — Public NSWindow/NSPanel + private SLS *retagging*.** Take A1's window, get
  its `CGWindowID` (`window.windowNumber`), and use private SLS calls to push it above
  fullscreen and force stickiness:
  `SLSSetWindowLevel`, `SLSSetWindowTags`/`SLSClearWindowTags`, and the space route
  (`SLSSpaceCreate` + `SLSSpaceSetAbsoluteLevel` +
  `SLSSpaceAddWindowsAndRemoveFromSpaces`). This is the **expected winner** —
  AppKit still owns the view tree (so symbol effects work), SLS only adjusts window
  placement/behavior.
- **A3 — Pure SLS window (stretch / feasibility note only).** A raw
  `SLSNewWindowWithOpaqueShapeAndContext` window with a `CALayer` tree attached to its
  context. The key question: **can `addSymbolEffect` even run without an `NSWindow`'s
  view/run-loop machinery?** You likely have to drive `CAAnimation` manually. Do not
  fully build this — spend at most a short timebox confirming whether native symbol
  effects are reachable at all in a viewless SLS window, and write up the verdict.

## Reference material (use these to get the private signatures right)

The private SLS/CGS function signatures drift across macOS versions — **confirm against
these, do not trust memory**:

- `NUIKit/CGSInternal` on GitHub — header collection for private CGS/SLS functions.
- `FelixKratz/SketchyBar` `src/window.c` — real-world window creation + per-OS forks
  (Monterey/Ventura/Sonoma code paths). Note it uses
  `SLSNewWindowWithOpaqueShapeAndContext`, `SLSSetWindowResolution`,
  `SLSSetWindowTags`, `SLSSetWindowOpacity`, `SLSSetWindowLevel`, `SLSOrderWindow`,
  and the `SLSSpace*` stickiness route.
- `koekeishiya/yabai` — `src/misc/extern.h` has clean `extern` declarations for these.

Starting point for the Swift bridge (verify each signature against the above):

```c
typedef int CGSConnectionID;
typedef int CGSSpaceID;
extern CGSConnectionID SLSMainConnectionID(void);
extern CGError SLSSetWindowLevel(CGSConnectionID cid, uint32_t wid, int level);
extern CGError SLSSetWindowTags(CGSConnectionID cid, uint32_t wid, const int tags[2], size_t maxTagSize);
extern CGError SLSClearWindowTags(CGSConnectionID cid, uint32_t wid, const int tags[2], size_t maxTagSize);
extern CGSSpaceID SLSSpaceCreate(CGSConnectionID cid, int unknown, int flags);
extern void SLSSpaceSetAbsoluteLevel(CGSConnectionID cid, CGSSpaceID sid, int level);
extern void SLSSpaceAddWindowsAndRemoveFromSpaces(CGSConnectionID cid, CGSSpaceID sid, CFArrayRef windows, int selector);
extern void SLSShowSpaces(CGSConnectionID cid, CFArrayRef spaces);
```

Expose these to Swift via a C module / bridging header (a small SwiftPM C target or an
Xcode bridging header — your choice). Window level for "above fullscreen" can be
derived from `CGWindowLevelForKey` / referenced from yabai; experiment.

## SF Symbol effect specifics to exercise

- Create symbols with `NSImage(systemSymbolName:accessibilityDescription:)`.
- Apply `NSImage.SymbolConfiguration` for rendering modes: `.monochrome`,
  `.hierarchical(...)`, `.palette(...)`, `.multicolor`; plus weight/scale; and a
  `variableValue` (0...1) demo.
- Run, gated behind `if #available`:
  - `imageView.addSymbolEffect(.bounce)` (macOS 14+)
  - `imageView.addSymbolEffect(.variableColor.iterative)` (macOS 14+)
  - magic replace: `imageView.setSymbolImage(newImage, contentTransition: .replace)`
    (macOS 14+; improved "magic replace" in SF Symbols 6 / macOS 15)
  - **bonus** `.drawOn` / `.drawOff` transitions (SF Symbols 7 / macOS 26) — these are
    the showcase effects; confirm whether the build SDK exposes them and demo if so.
- **Enumerate** which effects compile/run on the SDK available on the build machine,
  and record the minimum-OS for each in a table.

## Tasks

1. Scaffold a throwaway Swift macOS **app** (Xcode project or SwiftPM executable that
   creates an `NSApplication`) under `tasks/spike-a/code/`. App, not unit test — you need a
   real window on screen. Min deployment target macOS 13; build on the latest SDK
   available.
2. Implement A1, then A2 (and the A3 feasibility note). Put a horizontal strip across
   the top of the main screen containing 3–4 `NSImageView`s with SF Symbols.
3. Wire a trigger (a global hotkey, a timer, or a tiny click target) that fires the
   symbol effects repeatedly so they're observable and measurable.
4. **Verify the 5 criteria empirically**, not theoretically:
   - all-Spaces: switch Spaces (Ctrl-←/→) and confirm the bar stays.
   - over-fullscreen: put another app fullscreen, confirm visibility.
   - non-activating: confirm the previously focused app keeps focus and keystrokes
     when the bar appears/updates; confirm no Dock icon / not in Cmd-Tab.
5. **Measure** and record:
   - idle CPU (%) with nothing animating (target: ~0%),
   - CPU (%) during continuous symbol animation,
   - rough input→visual latency for a click-triggered effect,
   - whether animations stay smooth on a ProMotion/120 Hz display if available.
6. Capture **screenshots** (and a short screen recording if possible) of a symbol
   effect running inside the bar, plus the bar surviving a Space switch and a
   fullscreen app.

## Constraints & guardrails

- Throwaway quality is fine; clarity of the **findings** matters more than code polish.
- Do **not** implement Lua, config, multi-monitor, the item data model, or any product
  feature. Scope is strictly window + render + symbol effects.
- All code stays under `tasks/spike-a/code/`. Do not touch other paths.
- If a private API crashes or is unavailable, that is a **valid finding** — document it
  with the exact symbol/signature and OS version; do not rabbit-hole indefinitely.
- Note codesigning/entitlement/permission prompts you hit (these inform distribution).

## Deliverable — write `tasks/spike-a/FINDINGS.md` with:

1. **Verdict (go/no-go):** one line — can AppKit symbol effects live in a
   SkyLight-empowered window, yes/no.
2. **Recommended approach** (A1 / A2 / A3) and *why*, with the exact private functions
   used and per-OS caveats observed.
3. **Criteria matrix:** the 5 criteria × each approach, pass/fail with notes.
4. **Symbol-effect support table:** effect → works? → min OS → notes.
5. **Measurements:** idle CPU, animating CPU, latency, ProMotion behavior.
6. **Screenshots / recording** paths.
7. **Risks & surprises** for the real implementation (per-OS forks, permissions,
   anything fragile).
8. **The runnable spike code** committed under `tasks/spike-a/code/`.

Keep `FINDINGS.md` skimmable and lead with the verdict.
