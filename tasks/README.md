# Tasks

Every discrete unit of work on **noribar** — spikes, milestones, chores — lives here as a
**task folder**, regardless of type. This is the live view of *what is being worked on*;
durable *design* truth lives in [`docs/knowledge-base/`](../docs/knowledge-base/), which
tasks link back to via their `resolves:` / `decisions:` fields.

## Current tasks

| Task | Type | Status | Verdict | Resolves | Decisions |
|---|---|---|---|---|---|
| [spike-a](spike-a/task.md) — SkyLight window hosting live AppKit + SF Symbol effects | spike | ✅ complete | GO | Q1 | [D6](../docs/knowledge-base/decisions.md) |
| [spike-b](spike-b/task.md) — Embedded Lua runtime driving a live, hot-reloadable bar | spike | ✅ complete | GO | Q2 | [D7](../docs/knowledge-base/decisions.md) |
| [m1-tracer-bullet](m1-tracer-bullet/task.md) — Lua → SkyLight symbol-effect bar | milestone | 🟡 ready | — | Q4, Q5 | — |

## Layout

Each task is a folder named by its `id`:

```
tasks/<id>/
  task.md        # REQUIRED — stateful frontmatter + the brief / description
  FINDINGS.md    # optional — results/report once the task produces them
  code/          # optional — throwaway PoC/research code (NOT the product)
```

`code/` is present only for PoC / research / testing tasks (e.g. the spikes). Real product
code lives under `Sources/` at the repo root, never under `tasks/`.

## Frontmatter schema

Every `task.md` starts with YAML frontmatter:

```yaml
---
id: spike-a                       # kebab-case, matches the folder name
name: Human-readable task title
type: spike                       # spike | milestone | chore
status: complete                  # draft | ready | in-progress | blocked | complete | superseded
verdict: GO                       # spikes: GO | NO-GO | n/a ; others: n/a
created: 2026-05-30
updated: 2026-05-30
resolves: [Q1]                    # open-questions this task closes (or will, once complete) (see knowledge-base)
decisions: [D6]                   # decisions it produced
depends_on: [spike-a, spike-b]    # other task ids this one builds on
artifacts: ./code                 # path to runnable code, or null
findings: ./FINDINGS.md           # path to the results doc, or null
---
```

### `status` values

- **draft** — being written, not ready to pick up.
- **ready** — fully specified, ready to start.
- **in-progress** — actively being worked.
- **blocked** — waiting on a dependency or decision.
- **complete** — done; results captured (and `decisions:` / `resolves:` folded into the KB).
- **superseded** — replaced by another task; keep for history, point to the replacement.

## Adding a task

1. `tasks/<id>/task.md` with the frontmatter above (`status: draft` or `ready`).
2. Add a row to the table in this file.
3. When it lands, set `status: complete`, fill `verdict` / `findings`, and record any
   `decisions:` / `resolves:` into [`docs/knowledge-base/`](../docs/knowledge-base/) **in the
   same change** (see [CLAUDE.md](../CLAUDE.md)).
