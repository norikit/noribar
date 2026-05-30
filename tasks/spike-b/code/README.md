# Spike B — embedded Lua runtime driving a live bar

Throwaway de-risking spike. **Not the product.** Brief:
[`tasks/spike-b/task.md`](../task.md).
Result: **GO** — read [`FINDINGS.md`](../FINDINGS.md) first.

## Run

```sh
swift run SpikeB              # live bar in a plain NSWindow; edit config.lua to hot-reload
swift run SpikeB --selftest   # headless measurement + 100-reload + crash-isolation battery
```

Override the config path with `SPIKE_B_CONFIG=/path/to/config.lua`.

## What it proves

Vanilla **Lua 5.4.7** (vendored, MIT) embedded as a SwiftPM C target, running on a
dedicated serial queue, drives a bar-state model. Lua callbacks emit commands that are
marshalled to the main thread and applied to an AppKit view tree. Timers and a simulated
`front_app_switched` event call back into Lua; a buggy script is caught (`pcall` +
instruction hook) instead of crashing the host; editing `config.lua` hot-reloads the VM.

Deliberately uses **public AppKit only** (no SkyLight/private window APIs) so it stays
decoupled from Spike A.
