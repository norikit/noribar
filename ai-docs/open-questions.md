# Open questions

Unresolved design forks, roughly ordered by how much they constrain everything else.
When one is resolved, record the decision in [decisions.md](decisions.md) /
[architecture.md](architecture.md) and replace its entry here with a **one-line
resolved-pointer** to the decision (see Q1/Q2 below).

The four most consequential forks (render backend, window layer, config model, macOS
floor) are **already decided** — see [decisions.md](decisions.md) D2–D5.

> **Q1 (AppKit-in-SLS bridge) — RESOLVED 2026-05-30** by
> [Spike A](../../tasks/spike-a/task.md). Outcome locked in
> [decisions.md D6](decisions.md): public non-activating `NSPanel` owns the view tree,
> SLS applied additively. See [findings](../../tasks/spike-a/FINDINGS.md).

> **Q2 (Lua runtime + threading model) — RESOLVED 2026-05-30** by
> [Spike B](../../tasks/spike-b/task.md). Outcome locked in
> [decisions.md D7](decisions.md): vanilla Lua 5.4.7 as a SwiftPM C target, on a dedicated
> serial queue, `pcall`+instruction-hook crash isolation, `lua_close`-based hot reload.
> See [findings](../../tasks/spike-b/FINDINGS.md).

---

### Q3 — Event / provider system
In-process native providers (workspace, battery, network, audio, clock, front app) with
Lua callbacks — and do we also support external script plugins as an escape hatch /
sketchybar-compat? Event taxonomy and subscription API.
→ **Partially addressed by [M1](../../tasks/m1-tracer-bullet/task.md):** the `Provider`
protocol + a real `FrontAppProvider` (`front_app_switched`) prove the
provider → Lua → render path. Still open: the full provider set, the event taxonomy, and
the external-plugin/sketchybar-compat question.

> **Q4 (Render loop & redraw scoping) — RESOLVED 2026-05-30** by
> [M1](../../tasks/m1-tracer-bullet/task.md). Locked in [decisions.md D8](decisions.md):
> **no app-managed frame loop** (CoreAnimation drives effects; idle ~0% CPU), `BarStore` as
> the single main-thread applier, and per-`NSImageView` coalescing in `SymbolAnimator`
> (one apply per run-loop turn, ≤1 animation — the D6 guard). A scoped display link may
> return only for future continuously-animating items.

### Q5 — Item / component data model
The schema users configure against: item types (label, icon/symbol, graph, slider,
group, popup, alias of real menu-bar apps?), property set, layout regions
(left/center/right), ordering, and how Lua mutates it.
→ **Minimal version landed in [M1](../../tasks/m1-tracer-bullet/task.md)** (and noted under
[D8](decisions.md)): `BarItem` = id + immutable position (left/center/right) + mutable
icon/label, with `:set` taking a transient `effect`. The full type/property model (graphs,
sliders, groups, popups, aliases, styling, ordering, click handlers) is **still open** —
finalize from this concrete starting point.

### Q6 — SF Symbol rendering spec
Pin the exact "fully-featured" surface: rendering modes (mono/hierarchical/palette/
multicolor), variable color, variable weight/scale, and the effect matrix (appear/
disappear, bounce, pulse, scale, replace/magic-move, draw-on/off, wiggle, rotate,
breathe). Per-effect minimum-OS table and macOS-13 fallback behavior.

### Q7 — Multi-display, notch, menu-bar coexistence
Per-display bars vs. one stretched bar; behavior under the notch; hide/replace Apple's
menu bar vs. float above it.

### Q8 — Permissions, distribution & versioning
No sandbox / no App Store (D3 consequence); Accessibility / Screen-Recording prompts;
Homebrew cask; signing/notarization; the WindowServer-version abstraction layer.

### Q9 — Performance contract & language boundaries
Concrete latency/CPU budget; pure Swift vs. a small C/Obj-C core for the hot SLS/CG path;
how Lua C-API bindings are produced.

### Q10 — Project identity & v1 scope
Drop-in sketchybar-config compatibility vs. a clean break; the MVP cut (a single static
bar with one animated symbol provider proves the whole risky stack end-to-end). That MVP
cut is exactly **[M1](../../tasks/m1-tracer-bullet/task.md)**; the compat question is still open.
