# CLAUDE.md — entry point for AI agents working in noribar

**You are working on `noribar` (a project of the `norikit` org): a Swift macOS menu bar
replacement, inspired by sketchybar, built around native animated SF Symbols, for the
ricing community.**

This file is the front door. Before doing substantive work, read the knowledge base.

## ⇒ Start here: the knowledge base

All durable project knowledge lives in **[`docs/knowledge-base/`](docs/knowledge-base/)**.
It is the single source of truth for design intent — code may not exist yet, but the
decisions do. Read these in order:

1. **[decisions.md](docs/knowledge-base/decisions.md)** — locked architectural choices.
   Treat as constraints; do not relitigate without explicit user direction.
2. **[architecture.md](docs/knowledge-base/architecture.md)** — the evolving system design.
3. **[open-questions.md](docs/knowledge-base/open-questions.md)** — what's still undecided.
4. **[status.md](docs/knowledge-base/status.md)** — current phase + changelog.
5. **[sketchybar-reference.md](docs/knowledge-base/sketchybar-reference.md)** and
   **[glossary.md](docs/knowledge-base/glossary.md)** — reference as needed.

The knowledge base is the durable **design** truth. For **what is being worked on right
now** — and what to pick up next — read the task board at **[`tasks/`](tasks/)**
([tasks/README.md](tasks/README.md)) alongside [status.md](docs/knowledge-base/status.md).

## The locked decisions (do not violate without instruction)

- **Swift**, targeting **macOS 13+** (features degrade gracefully on older versions).
- **Rendering:** AppKit + CALayer view tree — chosen so native SF Symbol effects work.
- **Window:** private SkyLight (SLS/CGS) APIs — all-Spaces, over-fullscreen, non-activating.
- **Config:** embedded **Lua**.
- SF Symbol effects require macOS 14+; draw-on/off require macOS 26 / SF Symbols 7 —
  always gate them behind `if #available`.

## Your responsibility: keep the knowledge base current

**This is a standing instruction from the project owner.** Whenever you make a decision,
land a change, or learn something durable:

- Update the relevant file in `docs/knowledge-base/` **in the same change**.
- When a decision is made → add/update [decisions.md](docs/knowledge-base/decisions.md).
- When the design changes → update [architecture.md](docs/knowledge-base/architecture.md).
- When a question is resolved → record it in decisions/architecture and replace its entry in
  [open-questions.md](docs/knowledge-base/open-questions.md) with a one-line resolved-pointer.
- When you start or finish a task → update its `status:` in `tasks/<id>/task.md` and the
  status column in [tasks/README.md](tasks/README.md).
- Append a dated line to [status.md](docs/knowledge-base/status.md) for meaningful progress.
- Update [README.md](README.md) when user-facing facts (goals, status, build steps) change.
- If you add a new knowledge-base file, link it from
  [docs/knowledge-base/README.md](docs/knowledge-base/README.md).

Stale docs are worse than no docs. If you change reality, change the knowledge base.

## Git workflow: always branch, always PR

**This is a standing instruction from the project owner.** Never commit directly to `main`.

- **Always work on a dedicated work branch.** Before making changes, create one off `main`
  (e.g. `git checkout -b <descriptive-branch>`). If you find yourself on `main`, branch
  first.
- **Branch from an up-to-date `main`, and keep `main` up to date.** Before creating a new
  work branch, sync first: `git fetch origin` and base the branch on the latest `origin/main`
  (e.g. `git checkout -b <descriptive-branch> origin/main`), and fast-forward your local
  `main` to `origin/main` (`git checkout main && git pull --ff-only`) so it never drifts.
  This keeps every branch current with `main` from the start and avoids stale-base conflicts.
  (After a PR merges, fetch again so the next branch starts from the merged state.)
- **Open a pull request when you consider the task complete.** Push the branch and run
  `gh pr create` with a clear title and a body summarizing what changed and why (and how it
  was verified). Treat the PR as the deliverable — a task is not "done" until its PR exists.
- **Keep the PR current.** Any follow-up change to the same task — new commits, scope
  changes, fixes from review — must also update the PR: push the commits and edit the PR
  title/body (`gh pr edit`) so it always reflects the latest state of the branch.
- Commit messages and PR bodies should be self-explanatory. License is AGPL-3.0.

## Conventions

- Match surrounding Swift style; favor clarity and low-latency, main-thread-safe UI code.
- All work items (spikes, milestones, chores) live as task folders under `tasks/` — see
  [`tasks/README.md`](tasks/README.md). Each task is a folder with a `task.md` (stateful
  frontmatter + brief), optional `FINDINGS.md`, and, for PoC/research tasks, a `code/`
  subdir. That throwaway PoC code is explicitly **not** the product; real product code will
  live under `Sources/` at the repo root.
