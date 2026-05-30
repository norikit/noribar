# Architectural decisions

Locked decisions are **constraints**. Do not relitigate without explicit owner direction.
When a new decision is made, add an entry here (newest at the bottom of its section) and,
if it resolves an [open question](open-questions.md), remove that entry there.

Format: each decision has a status, the decision, and the rationale.

> The cross-cutting rationale for D1/D2/D4 — how we compare to sketchybar on performance
> and what the Swift/AppKit/Lua stack buys us beyond it — is gathered in
> [why-swift.md](why-swift.md).

---

## D1 — Language & platform: Swift / macOS

- **Status:** Locked (2026-05-30)
- **Decision:** Native Swift application targeting macOS.
- **Rationale:** First-class access to AppKit, CoreAnimation, and the SF Symbols /
  `SymbolEffect` APIs that are central to the product. Swift is the modern, contributor-
  approachable choice for a new macOS app.

## D2 — Rendering backend: AppKit + CALayer

- **Status:** Locked (2026-05-30)
- **Decision:** The bar is an `NSView` / `NSImageView` tree on a layer-backed host,
  using AppKit + CoreAnimation. **Not** raw CoreGraphics drawing (sketchybar's approach).
- **Rationale:** This is the whole reason the project exists. sketchybar draws static
  font glyphs and therefore **cannot** use Apple's symbol-effect engine. An AppKit view
  tree gets `NSImageView.addSymbolEffect(...)`, magic `.replace`, draw-on/off, and
  variable color **for free**. See [sketchybar-reference.md](sketchybar-reference.md).
- **Consequence / risk:** AppKit views must be hosted inside a private-SkyLight window
  (see D3). That bridge is novel — it was de-risked by
  [Spike A](../spikes/spike-a-render-window.md) and **confirmed viable** (see D6).

## D3 — Window strategy: private SkyLight (SLS/CGS) APIs

- **Status:** Locked (2026-05-30)
- **Decision:** Create/manage the bar window with private SkyLight APIs, sketchybar/
  yabai-style: all-Spaces, over-fullscreen, non-activating, able to replace the real
  menu bar, blur support.
- **Rationale:** These behaviors are non-negotiable for power users and are impossible
  with public AppKit alone.
- **Consequences:** No App Sandbox, no Mac App Store, per-macOS-version code forks
  (Monterey/Ventura/Sonoma/Tahoe), fragility across OS updates, permission prompts.
  **Mitigation:** isolate all SLS calls behind a window-backend boundary so a public
  fallback could be added and OS forks are contained.
- **Spike A refinement (see D6):** the SLS surface is *additive hardening* on top of a
  public `NSPanel`, not the thing that hosts the views. The private symbols are reached
  via `dlsym(RTLD_DEFAULT, …)` — `SkyLight.framework` has no on-disk binary (dyld-cache
  only), so `-framework SkyLight` is fragile.

## D4 — Configuration: embedded Lua

- **Status:** Locked (2026-05-30)
- **Decision:** Users configure and drive the bar with an embedded Lua runtime
  (Hammerspoon / AwesomeWM style), not sketchybar's imperative shell-CLI + per-event
  script spawning.
- **Rationale:** More powerful, more shareable, and far less per-tick overhead than
  spawning a process per event. Strong fit for the ricing community.
- **Consequence / risk:** Must embed and bridge a Lua runtime and define a safe
  Lua↔main-thread threading model. Being de-risked by
  [Spike B](../spikes/spike-b-lua-runtime.md).

## D5 — Minimum macOS 13, graceful degradation

- **Status:** Locked (2026-05-30)
- **Decision:** Deployment target macOS 13 (Ventura). Newer capabilities degrade
  gracefully on older systems rather than blocking them.
- **Rationale:** Reach vs. features. But note: the `SymbolEffect` API is **macOS 14+**,
  and draw-on/off (SF Symbols 7) is **macOS 26+**. On macOS 13 symbols render static.
- **Consequence:** All symbol-effect code paths must be gated behind `if #available`
  with sensible static fallbacks.

## D6 — Window/render bridge: public `NSPanel` + additive SLS retag (Spike A outcome)

- **Status:** Locked (2026-05-30) — resolves former open question Q1, via
  [Spike A](../spikes/spike-a-render-window.md) ([findings](../../spikes/spike-a/FINDINGS.md)).
- **Decision:** The bar surface is a borderless **non-activating `NSPanel`**
  (`.accessory` activation policy / `LSUIElement`) that **owns the AppKit/CALayer view
  tree** — so native SF Symbol effects (incl. macOS 26 draw-on/off) work. SkyLight is
  applied **additively** to the panel's real `CGWindowID` for hardening only:
  `kCGSPreventsActivationTagBit`, `kCGSExposeFadeTagBit`, and `SLSSetWindowLevel`
  (`CGShieldingWindowLevel()`) for above-fullscreen. Private symbols are bound at runtime
  with `dlsym(RTLD_DEFAULT, …)` behind the `WindowBackend` boundary. The pure-SLS
  viewless window (Spike A "A3") is **rejected**: native symbol effects are bound to
  AppKit's `NSView` + `NSScreen` display-link → RenderBox pipeline and are unreachable
  without an AppKit host.
- **Verified:** native effects ran inside the SLS-retagged panel at **0.0 % idle CPU**,
  without stealing focus / Dock / Cmd-Tab. (All-Spaces & over-fullscreen are configured
  via the documented mechanism; final on-screen confirmation is a pending manual check.)
- **🔴 Hard constraint for the item model:** **one in-flight symbol animation per
  `NSImageView`.** Stacking a content-transition (`.replace`) and a discrete effect
  (`.drawOn`) on the *same* view in the *same* run-loop turn crashes Apple's RenderBox
  animation thread (`EXC_BAD_ACCESS` in `RB::Symbol::Animation::apply`). The bar-state
  model must serialize symbol mutations per item.

---

## License

- **Status:** Locked (inherited) — **AGPL-3.0** (`LICENSE` at repo root).
