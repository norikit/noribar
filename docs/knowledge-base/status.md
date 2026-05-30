# Project status

**Current phase:** Architecture / de-risking. No buildable product yet.

**Next milestone:** [Spike A](../spikes/spike-a-render-window.md) is **complete (GO)** —
see [findings](../spikes/spike-a/FINDINGS.md) and [D6](decisions.md). Remaining:
run [Spike B](../spikes/spike-b-lua-runtime.md) (embedded Lua driving a live bar), then
finalize architecture. Pending follow-up: a 2-minute manual on-screen confirmation of
Spike A's all-Spaces / over-fullscreen behavior (run `spikes/spike-a/run-demo.sh`).

**Active risks being de-risked:** ~~Q1 (AppKit-in-SLS bridge)~~ **resolved** →
[Q2](open-questions.md) (Lua runtime + threading) remains.

---

## Changelog

Append a dated line for each meaningful step (newest at bottom).

- **2026-05-30** — Project kicked off. Reviewed sketchybar internals
  ([reference](sketchybar-reference.md)). Locked foundational decisions D1–D5
  ([decisions](decisions.md)): Swift/macOS, AppKit+CALayer rendering, private SkyLight
  window, embedded Lua config, macOS 13 floor with graceful degradation.
- **2026-05-30** — Authored two de-risking spike briefs
  ([Spike A](../spikes/spike-a-render-window.md),
  [Spike B](../spikes/spike-b-lua-runtime.md)), deliberately decoupled (Spike B uses a
  plain NSWindow) so they can run concurrently.
- **2026-05-30** — Established README + knowledge base (`docs/knowledge-base/`) and
  `CLAUDE.md` agent entry point.
- **2026-05-30** — Named the project **noribar** under the **norikit** org.
- **2026-05-30** — Added [why-swift.md](why-swift.md): rationale dossier consolidating the
  sketchybar performance comparison and the broader Swift/AppKit/Lua stack benefits behind
  D1/D2/D4. Cross-linked from decisions, sketchybar-reference, and the KB index.
- **2026-05-30** — **Spike A complete — verdict GO** (`spikes/spike-a/`,
  [FINDINGS.md](../spikes/spike-a/FINDINGS.md)). Native SF Symbol effects (incl. macOS 26
  draw-on/off) run inside an SLS-retagged non-activating `NSPanel` at 0.0% idle CPU
  without stealing focus. Locked outcome as [D6](decisions.md); resolved Q1. SLS bound via
  `dlsym(RTLD_DEFAULT)` (no on-disk SkyLight binary). **Constraint surfaced:** one symbol
  animation per view — RenderBox crashes when `.replace`+`.drawOn` stack on one view.
  All-Spaces/over-fullscreen configured but pending a manual on-screen check.
- **2026-05-30** — Added a user-facing **"Why noribar?"** benefits section to the root
  README (links [why-swift.md](why-swift.md)) and refreshed its status to reflect Spike A
  GO / D6. Reconciled why-swift.md's caveats with the now-proven AppKit-in-SLS bridge.
