# Project status

**Current phase:** First product skeleton **built** — milestone
[M1](../../tasks/m1-tracer-bullet/task.md) landed. Real product code now lives under
`Sources/`. Foundational architecture locked: D6/D7 (spikes) + **D8** (M1's render/update
model). Not yet a daily-driver bar.

**What's built:** a single `noribar` app where a hot-reloadable `config.lua` drives an
AppKit/CALayer bar hosted in a private-SkyLight `NSPanel`; a Lua timer and a real
`FrontAppProvider` mutate items; mutations flow Lua-queue → `BarCommand` → main thread →
`ItemView`; and an icon swap fires a **native SF Symbol effect** while honoring D6's
one-animation-per-view rule (`SymbolAnimator`). Verified: D6 invariant (headless + a live
0.1 s stress soak, no RenderBox crash), crash isolation, hot reload, ~0.2% idle CPU.

**Next:** finalize the full item model ([Q5](open-questions.md)) and SF Symbol rendering
spec ([Q6](open-questions.md)); grow the provider set + event taxonomy
([Q3](open-questions.md)); decide the Lua sandbox policy ([Q8](open-questions.md)). See the
live [task board](../../tasks/README.md).

**Pending manual on-screen checks (need a human):** (1) confirm the front-app icon effect is
visibly animating in the bundled app; (2) the carried-over Spike A check — bar persists
across Spaces / over fullscreen and never steals focus. Build with `./bundle.sh`.

**Foundational risks (retired):** ~~Q1 (AppKit-in-SLS bridge)~~ **resolved** ·
~~Q2 (Lua runtime + threading)~~ **resolved** · ~~Q4 (render/update loop)~~ **resolved**
([D8](decisions.md)).

---

## Changelog

Append a dated line for each meaningful step (newest at bottom).

- **2026-05-30** — Project kicked off. Reviewed sketchybar internals
  ([reference](sketchybar-reference.md)). Locked foundational decisions D1–D5
  ([decisions](decisions.md)): Swift/macOS, AppKit+CALayer rendering, private SkyLight
  window, embedded Lua config, macOS 13 floor with graceful degradation.
- **2026-05-30** — Authored two de-risking spike briefs
  ([Spike A](../../tasks/spike-a/task.md),
  [Spike B](../../tasks/spike-b/task.md)), deliberately decoupled (Spike B uses a
  plain NSWindow) so they can run concurrently.
- **2026-05-30** — Established README + knowledge base (`ai-docs/`) and
  `CLAUDE.md` agent entry point.
- **2026-05-30** — Named the project **noribar** under the **norikit** org.
- **2026-05-30** — Added [why-swift.md](why-swift.md): rationale dossier consolidating the
  sketchybar performance comparison and the broader Swift/AppKit/Lua stack benefits behind
  D1/D2/D4. Cross-linked from decisions, sketchybar-reference, and the KB index.
- **2026-05-30** — **Spike A complete — verdict GO** (`tasks/spike-a/code/`,
  [FINDINGS.md](../../tasks/spike-a/FINDINGS.md)). Native SF Symbol effects (incl. macOS 26
  draw-on/off) run inside an SLS-retagged non-activating `NSPanel` at 0.0% idle CPU
  without stealing focus. Locked outcome as [D6](decisions.md); resolved Q1. SLS bound via
  `dlsym(RTLD_DEFAULT)` (no on-disk SkyLight binary). **Constraint surfaced:** one symbol
  animation per view — RenderBox crashes when `.replace`+`.drawOn` stack on one view.
  All-Spaces/over-fullscreen configured but pending a manual on-screen check.
- **2026-05-30** — Added a user-facing **"Why noribar?"** benefits section to the root
  README (links [why-swift.md](why-swift.md)) and refreshed its status to reflect Spike A
  GO / D6. Reconciled why-swift.md's caveats with the now-proven AppKit-in-SLS bridge.
- **2026-05-30** — **Spike B complete — verdict GO** (`tasks/spike-b/code/`,
  [FINDINGS.md](../../tasks/spike-b/FINDINGS.md)). Vanilla **Lua 5.4.7** vendored as a SwiftPM
  C target drives a live, hot-reloadable bar in a plain `NSWindow`: declarative
  `bar.add`/`item:set`, host `bar.every` timers, and a simulated `front_app_switched`
  event all work end-to-end. One `lua_State` on a dedicated serial queue; callbacks emit
  commands marshalled to `DispatchQueue.main`. Crash isolation via `lua_pcall` + an
  instruction-count hook (`error()`, nil-index, infinite-loop all caught, app survives).
  Hot reload via `lua_close`+rebuild (in-place **and** atomic-rename saves; no leak over
  100 reloads). **Per-tick Lua→Swift ~1.7 µs**, Lua adds <1 MB RSS. Locked as
  [D7](decisions.md); resolved Q2. **Constraints surfaced for production:** macro shim
  header is mandatory; binding layer needs typed field reader + arg validation; user-config
  sandbox policy is an open security decision; `item:set` icon changes must coalesce symbol
  mutations per item to respect D6.
- **2026-05-30** — Drafted **[M1 — integration tracer bullet](../../tasks/m1-tracer-bullet/task.md)**
  brief: the first product skeleton joining Spike A + Spike B at the unproven seam (Lua command
  stream → SLS-hosted symbol-effect tree, honoring D6's one-animation-per-view rule).
- **2026-05-30** — **Reorganized work tracking into [`tasks/`](../../tasks/).** Every work
  item (spikes + the M1 milestone) now lives as a self-contained task folder
  (`task.md` with stateful frontmatter + `FINDINGS.md` + a `code/` subdir for PoC code);
  spike briefs moved out of `docs/spikes/` and spike code out of `spikes/`. The knowledge
  base remains the durable design truth; tasks cross-link to it. See the
  [task board](../../tasks/README.md).
- **2026-05-30** — **M1 (integration tracer bullet) built** — first product code under
  `Sources/` ([findings](../../tasks/m1-tracer-bullet/FINDINGS.md)). Promoted both spikes
  (CLua + Lua runtime from B; SLS bridge + non-activating panel from A) and wrote the seam:
  `BarStore` (main-thread command applier) + `SymbolAnimator` (per-`NSImageView`
  single-animator unit enforcing D6 via per-turn coalescing + a pure ≤1-animation resolver),
  `item:set{effect=}` bindings, and a real `FrontAppProvider`. Verified: D6 invariant
  (headless planner + a live 0.1 s icon+effect+`.replace` stress soak with **no RenderBox
  crash**), crash isolation, 50× hot reload, ~0.2% idle CPU, ~12 MB RSS, non-activating SLS
  panel. Locked the render/update model as [D8](decisions.md); resolved Q4; landed a minimal
  item schema (Q5 start) and the front-app slice of Q3. **Symbol effects require a real
  `.app` bundle** (`bundle.sh`) — RenderBox crashes from a bare executable. Two on-screen
  checks remain manual.
