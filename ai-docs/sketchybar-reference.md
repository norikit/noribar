# sketchybar reference

How [sketchybar](https://github.com/FelixKratz/SketchyBar) (the inspiration) is built,
and where noribar deliberately differs. Confirmed from source on 2026-05-30.

## One-paragraph summary

A C daemon that owns a **private SkyLight window**, redraws it with hand-written
**CoreGraphics** synced to a **CVDisplayLink**, and is configured/driven entirely over
**Mach IPC** by shell scripts. Fast and minimal — at the cost of modern SF Symbol
effects and a friendly config story.

## Details

- **Language / process model:** ~95% C, ~4% Obj-C. One long-lived **daemon** + a thin
  **CLI client**; the `sketchybar` binary you call in config just ships commands.
- **Window (private SkyLight):** `SLSNewWindowWithOpaqueShapeAndContext`,
  `SLSSetWindowResolution(2.0)`, `SLSSetWindowTags`, `SLSSetWindowOpacity`,
  `SLSSetWindowLevel`, `SLSOrderWindow`. All-Spaces stickiness via its **own space**:
  `SLSSpaceCreate` → `SLSSpaceSetAbsoluteLevel` →
  `SLSSpaceAddWindowsAndRemoveFromSpaces`. Explicit per-OS code forks
  (Monterey/Ventura/Sonoma) — the maintenance tax of going private.
- **Rendering (raw CoreGraphics):** draws into a `SLWindowContextCreate` CGContext:
  `CGContextClearRect` → draw → `CGContextFlush` → `SLSFlushWindowContentRegion`,
  batched inside `SLSDisableUpdate` / `SLSTransactionCreate` / `SLSTransactionCommit`.
  **SF Symbols are static font glyphs — no symbol-effect engine.** ← our key differentiator.
- **Animation (CVDisplayLink):** display link fires `animation_frame_callback` at refresh
  → posts `ANIMATOR_REFRESH` → `animator_update()` interpolates (linear / tanh / sine /
  quadratic / exp / circular) → marks `bar_item_needs_update()` or global
  `bar_needs_update`. Animations chain via next/prev pointers. **The display link tears
  down when nothing animates (idle = ~0% CPU)** — the single most important perf lesson
  to copy.
- **IPC (Mach ports):** not a Unix socket. CLI serializes SET/ADD/REMOVE/QUERY structs
  to a registered Mach port; daemon replies on `msgh_remote_port`. Chosen for latency.
- **Config:** imperative **shell script** (`sketchybarrc`) calling the CLI; everything
  mutable at runtime.
- **Events / plugins:** event-driven; the daemon **spawns external scripts per event**
  to recompute item content. Simple and language-agnostic, but process-spawn-per-tick is
  its performance floor and biggest UX friction.

## Where noribar differs (and why)

> For the full performance comparison and the non-perf benefits of our stack, see
> [why-swift.md](why-swift.md).


| Aspect | sketchybar | noribar |
|---|---|---|
| Language | C | Swift ([D1](decisions.md)) |
| Rendering | raw CoreGraphics, static glyphs | AppKit + CALayer, **native SF Symbol effects** ([D2](decisions.md)) |
| Config | imperative shell + CLI | embedded **Lua** ([D4](decisions.md)) |
| Reactivity | spawn a script per event | in-process providers + Lua callbacks ([Q3](open-questions.md)) |
| Window | private SkyLight | private SkyLight ([D3](decisions.md)) — **same** |
| Anim driver | CVDisplayLink, idle teardown | same principle ([Q4](open-questions.md)) |

## Reference repos

- `FelixKratz/SketchyBar` — `src/window.c`, `src/animation.c`, `src/message.c`.
- `NUIKit/CGSInternal` — private CGS/SLS header collection.
- `koekeishiya/yabai` — clean `extern` declarations for SLS functions (`src/misc/extern.h`).
