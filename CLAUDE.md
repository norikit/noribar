# CLAUDE.md — entry point for agents working in noribar

<!-- norikit:managed — synced from `template/CLAUDE.md`; do NOT hand-edit.
     Change the template and re-run sync_scaffold. Edit only the project region below. -->

**Read this, then the operating manual.** You are working in a repo of the **norikit** org.

## ⇒ The operating manual

**[`norikit/ai-docs/framework.md`](https://github.com/norikit/norikit/blob/main/ai-docs/framework.md)**
is the single entry point for *how we work* — task tracking, the working agreement, branching, and
quality. Read it before substantive work. The ecosystem mission/conventions live in
[`norikit/ai-docs/`](https://github.com/norikit/norikit/tree/main/ai-docs); this repo's design
knowledge lives in [`ai-docs/`](ai-docs/).

## The essentials (do not violate)

- **Work within the project — no code without a tracked issue.** Find/create a GitHub issue on the
  right board, meet Definition of Ready (typed · Priority + Size · rich description), pull one to
  In Progress, then work. Decompose big asks into an epic + sub-issues first. **GitHub issues are the
  source of truth.**
- **Always branch, always PR — never commit to `main`.** Branch off fresh `origin/main` as
  `<type>/<issue#>-<slug>` (`type ∈ feat, fix, chore, spike, docs`); Conventional-Commit messages; open
  a PR that `Closes #<issue>`; squash-merge after the gates pass (a deliberate human click — no auto-merge).
- **Standalone-first.** This tool must work on its own; ecosystem integrations (noricore, noriglaze, …)
  are optional, availability-gated enhancements — never hard dependencies.
- **Keep `ai-docs/` current in the same change.** If you change reality, change the knowledge base in the
  same PR. Stale docs are worse than none.
- **Definition of Done:** merged via PR · `ai-docs` updated · CI green · behavior **verified** (not just
  green CI) · standalone-first respected · no token/scaffold leftovers. (The issue form carries the checklist.)

## Conventions

- Match surrounding code style; favor clarity and low-latency, main-thread-safe code.
- Throwaway PoC/spike code lives in `tasks/<id>/code/` and is **not** the product; real product code
  lives under `Sources/`.
- License: **AGPL-3.0**.

<!-- /norikit:managed -->

<!-- norikit:project:start — this repo's own content; sync never overwrites between these markers. -->

## This project: noribar

**noribar** — a macOS menu-bar replacement built around native, fully-animated SF Symbols
(Swift + AppKit + a private SkyLight window + embedded Lua), inspired by sketchybar.

Durable design knowledge lives in **[`ai-docs/`](ai-docs/)** — decisions · architecture ·
open-questions · status · glossary, plus **[why-swift.md](ai-docs/why-swift.md)** and
**[sketchybar-reference.md](ai-docs/sketchybar-reference.md)**. Read **[decisions.md](ai-docs/decisions.md)** first.

### Primary architectural directive — always an escape hatch

**Standing owner instruction.** Every feature offers a sane default / simple declarative option
**and** a lower-level path with full control — defaults never limit, depth never hits a wall (e.g.
animation: easing curve *or* a Lua `(old, new, frame) → new`; layout: flow *or* absolute; sizing:
autosize *or* fixed). Apply to every API, config, and rendering decision.

### Locked decisions (see [ai-docs/decisions.md](ai-docs/decisions.md))

- **Standalone-first** — runs on its own; ecosystem integration (noricore/noriglaze) is optional,
  availability-gated.
- **Swift**, **macOS 13+** (degrade gracefully) · **AppKit + CALayer** render · private **SkyLight**
  window · embedded **Lua** config.
- SF Symbol effects are macOS 14+ (draw-on/off macOS 26 / SF Symbols 7) — gate behind `if #available`.

<!-- norikit:project:end -->
