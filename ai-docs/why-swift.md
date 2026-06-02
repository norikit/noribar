# Why Swift / what we gain over sketchybar

The case for noribar's stack (Swift + AppKit/CALayer + embedded Lua) versus sketchybar's
(C + raw CoreGraphics + shell/CLI). This is the **rationale dossier** behind
[D1](decisions.md), [D2](decisions.md), and [D4](decisions.md) — gathered in one place so
the reasoning isn't scattered across three ADRs. For how sketchybar itself is built, see
[sketchybar-reference.md](sketchybar-reference.md).

> **Honesty note.** The two wins that were once *contingent* on de-risking spikes are now
> both **proven**: the AppKit-inside-private-SkyLight bridge by
> [Spike A](../../tasks/spike-a/task.md) ([findings](../../tasks/spike-a/FINDINGS.md), locked
> as [D6](decisions.md)) — native symbol effects at ~0% idle CPU in an SLS-retagged panel;
> and the embedded-Lua stack by [Spike B](../../tasks/spike-b/task.md)
> ([findings](../../tasks/spike-b/FINDINGS.md), locked as [D7](decisions.md)) — ~1.7 µs
> per-tick overhead, crash-isolated, hot-reloadable. The one win below still *unmeasured at
> product scale* is **memory footprint** (§1): the spikes' early numbers are encouraging
> (~48 MB AppKit panel, <1 MB for Lua) but a fully-featured bar isn't built yet. Treat that
> row as a projection; the rest are now measured.

---

## 1. Performance: how we compare

The headline: **idle and steady-state should be a wash or better; per-frame draw cost
will be higher; the big win is event/reactivity overhead; the big unknown is memory.**

| Dimension | vs. sketchybar | Why |
|---|---|---|
| Idle CPU | **Tie** (~0%) | Both tear down the display link when nothing animates ([sketchybar-reference.md](sketchybar-reference.md), [architecture.md](architecture.md) render layer). The single most important perf lesson to copy — see [Q4](open-questions.md). [Spike A](../../tasks/spike-a/task.md) **measured 0.0% idle** with native effects live in the panel ([D6](decisions.md)). |
| Event / reactivity cost | **noribar wins** | sketchybar **spawns an external shell script per event** to recompute item content — its performance floor. noribar uses in-process native providers + Lua callbacks ([D4](decisions.md), [architecture.md](architecture.md)): no `fork`/`exec`, no shell startup per tick. |
| Command / config latency | **noribar wins** | sketchybar marshals commands over Mach IPC from a separate CLI process. noribar runs config logic in an in-process `lua_State` — no IPC serialization hop. |
| Per-frame draw | **sketchybar lighter** | sketchybar blits static font glyphs straight into a `CGContext` — about as cheap as on-screen drawing gets. noribar's CALayer tree carries more per-frame overhead, but mitigated by per-item dirty-layer redraw and GPU/window-server compositing, and it can render effects sketchybar cannot at any price. |
| Memory footprint | **sketchybar lighter** | A ~95% C daemon has a tiny RSS. noribar pulls in the Swift runtime + AppKit/CoreAnimation + an embedded Lua interpreter. Expect tens of MB vs. single-digit (Spike A's bare AppKit panel measured ~48 MB; embedded Lua added <1 MB in Spike B — but a fully-featured bar is unmeasured). The main standing cost of our stack; worth watching for a forever-running process, but acceptable on any macOS 13+ machine. |
| Startup | **sketchybar lighter** | Swift runtime + AppKit + Lua init is heavier than a C daemon's cold start. One-time, irrelevant for a long-lived process. |
| Window compositing | **Tie** | Both own the window via the **same** private SkyLight APIs ([D3](decisions.md)). |

**Bottom line:** noribar won't be faster across the board — sketchybar is a near-optimal
C minimalist daemon and stays leaner in raw memory and per-glyph draw. The bet is that the
two costs that actually bite users in daily use — **idle CPU and per-event overhead** —
are tie-or-better, while we unlock native animated SF Symbols sketchybar architecturally
cannot do. The price is a fatter memory footprint.

---

## 2. Beyond performance: what the stack buys us

Separating language wins from framework wins, because the benefit differs.

### From Swift the language

- **Memory & crash safety.** sketchybar is ~95% hand-written C talking to raw `CGContext`
  buffers and manually managed CGS handles — every pointer into a private SLS struct is a
  potential segfault. Swift gives bounds-checked collections, ARC, optionals, no manual
  `malloc`/`free` for the bulk of the code. For a process that runs **forever**,
  "doesn't leak and doesn't crash" is a feature.
- **Error isolation.** Every Lua entry is wrapped in `pcall` ([architecture.md](architecture.md))
  so a broken user config can't take down the host; typed Swift error handling lets the
  rest degrade (show a broken item, log, keep running) where C would crash. In sketchybar
  a daemon-side C bug is fatal.
- **Type-safe concurrency.** The threading model — main thread owns all AppKit mutation, a
  dedicated serial queue owns the single `lua_State`, providers hop events between them
  ([architecture.md](architecture.md)) — is treacherous to enforce by hand in C but
  policeable at compile time with actors / `@MainActor` / `Sendable`.

### From the stack Swift unlocks (the bigger wins)

- **Native animated SF Symbols — the whole reason the project exists.**
  `NSImageView.addSymbolEffect(...)`, magic `.replace`, draw-on/off, variable color come
  **for free** from the AppKit view tree ([D2](decisions.md)). sketchybar draws static
  font glyphs and *cannot* access the symbol-effect engine at any cost. Not "better" — a
  category it can't enter.
- **First-class system frameworks for providers — no shelling out.** sketchybar's
  reactivity is *spawn a shell script per event*, so users glue together `pmset`,
  `ifconfig`, `osascript`, `yabai` queries. noribar's providers ([architecture.md](architecture.md))
  call the real frameworks directly and type-safely: `IOKit`/`NSProcessInfo` (battery),
  `Network.framework`/`SCNetworkReachability` (net), `CoreAudio` (volume),
  `NSWorkspace` (front app, Space changes). Richer data, lower latency, no CLI-text
  parsing, works without a zoo of shell tools. See provider design in [Q3](open-questions.md).
- **AppKit/CoreAnimation does the hard pixel work.** Retina/`@2x` scaling, ProMotion
  display sync, text layout & font fallback, RTL, layer compositing, hit-testing,
  accessibility — handled by the framework. sketchybar hand-rolls much of this in
  CoreGraphics (note its explicit `SLSSetWindowResolution(2.0)` and manual glyph drawing).
  Code we don't write and can't get wrong.
- **Interactivity comes cheaper.** Popups, sliders, clickable/scrollable items, menus
  ([architecture.md](architecture.md), [Q5](open-questions.md)) are first-class AppKit
  controls with built-in event handling, rather than mouse-tracking and hit-rects drawn
  and dispatched by hand.

### For contributors & users

- **Approachability.** [D1](decisions.md) calls this out: the pool of people who can patch
  a Swift/AppKit menu-bar app is far larger than those comfortable in a C daemon doing raw
  CGS calls. For an open-source ricing project, contributor surface area matters.
- **A far better config story.** Embedded Lua ([D4](decisions.md)) gives real variables,
  functions, loops, shareable modules, and hot-reload, versus imperative shell + CLI —
  a direct fit for a community that swaps configs.

---

## 3. The counterweight (what Swift costs us)

So this doesn't read as cheerleading:

- **No App Sandbox, no Mac App Store** — though already true for sketchybar via SLS ([D3](decisions.md)).
- **Heavier memory & runtime footprint** — see the table in §1.
- **The (former) novel risk:** the AppKit-inside-private-SkyLight bridge — sketchybar's
  C+CoreGraphics path through SLS is well-trodden, ours was not — is now **proven** by
  [Spike A](../../tasks/spike-a/task.md) (locked as [D6](decisions.md)): a
  layer-backed AppKit tree runs native symbol effects inside an SLS-retagged panel
  cleanly. Caveat carried forward: one symbol animation per view (RenderBox crashes if
  effects stack on one view).
