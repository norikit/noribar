---
id: spike-config-design-surface
name: "Spike: configuration design surface — advanced user needs vs sketchybar vs noribar"
type: spike
status: in-progress
verdict: n/a
created: 2026-05-31
updated: 2026-05-31
resolves: [Q3, Q5, Q6, Q10]
decisions: []
depends_on: [m1-tracer-bullet]
artifacts: null
findings: ./FINDINGS.md
---

# Spike: configuration design surface

**Goal:** produce an exhaustive map of advanced configuration needs, how sketchybar handles
each, and what noribar's design must support so that users never need to fork the tooling.
This is a design spike — no code — whose output drives the Lua config API and the architecture
of the element/layer/object/animation system.

**Primary directive that governs this spike:** every capability must be reachable through the
config API. Sane defaults for the 80%; full escape hatches for the 20%.

**Output:** `FINDINGS.md` with the full capability matrix and design gaps to address.
