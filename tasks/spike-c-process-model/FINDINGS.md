# Spike C — findings: process & update model

**Status: resolved.** This spike closes the last big Phase-0 architectural unknown. Below
is the decision and rationale for each key question, plus the validating PoC.

The four resolutions are also folded into the knowledge base as decisions **D5–D8**
([decisions.md](../../docs/knowledge-base/decisions.md)) and into
[architecture.md](../../docs/knowledge-base/architecture.md). Open questions Q1–Q4 are
closed.

---

## Q1 — Process model → **single faceless process, run as a per-user LaunchAgent**

**Decision.** noribar is **one long-lived process**: a faceless menu-bar app
(`LSUIElement`/agent — no Dock icon, no menu) that owns the SkyLight window, the Lua state,
and the CALayer item tree. It is **not** split into a background daemon + a thin UI client.
The only "client" is the short-lived `noribar` **CLI**, which connects over IPC, sends one
command, and exits.

For login persistence and crash recovery it is registered as a **per-user LaunchAgent**
(`~/Library/LaunchAgents`, `KeepAlive`), launched in the user's GUI (Aqua) session.

**Rationale.**

- **The window server forces it.** A SkyLight/CGS window can only be created by a process
  that holds a window-server connection, which only exists inside a logged-in GUI session.
  A launchd **system daemon** (no GUI session) cannot own the bar window at all — so a
  "daemon + client" split is not even available for the rendering half. The renderer must
  be a GUI-session agent regardless.
- **No benefit to splitting.** State and rendering are tightly coupled: events mutate item
  state which must immediately drive low-latency CALayer changes on the main thread.
  Splitting them across processes would add IPC latency and serialization on the hot path
  for zero gain. sketchybar (single process) is the proof.
- **"Survive across Spaces / fullscreen"** is a *window* property (SkyLight flags, proven
  in Spike A), not a *process* property — it does not motivate a daemon.
- **"Survive logout"** is a non-goal: the bar is intrinsically tied to the GUI login
  session. It should stop at logout and be **relaunched at next login** by launchd. That is
  exactly a LaunchAgent, not a system daemon.

**Consequence.** Two executables ship: the **bar** (the agent) and the **`noribar` CLI**
(a few KB; opens the socket, writes a framed message, prints the reply). The CLI is
stateless and holds no UI.

---

## Q2 — Update / event model → **one event dispatcher fed by timers + system events + triggers; coalesced redraw**

**Decision.** A single **event-dispatch point on the main thread** is fed by three
sources, all normalized into named **events**:

1. **Timers** — per-item `update_freq` (clock, CPU, battery…). Implemented as GCD timer
   sources; a coalescing timer wheel can later collapse many same-period items.
2. **System event subscriptions** — `NSWorkspace` notifications (`didActivateApplication`
   → `front_app_switched`, `activeSpaceDidChange` → `space_change`), display reconfigure
   callbacks, distributed notifications — each bridged to a noribar event name.
3. **Explicit triggers** — the Lua config and the external CLI can `trigger <event>`.
   Items **subscribe** to events by name; a trigger invokes their Lua callbacks.

All three funnel into the same dispatcher: *event → matching item callbacks (Lua) → item
state mutation → mark dirty*. A **coalesced redraw** then runs once on the next main-loop
pass inside a single `CATransaction`, so a burst of events produces one repaint, not many.

**Rationale.** This is sketchybar's proven hybrid (timers + events + triggers) but unified
under one dispatch/redraw path, which keeps the threading rules simple (everything that
touches Lua or layers happens at one place, on one thread) and makes redraw coalescing
trivial. The PoC exercises the timer-source-and-CLI-into-one-dispatcher shape directly.

---

## Q3 — IPC → **Unix domain socket, length-prefixed request/reply**

**Decision.** The bar listens on a **Unix domain socket** (`SOCK_STREAM`, `AF_UNIX`).
Messages are **length-prefixed**: a 4-byte big-endian length followed by a UTF-8 payload;
the bar replies on the same connection (enabling `query`-style commands). The socket path
is advertised via an env var (**`$NORIBAR`**, mirroring sketchybar's `$SKETCHYBAR`) with a
well-known per-user default under `$TMPDIR`; it is `chmod 0600` to the owning user.

CLI surface mirrors sketchybar: `noribar -m <domain> <command> [args…]` (e.g.
`noribar -m --add item clock right`, `noribar -m --trigger front_app_switched`).

**Rationale.**

- **Simplicity + speed + security with no entitlements.** A `0600` socket in the user's
  tmp dir is reachable only by that user — no sandbox entitlement or bootstrap registration
  needed. The CLI just `connect()`s to a path.
- **Rejected alternatives.** *Mach ports* need bootstrap-name registration/lookup and are
  fiddly for a tiny CLI; *distributed notifications* are broadcast, insecure, and can't
  carry a clean reply. The socket is the lowest-ceremony fit and is the proven sketchybar
  mechanism.
- **Framing** avoids stream-boundary bugs and cleanly supports request/reply.

**Validated** by [`code/ipc-poc.swift`](code/ipc-poc.swift): framed `set`/`query`/error
round-trips over a real `AF_UNIX` socket, all green.

---

## Q4 — Threading & main-thread safety → **Lua + view tree main-confined; only socket I/O off-main**

**Decision.**

- **Main thread owns**: the run loop, all AppKit/CALayer mutation, **and the Lua state**
  (Lua is single-threaded; confining it to main avoids any locking and matches where the
  view tree lives). The event dispatcher and redraw run here.
- **Background queues own**: raw socket I/O only — the `accept()` loop and per-connection
  byte read/parse run on a dedicated GCD queue so a slow/hostile client never stalls the
  UI. Any future shell-outs for item scripts also run off-main.
- **The seam**: a parsed command is handed to the core via `DispatchQueue.main` (sync when
  a reply is needed, async otherwise). System notifications already arrive on main.
- **Invariant**: *the Lua state and the CALayer item tree are main-thread-confined.* Only
  socket bytes and their parsing touch a background thread.

**Rationale.** Confining all interpreter and UI mutation to one thread eliminates a whole
class of data races and lock contention for free, while moving only blocking I/O off-main
keeps the UI responsive. The PoC enforces this with a `precondition(Thread.isMainThread)`
on every state mutation and passes — proving commands arriving on a background socket queue
are correctly marshalled to main before touching state.

---

## PoC

[`code/ipc-poc.swift`](code/ipc-poc.swift) (run: `swift ipc-poc.swift`) is a headless,
self-asserting demo of Q3 + Q4 (and the Q2 funnel): a background socket accept loop,
length-prefixed request/reply, a timer event and CLI commands converging on one
main-thread dispatcher, and a main-thread `precondition` on every mutation. Exits `0` with
all checks `PASS`. It is **throwaway** validation, not product code; the real bar replaces
the PoC's `BarCore` with the Lua state + CALayer item tree.

## What this unblocks

With rendering (Spike A), config (Spike B), and now the process/update/IPC model (Spike C)
resolved, **Phase 0 is complete** and milestone-1 implementation under `Sources/` can begin.
