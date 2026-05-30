# spike-a — AppKit SF Symbol effects inside a SkyLight window

**Throwaway de-risking spike. Not the product.** Answers one question: can a real
AppKit/CALayer view tree running native SF Symbol effects live in a window that also has
SkyLight ricing powers (all-Spaces, over-fullscreen, non-activating)?

➡️ **Result: yes.** Read **[FINDINGS.md](../FINDINGS.md)** (verdict first).

## Layout

| File | Purpose |
|---|---|
| [`Sources/SpikeA/main.swift`](Sources/SpikeA/main.swift) | entry point, CLI flags, on-launch diagnostics |
| [`Sources/SpikeA/BarPanel.swift`](Sources/SpikeA/BarPanel.swift) | **A1** public-API panel config + **A2** private-SLS retag |
| [`Sources/SpikeA/SymbolStrip.swift`](Sources/SpikeA/SymbolStrip.swift) | the bar: `NSImageView`s + every symbol effect/rendering mode |
| [`Sources/SpikeA/SLS.swift`](Sources/SpikeA/SLS.swift) | private SkyLight surface, bound via `dlsym(RTLD_DEFAULT)` |
| [`bundle.sh`](bundle.sh) | build + wrap into `SpikeA.app` (needs a bundle id — see findings §7.1) |
| [`run-demo.sh`](run-demo.sh) | build + launch for the manual Space/fullscreen check |
| `artifacts/` | screenshots |

## Run

```sh
./bundle.sh
SpikeA.app/Contents/MacOS/SpikeA --approach a2 --anim
```

Flags: `--approach a1|a2` · `--anim|--idle` · `--seconds N` (auto-quit) ·
`--only bounce|pulse|varcolor|replace|draw` (effect bisection) ·
`--space` (dedicated-space stickiness route).

Requires Xcode/Swift toolchain, macOS 13+ (effects need 14+; draw-on/off need 26).
