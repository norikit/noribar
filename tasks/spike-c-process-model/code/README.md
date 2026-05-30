# Spike C — IPC PoC

Throwaway proof-of-concept (not product code) validating the IPC + threading decisions
in [`../FINDINGS.md`](../FINDINGS.md).

## Run

```sh
swift ipc-poc.swift
```

Exits `0` with all checks `PASS`, non-zero on any failure (it self-asserts).

## What it proves

- **Unix domain socket** control channel with **length-prefixed** (4-byte BE length +
  UTF-8) request/reply framing — sketchybar's model.
- The socket **accept/read loop runs on a background queue** (never blocks the UI thread).
- Every command's *application* is **marshalled onto the main queue**, modelling the rule
  that the Lua state and CALayer view tree are **main-thread-confined**. The core
  `precondition`s `Thread.isMainThread` on every state mutation.
- A **timer event** and **CLI commands** funnel into the **same main-thread dispatcher** —
  the unifying event model (timers + system events + CLI triggers → one dispatch point →
  coalesced redraw).

This is headless (no AppKit/SkyLight) so it runs anywhere Swift + Foundation are present,
including CI. The real product replaces `BarCore` with the Lua state + CALayer item tree.
