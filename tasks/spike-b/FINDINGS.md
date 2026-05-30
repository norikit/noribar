# Spike B — Findings: embedded Lua driving a live, hot-reloadable bar

## 1. Verdict — **GO** ✅

An embedded Lua runtime can drive a **live, hot-reloadable, crash-isolated** bar from a
Swift macOS app with a clean bindings API and **negligible** per-tick overhead. Every
unknown the brief named resolved in favor of proceeding. Adopt **vanilla Lua 5.4.7**
compiled as a SwiftPM C target, run on a **dedicated serial queue**, with all Lua entries
wrapped in `lua_pcall` + an instruction-count hook.

| Risk | Result |
|---|---|
| Embedding mechanics | ✅ Lua 5.4.7 as a SwiftPM C target; one small shim header for macros. |
| Threading | ✅ One `lua_State` on one serial queue; commands marshalled to main. |
| Hot reload | ✅ `lua_close` + rebuild; in-place **and** atomic-rename saves both reload. |
| Crash isolation | ✅ `error()`, nil-index, and infinite-loop all caught; app survives. |
| Per-tick overhead | ✅ **~1.7 µs mean** Lua→Swift round-trip (a bar updates a few ×/sec). |
| Footprint / leaks | ✅ Lua adds <1 MB; **flat across 100 reloads**. |

Measured on macOS 26.3, Apple Silicon, Swift 6.3.2, debug build.

---

## 2. Recommended Lua distribution — **vanilla Lua 5.4.7, SwiftPM C target**

**Choice: vanilla Lua 5.4.7**, C sources dropped into a SwiftPM C target (`Sources/CLua`)
with hand-rolled Swift bindings over the C API. It is the smallest dependency, gives total
control, matches "embed a runtime" exactly, and builds with zero external tooling.

**Vendoring** (see [`Sources/CLua/VENDORING.md`](code/Sources/CLua/VENDORING.md)):
- All upstream `src/*.c` **except** `lua.c`/`luac.c` (those carry `main()`).
- All `src/*.h`, plus an umbrella (`clua.h`) that exposes **only** the public API to Swift,
  a `module.modulemap`, and one hand-written shim (`lua_shims.h`, below).
- Compiled with `-DLUA_USE_MACOSX`. No upstream source modified.
- **License: MIT** ([`LUA-LICENSE.txt`](code/Sources/CLua/LUA-LICENSE.txt)) — compatible with
  noribar's AGPL-3.0. SHA-256 of the tarball is recorded for reproducibility.

**The one piece of required glue:** Lua exposes much of its C API as *function-like
macros* (`lua_pcall`, `lua_pop`, `lua_pushcfunction`, `lua_tostring`, `lua_upvalueindex`…),
which Clang's importer does **not** surface to Swift. The fix is a single header of
`static inline` wrappers (`cl_*`). This is well-understood, ~50 lines, and audited in one
place. **Expect to write it; it is not a blocker.**

**Alternatives assessed:**
- **A Swift Lua wrapper** (LuaSwift / swift-lua-style packages): would save the binding
  glue, but adds a dependency that can pin an OS/Swift/Lua version and obscures the C
  boundary we want explicit control over (threading, hooks, refs). The binding layer here
  was small enough that the wrapper's value didn't justify the coupling. *Reconsider only
  if the hand-rolled binding surface balloons.*
- **LuaJIT**: 5.1 semantics (loses 5.4's integer subtype, `<close>`, etc.), and its speed
  is irrelevant for a status bar that ticks a few times per second — our measured overhead
  is already ~1.7 µs on stock 5.4. Apple-Silicon support exists but adds friction. **Not
  adopted; no clear reason.**

---

## 3. Recommended threading model — **dedicated serial Lua queue**

```
            ┌──────────────── Lua serial queue ────────────────┐
 timers ───►│  lua_State (single, never touched off this queue) │
 events ───►│  callbacks run here, under lua_pcall + count hook  │
            │            │ emit(BarCommand)                       │
            └────────────┼───────────────────────────────────────┘
                         ▼  DispatchQueue.main.async
            ┌──────────── main thread ──────────────┐
            │  BarRenderer applies commands to the   │
            │  NSView / NSStackView tree (AppKit)    │
            └────────────────────────────────────────┘
```

**Marshalling rules (validated):**
1. The `lua_State` is created on, and **only ever touched from**, one serial
   `DispatchQueue`. `dispatchPrecondition` guards enforce this.
2. Lua callbacks never call AppKit. They mutate state by emitting `BarCommand` values
   (`.add` / `.set` / `.clear`).
3. `emit` does `DispatchQueue.main.async { renderer.apply(cmd) }`. The renderer asserts
   it is on `.main`.
4. Inbound timers (`bar.every`) use a `DispatchSourceTimer` **scheduled on the Lua queue**,
   so the callback already runs on the right thread.
5. Inbound events (`fire(event:)`) hop onto the Lua queue *before* touching `lua_State`.

**Dedicated queue vs. main-thread-only — recommendation: keep the dedicated queue.**
For a bar's own ticking, main-thread-only Lua would be *simpler and sufficient* (overhead
is microseconds). But the dedicated queue earns its keep for the **infinite-loop guard**:
a runaway user script is contained on a background queue, so the instruction-hook abort
and even a (future) hard watchdog never freeze the UI. A buggy `bar.every(0.1, …)` that
spins can't lock the menu bar. That isolation is worth the modest marshalling code, and
the model is the same one Hammerspoon-style tools converge on. **Keep it.**

---

## 4. Bindings ergonomics

The brief's target API works verbatim:

```lua
local clock = bar.add({ type = "item", position = "right", icon = "clock", label = "" })
clock:set({ label = os.date("%H:%M:%S") })
bar.every(1.0, function() clock:set({ label = os.date("%H:%M:%S") }) end)
bar.subscribe("front_app_switched", function(p) cpu:set({ label = p.app }) end)
```

**What felt clean:**
- **Context via light-userdata upvalue.** Each binding is a `@convention(c)` function with
  the owning `LuaVM` pushed as `upvalue(1)` (`lua_pushlightuserdata` + `lua_pushcclosure`).
  Retrieved with `Unmanaged.fromOpaque`. No globals, supports multiple VMs later.
- **Items as a table `{ _id }` + shared metatable.** `bar.add` returns a handle whose
  metatable's `__index` carries `set`. Method-call syntax (`clock:set{…}`) falls out for
  free. The Swift side stays a flat `Int → view` map.
- **Callbacks as registry refs.** `luaL_ref(LUA_REGISTRYINDEX)` stores the Lua function;
  the host timer/event fetches it with `lua_rawgeti`. `lua_close` frees them all — no
  manual unref needed on teardown.

**What felt awkward (and the lesson for the real layer):**
- **The macro shim is unavoidable** — see §2. Centralize it; don't scatter `cl_*` calls'
  rationale.
- **Reading a Lua table field is 3 stack ops** (`getfield` / read / `pop`). For a real,
  larger property set, write **one typed `field(table, key) -> String?/Double?/Bool?`
  helper layer** rather than hand-coding stack juggling per property. This is the single
  highest-leverage cleanup for the production binding.
- **No arg validation yet.** `bar.add` with a bad `position` silently defaults. Production
  should `luaL_argerror` with a clear message so config authors get good diagnostics.

**Recommendation for the real binding layer:** a thin typed "args reader" + a small
registration helper (`register(name, fn)`), keep context-via-upvalue, keep refs-in-registry.

---

## 5. Hot reload + crash isolation

**Hot reload** — `ConfigWatcher` (a kqueue `DispatchSourceFileSystemObject`) watches
`config.lua`. On change it calls `vm.start(configURL:)`, which on the Lua queue:
`emit(.clear)` → cancel timers → `lua_close` → fresh `luaL_newstate` → rebind → re-run.

- ✅ **In-place writes** (`>>`, editors that write the same inode) reload.
- ✅ **Atomic rename-replace** (vim, many editors save temp + `mv`) reload too — the watcher
  detects the `rename`/`delete`, cancels, and **re-arms** onto the new inode.
- ✅ A **debounce** (80 ms) coalesces the multi-event bursts editors emit.
- ✅ **No leak:** `lua_close` frees the entire state including ref'd callbacks; timers are
  explicitly cancelled. RSS is flat across 100 reloads (§6).

**Edge cases noted for production:** (a) a reload whose config *errors mid-run* leaves the
items it managed to create before the error — acceptable, but production may want
"build into a staging model, swap atomically on success." (b) The watcher re-arm has a
200 ms retry if it opens during the rename gap; fine for hand-edits.

**Crash isolation** — every Lua entry goes through `protectedCall` (`lua_pcall` + a
traceback message handler) and the state has an **instruction-count hook**
(`lua_sethook(LUA_MASKCOUNT)`) that aborts a single call after a fixed budget. All three
deliberate faults were **caught and logged; the app survived every one**:

```
⚠️ lua: test:explicit-error: …: boom — deliberate            (error("boom"))
⚠️ lua: test:nil-index: …: attempt to index a nil value (local 't')
⚠️ lua: test:infinite-loop: script exceeded its instruction budget … — aborted
```

The infinite-loop case is the important one: `while true do end` was stopped by the hook
(it `lua_error`s out of the hook, unwinding to the enclosing `pcall`) **without freezing
the app**, because it ran on the background Lua queue.

---

## 6. Measurements

macOS 26.3 · Apple Silicon · Swift 6.3.2 · **debug** build (release would be faster).

| Metric | Result |
|---|---|
| **Per-tick Lua→Swift round-trip** (registry fetch → `pcall` w/ hook+traceback → `item:set` binding → command emit), 20 000 iters | **mean 1.8 µs · p50 1.5 µs · p99 2.9 µs · max 116 µs** |
| RSS baseline (AppKit process, pre-VM) | 8.7 MB |
| RSS with VM + stdlib + config loaded | 8.7 MB (**Lua adds <1 MB**) |
| RSS during 20k-iter benchmark | 12.5 MB (transient: queued main-thread commands) |
| **RSS after 100 hot reloads** | **13.0 MB — flat, no leak** |
| Hot-reload latency (edit → re-run) | dominated by the 80 ms debounce; the rebuild itself is sub-millisecond |

The `max 116 µs` outlier is a one-off (first-call warmup / scheduler), not steady state.
At a bar's realistic cadence (≤ a few updates/sec) the Lua boundary cost is **noise**.

---

## 7. Risks & surprises for the real implementation

1. **`@convention(c)` cannot capture.** Every binding must get its context via upvalue
   (or `lua_getextraspace`). Settled here via light-userdata upvalue — carry that pattern
   forward.
2. **The macro shim is mandatory**, not optional. Lua's most-used API entries are macros
   invisible to Swift. Budget the (small) `cl_*` shim header up front.
3. **The instruction hook is a *guard*, not a scheduler.** It bounds a single `pcall`; it
   does not preempt cooperatively. A script doing slow-but-finite work each tick is the
   user's problem. A true hang needs the hook **plus** the background queue (have both).
4. **Symbol-animation constraint meets the binding layer.** Spike A's
   [D6](../../docs/knowledge-base/decisions.md) hard rule — *one in-flight symbol animation
   per `NSImageView`* — means `item:set` that changes an icon must **serialize/coalesce
   symbol mutations per item** on the main side. The command model makes this natural
   (collapse rapid `.set`s per id before applying), but it must be built deliberately.
5. **Lua's `os`/`io`/`package` are open here.** A real product must decide the **sandbox
   policy** for user configs (drop `os.execute`/`io`? gate `require`?). Out of scope for
   this spike but a security decision the runtime owner must make.
6. **Coroutines/yield across the C boundary** weren't exercised. If providers ever want
   async Lua, validate `lua_pcallk`/yield semantics before promising it.
7. **Debug vs. release.** Numbers above are debug. Release will be faster; not worth
   chasing — overhead is already negligible.

---

## 8. The runnable spike

```
tasks/spike-b/code/
├── Package.swift                 SwiftPM: CLua (C) + SpikeB (executable), macOS 13+
├── config.lua                    sample: clock, blinking center item, simulated event
├── Sources/
│   ├── CLua/                     vendored Lua 5.4.7 (MIT) + shims + modulemap
│   │   ├── src/*.c               upstream sources (no lua.c/luac.c)
│   │   ├── include/              headers + clua.h umbrella + lua_shims.h + modulemap
│   │   ├── VENDORING.md          version, sha256, what/why
│   │   └── LUA-LICENSE.txt       MIT
│   └── SpikeB/
│       ├── main.swift            app bootstrap; live mode + --selftest battery
│       ├── LuaVM.swift           state lifecycle, queue, bindings, pcall, hook, reload
│       ├── BarModel.swift        BarCommand / BarPosition / BarItem
│       ├── BarWindow.swift       plain NSWindow renderer (public AppKit only)
│       ├── HotReload.swift       kqueue config watcher (handles atomic saves)
│       └── Metrics.swift         tick timing + RSS sampling
```

Run it:

```sh
cd tasks/spike-b/code
swift run SpikeB              # live bar; edit config.lua to hot-reload
swift run SpikeB --selftest   # measurement + reload + crash-isolation battery, then exit
```

> Throwaway de-risking code — **not** the product. No SkyLight/private APIs (decoupled
> from Spike A): the bar renders in an ordinary `NSWindow`.
