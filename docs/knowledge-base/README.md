# noribar knowledge base

This directory is the **single source of truth** for noribar's design intent and
project knowledge. It is the knowledge base every AI agent and contributor should read
before working in this repo. (AI agents: the repo entry point is the root
[`CLAUDE.md`](../../CLAUDE.md), which points here.)

## Contents

| File | Purpose |
|---|---|
| [decisions.md](decisions.md) | **Locked** architectural decisions + rationale (ADR-style). Constraints, not suggestions. |
| [architecture.md](architecture.md) | The evolving system design — modules, data flow, threading, render loop. |
| [open-questions.md](open-questions.md) | Unresolved design forks awaiting decisions. |
| [sketchybar-reference.md](sketchybar-reference.md) | How sketchybar (the inspiration) is implemented, and where we differ. |
| [why-swift.md](why-swift.md) | Rationale dossier — performance comparison + what the Swift/AppKit/Lua stack buys us over sketchybar, with honest counterweights. |
| [glossary.md](glossary.md) | Domain terms — SkyLight/SLS, ricing, SF Symbol effects, etc. |
| [status.md](status.md) | Current phase + dated changelog of meaningful progress. |
| [../spikes/](../spikes/) | De-risking spike briefs (handoff specs for focused experiments). |

## Maintenance protocol (read this)

Keeping this current is a **standing requirement**, not optional cleanup:

- **A decision is made** → record it in [decisions.md](decisions.md); if it resolves an
  open question, remove that entry from [open-questions.md](open-questions.md).
- **The design changes** → update [architecture.md](architecture.md) in the same change.
- **Meaningful progress happens** → append a dated line to [status.md](status.md).
- **A new knowledge-base doc is added** → link it in the table above.
- **A user-facing fact changes** (goals, status, build) → update the root
  [README.md](../../README.md).

Rule of thumb: **if you change reality, change the knowledge base in the same change.**
Stale docs are worse than none.

## How to use this as an agent

1. Read [decisions.md](decisions.md) first — these are hard constraints.
2. Skim [architecture.md](architecture.md) and [status.md](status.md) for current state.
3. Check [open-questions.md](open-questions.md) before proposing anything that might
   already be under discussion.
4. Do the work. Update the relevant file(s) here as part of the same change.
