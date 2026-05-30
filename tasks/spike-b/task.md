---
id: spike-b
name: Embedded Lua runtime driving a live, hot-reloadable bar
type: spike
status: complete
verdict: GO
created: 2026-05-30
updated: 2026-05-30
resolves: [Q2]
decisions: [D7]
depends_on: []
artifacts: ./code
findings: ./FINDINGS.md
---

# Spike B — Embedded Lua runtime driving a live, hot-reloadable bar

> **This is a self-contained brief for an autonomous coding agent.** You have no prior
> context on this project. Everything you need is below. This is a **throwaway
> de-risking spike**, not production code. Do not build the real product. Answer the
> question, measure, and report.

## Background

`noribar` is an open-source macOS menu-bar replacement written in **Swift**,
inspired by `sketchybar`, aimed at the "ricing" (desktop customization) community.

Four foundational decisions are **already locked** and not up for debate:

1. **Rendering backend: AppKit + CALayer** (not the focus of this spike).
2. **Window strategy: private SkyLight APIs** (NOT this spike — deliberately avoid it).
3. **Config: embedded Lua.** Users configure and *drive* the bar with Lua scripts,
   Hammerspoon / AwesomeWM style — chosen for power and shareability over the
   imperative shell-CLI model that `sketchybar` uses.
4. **macOS floor: 13 (Ventura).**

## The risk this spike must resolve

`sketchybar` reacts to events by **spawning an external shell script per event** —
simple but slow and clunky. We want an **embedded Lua runtime** instead: a persistent
VM that loads the user's config, builds the bar's state, and runs live callbacks
(timers, event handlers) that mutate that state.

The unknowns:

- **Embedding mechanics:** how to compile/link Lua into a Swift macOS app and bridge
  Swift ↔ Lua cleanly.
- **Threading:** a `lua_State` is single-threaded and not thread-safe; AppKit UI is
  main-thread-only. What is the safe model for "Lua produces state changes → UI applies
  them"?
- **Hot reload:** re-running an edited config without restarting the app, without
  crashing or leaking.
- **Robustness:** a buggy user script must **not** crash the app.
- **Overhead:** is per-tick Lua→Swift call cost acceptable for a bar updating a few
  times per second?

> **Important — stay decoupled from Spike A.** Render the bar in a plain, ordinary
> `NSWindow` using public AppKit only. Do **not** use SkyLight/private APIs here. This
> keeps Spike B independent so it can run concurrently with Spike A.

## The precise question (go/no-go)

> Can an embedded Lua runtime drive a **live, hot-reloadable** bar-state model from a
> Swift macOS app — with a clean bindings API, a safe Lua↔main-thread model, crash
> isolation for user-script errors, and acceptable per-tick overhead?
> And which **Lua distribution** and **threading model** should the real project adopt?

## Lua distribution options to evaluate

Pick a **primary** and briefly assess the alternatives:

- **Vanilla Lua 5.4** compiled as a SwiftPM **C target** (drop in the Lua C sources)
  with hand-rolled Swift bindings over the C API (`lua_State`, `lua_pcall`,
  `lua_pushcfunction`, registry, etc.). Most control, smallest dependency, matches
  "embed a runtime." **Recommended primary.**
- **A Swift Lua wrapper library** (e.g. a `swift-lua` / `LuaSwift`-style package) — may
  speed binding work; assess maintenance, API ergonomics, and whether it pins an OS or
  Lua version.
- **LuaJIT** — faster + FFI, but Lua 5.1 semantics. Note Apple-Silicon support status
  and whether the speed matters for a status bar (it almost certainly does not). Assess
  briefly; do not adopt unless there's a clear reason.

State your choice and the reasoning in the findings.

## Threading model to validate

Implement and confirm this (or document a better one you find):

- The Lua VM runs on a **dedicated serial queue / thread** (one `lua_State`, one
  thread, always).
- Lua callbacks mutate an in-memory bar-state model and/or emit **state-change
  commands**.
- Those commands are marshalled to **`DispatchQueue.main`** and applied to the AppKit
  views there.
- Inbound events (timers, a simulated system event) are funnelled **onto the Lua queue**
  before touching `lua_State`.
- Every entry into Lua is wrapped in `lua_pcall` (or equivalent) so a script error is
  caught, logged, and surfaced — never crashes the host.

Explicitly test/answer: is running the VM on a dedicated queue worth it, or is
main-thread-only simpler and sufficient for a bar? Give a recommendation.

## Minimum bindings API to expose to Lua

Enough surface to prove the model — keep it small but real:

```lua
-- declarative item creation
local clock = bar.add({ type = "item", position = "right", icon = "clock", label = "" })
local cpu   = bar.add({ type = "item", position = "left",  icon = "cpu",   label = "0%" })

-- mutate an item
clock:set({ label = os.date("%H:%M:%S") })

-- a repeating timer driven by the host run loop
bar.every(1.0, function()
  clock:set({ label = os.date("%H:%M:%S") })
end)

-- subscribe to a (simulated, for this spike) event
bar.subscribe("front_app_switched", function(payload)
  cpu:set({ label = payload.app })
end)
```

You may rename things; the point is: **declarative item creation, mutation, a host
timer calling back into Lua, and an event subscription** all working end to end.

## Tasks

1. Scaffold a throwaway Swift macOS **app** under `tasks/spike-b/code/` (Xcode project or
   SwiftPM executable creating an `NSApplication`). Min target macOS 13.
2. Embed the chosen Lua and get a trivial script (`print` / return a value) executing
   from Swift.
3. Build the bindings API above and a tiny bar-state model. Render it in a **plain
   `NSWindow`** as a horizontal strip of `NSTextField`/`NSImageView` items (public
   AppKit only).
4. Ship a sample `tasks/spike-b/code/config.lua` that creates items, runs a **live clock**
   updating once per second via `bar.every`, and updates an item from a **simulated
   event** (fire `front_app_switched` from a timer or a keypress).
5. Implement **hot reload**: watch `config.lua` (or a manual trigger), tear down the
   old Lua state + items, re-run the script, rebuild. Confirm no crash and no leak
   across many reloads.
6. **Crash-isolation test:** put a deliberate error (`error("boom")`, nil index, infinite
   loop guarded by an instruction-count hook) in a callback and confirm the app logs and
   survives.
7. **Measure** and record:
   - per-tick Lua→Swift→UI overhead (time one `bar.every` cycle),
   - app memory footprint with the runtime loaded,
   - hot-reload latency (edit → visible update),
   - memory after 100 reloads (leak check).

## Constraints & guardrails

- Throwaway quality is fine; the **findings** matter more than code polish.
- **No SkyLight / private window APIs** — plain `NSWindow` only (decoupling from
  Spike A). No multi-monitor, no real system providers, no item layout engine beyond a
  simple strip.
- All code stays under `tasks/spike-b/code/`. Do not touch other paths.
- Bundle/license note: record Lua's license (MIT) and how it's vendored, since this is
  an open-source project.

## Deliverable — write `tasks/spike-b/FINDINGS.md` with:

1. **Verdict (go/no-go):** one line — can embedded Lua drive a live, hot-reloadable,
   crash-isolated bar with acceptable overhead, yes/no.
2. **Recommended Lua distribution** (vanilla 5.4 / wrapper / LuaJIT) and why, including
   how it's vendored and its license.
3. **Recommended threading model** (dedicated Lua queue vs main-thread) with the
   marshalling rules, and the rationale.
4. **Bindings ergonomics:** what the API looks like, what felt clean vs awkward,
   recommendations for the real binding layer.
5. **Hot-reload + crash-isolation results:** does it work, edge cases, leak findings.
6. **Measurements:** per-tick overhead, memory, reload latency, post-100-reload memory.
7. **Risks & surprises** for the real implementation.
8. **The runnable spike code + `config.lua`** committed under `tasks/spike-b/code/`.

Keep `FINDINGS.md` skimmable and lead with the verdict.
