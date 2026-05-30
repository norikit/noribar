# Spike A — Findings

## 1. Verdict (go / no-go)

**GO.** A single on-screen window can host a live AppKit/CALayer view tree running
**native** SF Symbol effects *and* carry SkyLight ricing powers (above the menu bar,
non-activating, all-Spaces-capable) at the same time. All six targeted symbol effects —
including the macOS 26 / SF Symbols 7 **draw-on / draw-off** — ran inside a borderless
non-activating `NSPanel` that was retagged through the private SLS API, at **0.0 % idle
CPU**, without stealing keyboard focus.

> Tested on **macOS 26.3 (build 25D125), Apple Swift 6.3.2, SDK 26.5**, 16″ MacBook Pro
> (Liquid Retina XDR, ProMotion 120 Hz, Apple Silicon).

---

## 2. Recommended approach: **A2** (public `NSPanel` + private SLS retag)

AppKit owns the view tree (so `NSImageView.addSymbolEffect(…)` works natively); SLS only
adjusts window placement/behavior on the panel's real `CGWindowID`. This is exactly the
"expected winner" from the brief, and it proved both **stable** and **free** (no extra
CPU vs A1).

Nuance worth recording: **A1 (pure public AppKit) already gets surprisingly far.** A
borderless `.nonactivatingPanel` with `NSApp.setActivationPolicy(.accessory)` +
`LSUIElement` satisfies criteria 1, 2 and 4 outright and *configures* 3 and 5 via
`collectionBehavior`. A2's private calls are therefore **hardening**, not enabling:

| SLS call (on the panel's `CGWindowID`) | Why A2 adds it |
|---|---|
| `SLSSetWindowTags(kCGSPreventsActivationTagBit /* 1<<16 */)` | belt-and-braces non-activation even if AppKit changes behavior |
| `SLSSetWindowTags(kCGSExposeFadeTagBit /* 1<<1 */)` | menu-bar-like fade in Mission Control / Exposé |
| `SLSSetWindowLevel(cid, wid, CGShieldingWindowLevel())` | reliably float above *other apps'* native-fullscreen spaces, where `.fullScreenAuxiliary` alone is documented to be flaky |
| `SLSSpace{Create,SetAbsoluteLevel,AddWindowsAndRemoveFromSpaces}` + `SLSShowSpaces` | optional "maximal stickiness" route (gated behind `--space`; perturbs Mission Control, off by default) |

**Implementation note — reaching SLS:** `SkyLight.framework` ships **only inside the
dyld shared cache** (its on-disk `Versions/A/` has no Mach-O), so `-framework SkyLight`
is fragile. AppKit already loads SkyLight into every GUI process, so we bind every
private symbol at runtime with `dlsym(RTLD_DEFAULT, "SLS…")` (see
[`SLS.swift`](Sources/SpikeA/SLS.swift)). **No bridging header, no linker flags, no C
target.** Signatures were confirmed against yabai `src/misc/extern.h` and SketchyBar
`src/window.{c,h}` per the brief (the brief's `const int tags[2]` was wrong — the real
signature is `uint64_t *tags, int tag_size`; space IDs are `uint64_t`).

---

## 3. Criteria matrix (5 criteria × approach)

| # | Criterion | A1 (public only) | A2 (A1 + SLS) | Evidence |
|---|---|---|---|---|
| 1 | Live AppKit/CALayer tree running **native** SF Symbol effects | ✅ pass | ✅ pass | all 6 effects logged "ran"; rendered ([screenshots](artifacts/)) |
| 2 | Pinned across top / in menu-bar region | ✅ pass | ✅ pass | `level = .mainMenu+1 = 25`; [`fullscreen.png`](artifacts/fullscreen.png) shows it over the menu bar |
| 3 | Appears on **all Spaces** | ⚙️ configured | ⚙️ configured (+ sticky tag) | `collectionBehavior` has `.canJoinAllSpaces` (raw `337`). **Visual confirmation across a Space switch needs a human** — could not be automated. |
| 4 | Never steals keyboard focus / activation (no Dock, no Cmd-Tab) | ✅ pass | ✅ pass | frontmost app stayed **Claude** before/during/at-quit; panel never key/main; `NSApp.isActive=false`; `.accessory` + `LSUIElement` |
| 5 | Floats above fullscreen apps | ⚙️ configured | ⚙️ configured (+ SLS level) | `.fullScreenAuxiliary` + `CGShieldingWindowLevel()`. **Visual confirmation over a fullscreen app needs a human.** |

✅ = empirically verified by the spike · ⚙️ = configured via the documented mechanism,
final visual confirmation pending a 2-minute human check (see §7).

The window was confirmed registered with the WindowServer
(`SLSCopySpacesForWindows` → 1 = current space once settled; it returns 0 if queried in
the same run-loop turn as `orderFront` — don't query synchronously at creation).

---

## 4. Symbol-effect support table

All exercised via `NSImageView` on `NSImage(systemSymbolName:…)`. Each effect ran on its
**own** image view (see the crash in §7).

| Effect / feature | Works? | Min OS | Notes |
|---|---|---|---|
| `.bounce` | ✅ ran | macOS 14 | |
| `.pulse` | ✅ ran | macOS 14 | |
| `.variableColor.iterative.dimInactiveLayers.nonReversing` | ✅ ran | macOS 14 | full modifier chain compiled & ran |
| magic `.replace` (`setSymbolImage(_:contentTransition:.replace)`) | ✅ ran | macOS 14 (magic-replace improved 15) | bell ↔ bell.slash |
| **`.drawOn`** | ✅ ran | **macOS 26 / SF Symbols 7** | compiled on SDK 26.5, ran on 26.3 |
| **`.drawOff`** | ✅ ran | **macOS 26 / SF Symbols 7** | the showcase effects — confirmed reachable |
| `variableValue` (`NSImage(systemSymbolName:variableValue:…)`) | ✅ | macOS 13 | static partial-fill rendering |
| rendering modes: monochrome / hierarchical / palette / multicolor | ✅ | macOS 12–13 | all four rendered, visible in screenshots |

On the macOS-13 floor the symbols render **static** (no effects) — degrades gracefully,
as the decisions require. Gate every effect behind `if #available(macOS 14/26, *)`.

---

## 5. Measurements

| Metric | Value | Notes |
|---|---|---|
| Idle CPU (nothing animating) | **0.0 %** | 8 × 1 s samples, flat 0.0 — meets the ~0 % target |
| CPU during continuous animation | **~3–5 %** | 6 effects re-fired **every 1.25 s** — an artificially dense load; a real bar animates far less |
| Memory (RSS) | ~48 MB idle / ~52 MB animating | bare SwiftPM debug build |
| Input→visual latency | not instrumented to ms; **perceptually immediate** | click handled synchronously on `mouseDown`; effect begins on the next display-link tick (≤1 frame, ≈8 ms @120 Hz) |
| ProMotion / 120 Hz | display present (Liquid Retina XDR); animations are **NSScreen display-link driven** (confirmed in the backtrace) → adaptive & display-synced; observed smooth |

---

## 6. Screenshots

| File | Shows |
|---|---|
| [`artifacts/bar-window.png`](artifacts/bar-window.png) | A2 bar window: hierarchical-teal `wifi`, monochrome `speaker`, multicolor `battery`, red-palette `bell` (5th symbol mid-`drawOff`, i.e. hidden) |
| [`artifacts/bar-window-a1.png`](artifacts/bar-window-a1.png) | A1 bar with all 5 symbols visible incl. `square.and.arrow.up` drawn-on and `bell.slash` (magic-replace toggled) |
| [`artifacts/fullscreen.png`](artifacts/fullscreen.png) | full screen — the bar pinned across the very top, rendering **over the system menu-bar region** |

(No screen recording captured — the agent harness can't drive a continuous capture; the
animation cadence is visible across the stills and effect-log instead.)

---

## 7. Risks & surprises for the real implementation

1. **🔴 RenderBox crashes if you stack animations on one view.** Applying a
   content-transition (`setSymbolImage(_:contentTransition:.replace)`) **and** a discrete
   effect (`.drawOn`) to the **same** `NSImageView` in the **same run-loop turn**
   reliably `EXC_BAD_ACCESS`es on `com.apple.renderbox.animation-thread`
   (`RB::Symbol::Animation::apply`). Fixed here by **one in-flight effect per view**.
   **Product constraint:** the item/update model must serialize symbol mutations per item
   — never replace a symbol's image while another transition is in flight on it. Treat
   each bar item's symbol as a single-animator unit.
2. **Private SLS access:** use `dlsym(RTLD_DEFAULT, …)`, not `-framework SkyLight` (no
   on-disk binary). Confirmed the symbols are reachable in-process. Consequence: an app
   using private SLS **cannot be sandboxed / shipped via the App Store** (same as
   sketchybar/yabai) and must be **Developer-ID signed with hardened runtime** for
   distribution; our spike used ad-hoc signing + `LSUIElement`.
3. **Per-OS SLS forks (not exercised here, but required for the macOS-13 floor):**
   SketchyBar uses `SLSTransactionSetWindowLevel` / `SLSTransactionOrderWindow` on
   Sonoma+ vs `SLSSetWindowLevel` / `SLSOrderWindow` on Ventura. We used the
   non-transaction calls and they worked on 26.3; the product should fork per the
   sketchybar/yabai precedent and **test on a real Ventura machine**.
4. **WindowServer registration is async:** `SLSCopySpacesForWindows` returns 0 if queried
   in the same run-loop turn as `orderFront`; query after the window settles.
5. **Bundle identity matters:** running as a bare binary logs
   `[WindowTab] … missing main bundle identifier`. Not the crash cause, but the product
   is a real `.app` bundle anyway (see [`bundle.sh`](bundle.sh)).
6. **Permissions:** creating/showing the bar triggered **no** TCC prompt. (Screen capture
   for these findings used the host terminal's existing Screen Recording grant; the bar
   itself needs no special permission to render or to retag via SLS.)
7. **Not autonomously verifiable — needs a 2-minute human check:** criteria **3
   (all-Spaces)** and **5 (over-fullscreen)** require Mission Control interaction the
   agent can't perform. Run `./run-demo.sh`, then Ctrl-←/→ to switch Spaces and put any
   app fullscreen, and confirm the bar persists/floats. Everything points to pass
   (correct `collectionBehavior`, high level, SLS tags), but it is unconfirmed visually.

---

## 8. A3 feasibility note (pure SLS window — timeboxed, not built)

Per the brief, A3 was **not built**. Reasoned verdict from the A2 crash backtrace: native
symbol effects are dispatched through AppKit's hosting pipeline —
`-[NSScreen _displayLinkWithOptions:…]` → `RBAnimationThread` → `RBSymbolLayer
updateForTime:` → `RB::Symbol::Animation::apply`. A raw
`SLSNewWindowWithOpaqueShapeAndContext` window has **no `NSView`, responder chain, or
NSScreen display-link host**, so `addSymbolEffect` / `setSymbolImage(contentTransition:)`
have nothing to attach to. Reaching symbol *effects* there would mean rebuilding CALayer
trees and driving `CAAnimation`s by hand — i.e. reimplementing RenderBox, which defeats
the entire reason AppKit was chosen. **Conclusion: A3 can do static symbol rendering but
cannot reach native symbol effects without the AppKit layer. A2 is the correct
architecture.**

---

## Reproduce

```sh
cd spikes/spike-a
./bundle.sh                                   # builds + wraps in SpikeA.app
SpikeA.app/Contents/MacOS/SpikeA --approach a2 --anim   # the bar; Ctrl-C to quit
# flags: --approach a1|a2 · --anim|--idle · --seconds N · --only bounce|pulse|varcolor|replace|draw · --space
```

Throwaway de-risking code — **not the product**. See [`README.md`](README.md).
