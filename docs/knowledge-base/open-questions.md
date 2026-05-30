# Open questions

Unresolved design forks, roughly ordered by how much they constrain everything else.
When one is resolved, record the decision in [decisions.md](decisions.md) /
[architecture.md](architecture.md) and delete it here.

The four most consequential forks (render backend, window layer, config model, macOS
floor) are **already decided** — see [decisions.md](decisions.md) D2–D5.

> **Q1 (AppKit-in-SLS bridge) — RESOLVED 2026-05-30** by
> [Spike A](../spikes/spike-a-render-window.md). Outcome locked in
> [decisions.md D6](decisions.md): public non-activating `NSPanel` owns the view tree,
> SLS applied additively. See [findings](../../spikes/spike-a/FINDINGS.md).

> **Q2 (Lua runtime + threading model) — RESOLVED 2026-05-30** by
> [Spike B](../spikes/spike-b-lua-runtime.md). Outcome locked in
> [decisions.md D7](decisions.md): vanilla Lua 5.4.7 as a SwiftPM C target, on a dedicated
> serial queue, `pcall`+instruction-hook crash isolation, `lua_close`-based hot reload.
> See [findings](../../spikes/spike-b/FINDINGS.md).

---

### Q3 — Event / provider system
In-process native providers (workspace, battery, network, audio, clock, front app) with
Lua callbacks — and do we also support external script plugins as an escape hatch /
sketchybar-compat? Event taxonomy and subscription API.

### Q4 — Render loop & redraw scoping
How much to lean on CoreAnimation implicit animation vs. an explicit animator. Per-item
dirty redraw vs. full-bar. Display-link lifecycle (idle teardown). ProMotion handling.

### Q5 — Item / component data model
The schema users configure against: item types (label, icon/symbol, graph, slider,
group, popup, alias of real menu-bar apps?), property set, layout regions
(left/center/right), ordering, and how Lua mutates it.

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
bar with one animated symbol provider proves the whole risky stack end-to-end).
