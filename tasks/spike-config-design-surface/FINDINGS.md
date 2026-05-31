# Config design surface — findings

**Legend**
- Sketchybar: ✅ full support · ⚠️ partial / workaround only · ❌ not supported
- noribar: ✅ covered by current design · ⚠️ needs design work · ❌ fundamental gap · 🔧 escape hatch handles it

---

## 1. Layout & Positioning

| Capability | sketchybar | noribar | Notes / gaps |
|---|---|---|---|
| Fixed zones (left / center / right) | ✅ | ✅ | noribar adds left-notch / right-notch |
| Absolute position anywhere on screen | ⚠️ via `position=0` | ✅ unassigned element | x,y relative to screen top-left |
| Position offset relative to auto-slot | ❌ | ✅ | Lets user nudge an area element |
| Per-element flow direction | ❌ | ✅ | L→R, R→L per area; user can override |
| Sequential object flow (L→R, R→L, T→B, B→T) | ❌ | ✅ | Per-layer |
| Independent object position within layer | ❌ | ✅ | Absolute within layer bounds |
| Autosize element to content | ⚠️ width only | ✅ | Width + height |
| Fixed element size | ✅ | ✅ | |
| Clip overflow | ❌ | ✅ | Enables scrolling ticker |
| Wrap overflow | ❌ | ✅ | Multi-line/dynamic resize |
| Independent area height | ❌ | ✅ | Each zone has own height |
| Independent element height | ⚠️ | ✅ | |
| Constraint-based layout (align A to B) | ❌ | ⚠️ | Needs design — powerful but complex |
| Element spans multiple zones | ❌ | ❌ | Not in current design; edge case |
| Relative sizing (% of bar/screen width) | ❌ | ⚠️ | Useful for responsive layouts; needs design |
| Gap / spacing between elements | ✅ | ⚠️ | Need to decide: per-element padding or gap property on zone |
| Z-order between elements | ⚠️ manual ordering | ✅ | element.order drives compositing |
| Z-order between layers within element | ❌ | ✅ | layer.order |
| Padding / insets per object | ⚠️ | ⚠️ | Need explicit padding API on objects |
| Stacking overflow (what happens when zone is full) | ❌ | ⚠️ | Clip, scroll, or push into adjacent zone? Needs decision |

**Gaps to address:**
- Constraint layout (A.trailing = B.leading + 8) — even a limited form (anchor to another element) would let users build aligned composites without absolute coordinates.
- Percentage sizing — `width = "50%"` for center zone fills space dynamically.
- Explicit gap/padding API — needs first-class treatment, not just empty objects.

---

## 2. Visual Appearance

| Capability | sketchybar | noribar | Notes / gaps |
|---|---|---|---|
| Solid background color (RGBA) | ✅ | ✅ rectangle object |  |
| Gradient background (linear) | ❌ | ⚠️ | Needs design — CAGradientLayer is straightforward |
| Gradient background (radial / angular) | ❌ | ⚠️ | Needs design |
| Blur / vibrancy background | ✅ blur_radius | ✅ blur object | noribar: NSVisualEffectView |
| Border / stroke | ✅ | ⚠️ | Need border object or property on rectangle |
| Corner radius | ✅ | ⚠️ | Property on rectangle / layer |
| Drop shadow | ✅ | ⚠️ | CALayer shadow — straightforward |
| Inner shadow | ❌ | ⚠️ | Achievable with CALayer but needs design |
| Glow / outer glow | ❌ | ⚠️ | Can approximate with shadow + blur |
| Opacity (element / layer / object) | ✅ | ✅ | Part of animatable state |
| Blend modes (multiply, screen, overlay…) | ❌ | ⚠️ | CALayer compositingFilter — powerful, niche |
| Color filter / matrix | ❌ | 🔧 | Escape hatch: custom Lua transform function |
| Per-display accent color | ❌ | ⚠️ | NSColor.controlAccentColor — easy to expose |
| Dark/light mode aware colors | ❌ | ⚠️ | NSAppearance-aware color literals needed |
| Wallpaper-derived color | ❌ | ⚠️ | Interesting — sample dominant color; needs design |
| Image background (file, URL, SF Symbol) | ✅ | ✅ image object | |
| Clip to custom shape (not just rect) | ❌ | ⚠️ | CAShapeLayer mask — needs design |
| Scale transform | ❌ | ✅ | Part of animatable state |
| Rotation transform | ❌ | ✅ | Part of animatable state |
| Reflection / mirror | ❌ | ⚠️ | Exotic; 🔧 custom draw escape hatch |
| Custom Metal shader / draw function | ❌ | ⚠️ | **Key escape hatch gap** — see below |

**Key gap — custom rendering escape hatch:**
Advanced users (shaders, procedural drawing, game-style effects) will eventually hit the ceiling of pre-defined object types. Consider a `canvas` object type with a `draw(ctx, frame)` Lua callback that receives a CGContext. This is the ultimate escape hatch and means noribar never forces a fork for visual effects.

---

## 3. Animation & Motion

| Capability | sketchybar | noribar | Notes / gaps |
|---|---|---|---|
| Built-in easing curves (linear, ease-in/out, spring…) | ✅ limited set | ✅ | |
| Custom cubic-bezier easing | ❌ | ⚠️ | Expose as `easing = {0.25, 0.1, 0.25, 1.0}` table |
| Custom per-frame Lua animation function | ❌ | ✅ | `(old, new, frame) → state \| done` |
| Animation on element level | ❌ | ✅ | Move whole element |
| Animation on layer level | ❌ | ✅ | Fade/slide a layer |
| Animation on object level | ⚠️ position/color | ✅ | Full state |
| Animatable properties: position (x,y) | ✅ | ✅ | |
| Animatable properties: size (w,h) | ❌ | ✅ | |
| Animatable properties: opacity | ✅ | ✅ | |
| Animatable properties: scale | ❌ | ✅ | |
| Animatable properties: rotation | ❌ | ✅ | |
| Animatable properties: color / background | ✅ | ✅ | |
| Animatable properties: corner radius | ❌ | ✅ | |
| Animatable properties: blur radius | ❌ | ✅ | |
| Animatable properties: border width/color | ❌ | ✅ | |
| Animatable properties: font size | ❌ | ⚠️ | Needs decision — CALayer text doesn't animate font size natively |
| SF Symbol native effects (bounce, pulse, replace…) | ❌ | ✅ | noribar's headline; D6-safe via SymbolAnimator |
| SF Symbol variable value animation | ❌ | ✅ | |
| SF Symbol draw-on / draw-off (macOS 26+) | ❌ | ✅ | Gated behind #available |
| Animation chaining (A ends → B starts) | ❌ | ⚠️ | **Gap** — needs an `on_complete` callback |
| Animation sequencing (queue of animations) | ❌ | ⚠️ | Follows from chaining |
| Looping animation (infinite / n times) | ⚠️ manual | ⚠️ | Need `loop = true / n` option |
| Ping-pong loop (forward then reverse) | ❌ | ⚠️ | Follows from loop |
| Animation delay (start after N seconds) | ❌ | ⚠️ | `delay = 0.5` — easy to add |
| Stagger (multiple elements animate with offset) | ❌ | 🔧 | Lua can schedule bar.every with offsets |
| Synchronized animations across elements | ❌ | ⚠️ | Needs a shared animation clock or broadcast event |
| Physics-based animation (spring, gravity) | ❌ | 🔧 | Custom frame function with velocity state |
| Animation triggered by data value crossing threshold | ❌ | 🔧 | Lua can watch values and call animate() |
| Transition animation on element show/hide | ⚠️ | ⚠️ | Need first-class show/hide with transition spec |
| Transition on element enter/exit zone | ❌ | ⚠️ | Useful for dynamic element sets |
| Reverse / cancel running animation | ❌ | ⚠️ | Needs animation handle API |
| Pause / resume animation | ❌ | ⚠️ | Needs animation handle |
| Animation speed multiplier | ❌ | ⚠️ | Global or per-animation |
| Notch appear/disappear transition | N/A | ✅ | With escape hatch for custom fn |

**Key gaps:**
- **Animation chaining** — without `on_complete`, users must approximate with timers. A callback `animation:on_complete(fn)` or `animate({ ..., on_complete = fn })` is essential.
- **Animation handle** — `local anim = element:animate({...})` that you can `anim:cancel()`, `anim:pause()`, `anim:reverse()`. Enables interactive and reactive animations.
- **Synchronized clock** — `bar.sync(fn)` that calls `fn(t)` on every display-link tick so multiple elements can animate in lockstep.

---

## 4. Interaction & Input

| Capability | sketchybar | noribar | Notes / gaps |
|---|---|---|---|
| Left click handler | ✅ via script | ⚠️ | Needs design — Lua callback on element |
| Right click handler | ✅ via script | ⚠️ | |
| Middle click handler | ❌ | ⚠️ | |
| Double click | ❌ | ⚠️ | |
| Long press | ❌ | ⚠️ | |
| Scroll wheel (up/down/left/right) | ✅ | ⚠️ | Useful for volume, brightness sliders |
| Hover enter / exit | ❌ | ⚠️ | **Important gap** — drives tooltip, highlight, reveal |
| Hover dwell (hover for N ms) | ❌ | ⚠️ | Tooltip trigger |
| Drag (reorder elements) | ❌ | ⚠️ | Complex; defer |
| Keyboard shortcut binding | ❌ | ⚠️ | `bar.bind("cmd+shift+b", fn)` — needs design |
| Passthrough mouse events to app below | ✅ ignores_mouse | ⚠️ | Per-element control; need `mouse_passthrough` flag |
| Hit testing control (which layer receives events) | ❌ | ⚠️ | Needed when layers overlap |
| Tooltip on hover | ❌ | ⚠️ | Follows from hover; could be a built-in |
| Context menu (native NSMenu on right-click) | ❌ | ⚠️ | Powerful — lets element spawn a menu |
| Popup / overlay element | ❌ | ⚠️ | **Key gap** — see below |
| Click-through on transparent areas | ❌ | ⚠️ | Per-pixel hit testing vs bounding box |

**Key gap — popups / overlays:**
Users will want click → popup (dropdown, calendar, mini-window). This requires elements that can exist *above* the bar height. Two options: (a) a secondary floating window that the Lua config can show/hide, or (b) elements with `overflow = "visible"` that draw outside their area bounds. This is a significant architectural decision.

**Key gap — hover:**
Without hover, users can't build highlight-on-hover, reveal-on-hover, or tooltip effects. It's fundamental to an interactive bar. Needs an NSTrackingArea per element.

---

## 5. Typography & Text

| Capability | sketchybar | noribar | Notes / gaps |
|---|---|---|---|
| System font with weight/size | ✅ | ✅ text object | |
| Custom font (by name) | ✅ | ✅ | |
| Bundled font file (.ttf/.otf) | ❌ | ⚠️ | Users want custom icon fonts (Nerd Fonts) |
| Monospaced digits (clock alignment) | ❌ | ⚠️ | `.monospacedDigit()` modifier — easy |
| Text color | ✅ | ✅ | |
| Text shadow | ❌ | ⚠️ | |
| Text alignment (left/center/right) | ✅ | ⚠️ | Need per-text-object alignment |
| Letter spacing / kerning | ❌ | ⚠️ | NSAttributedString |
| Line height | ❌ | ⚠️ | |
| Truncation with ellipsis | ✅ | ⚠️ | Need explicit truncation mode |
| Scrolling / marquee text | ❌ | ✅ | Clip + animation on text object |
| Rich text / attributed strings | ❌ | ⚠️ | Per-run color, weight, size — complex but powerful |
| Gradient text | ❌ | ⚠️ | CALayer mask trick; niche but popular in ricing |
| Emoji rendering | ✅ | ✅ | NSAttributedString handles it |
| Icon fonts (Nerd Fonts glyphs as text) | ✅ | ✅ | Follows from custom font support |
| RTL text | ❌ | ⚠️ | NSAttributedString supports it; needs testing |
| Multiline text | ❌ | ✅ | Wrap mode on element |
| Per-character animation | ❌ | ⚠️ | Each char as separate object — user builds it |

**Key gap — Nerd Fonts / bundled fonts:**
The ricing community heavily uses Nerd Fonts. Support for loading a font file from the config directory is essential. `text({ font_file = "~/.config/noribar/fonts/NerdFont.ttf" })`.

---

## 6. Data & Providers

| Capability | sketchybar | noribar | Notes / gaps |
|---|---|---|---|
| Shell command (one-shot) | ✅ | 🔧 | `os.execute` in Lua (sandbox policy pending) |
| Shell command (polling) | ✅ native | 🔧 | `bar.every` + `os.execute` |
| Shell command (event-driven) | ✅ native | 🔧 | `bar.subscribe` + shell |
| Native CPU provider | ❌ | ⚠️ | Common need; avoids spawning `top` |
| Native memory provider | ❌ | ⚠️ | |
| Native disk I/O provider | ❌ | ⚠️ | |
| Native network (speed) provider | ❌ | ⚠️ | |
| Native battery provider | ❌ | ⚠️ | |
| Native front-app provider | ✅ event | ✅ FrontAppProvider | |
| Native Spaces / workspace provider | ✅ event | ⚠️ | Space index, layout |
| Native audio (volume, device) provider | ❌ | ⚠️ | CoreAudio |
| Native display/brightness provider | ❌ | ⚠️ | |
| Native clock / date | ✅ via script | ✅ os.date in Lua | |
| Native Focus / DND state | ❌ | ⚠️ | |
| HTTP polling (JSON endpoint) | ❌ | ⚠️ | **Gap** — needs URLSession bridge to Lua |
| WebSocket / streaming | ❌ | ⚠️ | Niche but powerful; real-time data |
| File watching | ❌ | ⚠️ | Watch a log file, data file |
| NSDistributedNotification | ⚠️ via script | ⚠️ | Spotify, other apps broadcast these |
| IOKit hardware events | ❌ | ⚠️ | Lid open/close, power events |
| Reactive / observable values | ❌ | ⚠️ | **Key design gap** — see below |
| Derived / computed values | ❌ | 🔧 | Lua variables + bar.every |
| Persistent state (survive reload) | ❌ | ⚠️ | Write to file; or first-class `bar.persist` |
| IPC (external process pushes data) | ✅ via CLI | ✅ planned | Unix socket + CLI (from architecture) |
| Broadcast custom events | ✅ | ✅ | `bar.trigger` / `bar.subscribe` |
| User-defined Lua provider module | ❌ | ✅ | `require` a Lua module |

**Key gap — HTTP provider:**
Without a built-in HTTP fetch, users must shell out to `curl` per tick — expensive and awkward. Even a simple `bar.fetch(url, fn)` that runs async and calls `fn(response)` on the Lua queue would cover the vast majority of use cases (weather, crypto price, CI status, etc.).

**Key gap — reactive / observable values:**
Instead of polling every N seconds, let users declare `local cpu = bar.watch("cpu")` and attach callbacks that fire when the value changes. Eliminates unnecessary timer churn and makes configs more declarative.

---

## 7. SF Symbols (noribar's key differentiator)

| Capability | sketchybar | noribar | Notes / gaps |
|---|---|---|---|
| Render SF Symbol as static glyph | ✅ | ✅ | |
| Rendering mode: monochrome | ✅ | ✅ | |
| Rendering mode: hierarchical | ❌ | ✅ | |
| Rendering mode: palette (multi-color) | ❌ | ✅ | |
| Rendering mode: multicolor (system) | ❌ | ✅ | |
| Variable value (0…1 continuous) | ❌ | ✅ | wifi signal, battery, volume |
| Symbol size / weight / scale | ✅ | ✅ | |
| Effect: bounce | ❌ | ✅ | macOS 14+ |
| Effect: pulse | ❌ | ✅ | macOS 14+ |
| Effect: scale | ❌ | ✅ | macOS 14+ |
| Effect: appear / disappear | ❌ | ✅ | macOS 14+ |
| Effect: wiggle | ❌ | ✅ | macOS 14+ |
| Effect: rotate | ❌ | ✅ | macOS 14+ |
| Effect: breathe | ❌ | ✅ | macOS 14+ |
| Effect: variableColor | ❌ | ✅ | macOS 14+ |
| Effect: magic replace | ❌ | ✅ | macOS 14+ |
| Effect: draw-on / draw-off | ❌ | ✅ | macOS 26 / SF Symbols 7 |
| Continuous symbol animation (loop) | ❌ | ⚠️ | Some effects support repeat; needs loop API |
| Animate variable value (battery charging) | ❌ | ⚠️ | Animate the 0…1 value over time |
| Palette colors user-defined | ❌ | ⚠️ | Need `palette = {"#ff0000", "#00ff00"}` on symbol |
| Per-render-mode fallback on older macOS | ❌ | ✅ | D5 gates with #available |

**This entire category is a noribar exclusive vs sketchybar.** The design is mostly sound; gaps are in the API surface (palette colors, looping, animating variable values).

---

## 8. Window & Display

| Capability | sketchybar | noribar | Notes / gaps |
|---|---|---|---|
| Bar on top of screen | ✅ | ✅ | |
| Bar on bottom of screen | ✅ | ⚠️ | Architecture allows it; not yet designed |
| Bar on left / right edge | ❌ | ⚠️ | Interesting for vertical bars; needs layout rethink |
| Non-full-width bar | ✅ | ⚠️ | `width = 800, position = center` |
| Multiple bars on one display | ❌ | ⚠️ | Useful (one at top, one at bottom) |
| Per-display different layouts | ✅ | ⚠️ | **Gap** — needs multi-display model |
| Per-display bar height | ✅ | ⚠️ | |
| Auto-hide (slide out when unfocused) | ✅ | ⚠️ | Needs element transition design |
| Always-on-top / all-Spaces | ✅ | ✅ | SkyLight (D3/D6) |
| Over-fullscreen | ✅ | ✅ | SkyLight |
| Non-activating | ✅ | ✅ | |
| Hide on fullscreen | ✅ | ⚠️ | Listen to fullscreen notification |
| Show on specific Space only | ❌ | ⚠️ | Element visible only on Space N |
| Hide on specific app (e.g. hide during presentation) | ❌ | ⚠️ | Per-app visibility rule |
| Notch-aware (built-in) | ❌ | ✅ | Five zones + animated transition |
| User-defined notch transition | ❌ | ✅ | Escape hatch fn |
| Secondary/external display bar | ✅ | ⚠️ | Multi-display design needed |
| Native menu bar replacement | ⚠️ partial | ⚠️ | Hiding Apple menu bar; complex |
| Floating panels (above bar height) | ❌ | ⚠️ | For popups — see Interaction section |
| Transparent bar | ✅ | ✅ | Via element/area background opacity |

**Key gap — multi-display:**
No serious ricing bar can ignore multiple displays. The multi-display model needs a first-class design: is each display an independent bar instance? Does one config drive all displays with per-display overrides? Needs a spike.

---

## 9. Scripting & Extensibility

| Capability | sketchybar | noribar | Notes / gaps |
|---|---|---|---|
| Config hot-reload on file save | ✅ | ✅ | kqueue watcher |
| Multiple config files / imports | ✅ via require | ✅ | Lua require |
| Config split across files | ✅ | ✅ | |
| Reusable component functions | ❌ | ✅ | Lua functions / closures |
| Plugin / package system | ❌ | ⚠️ | `require 'noribar-spotify'` — needs module search path design |
| Config validation with error messages | ❌ | ⚠️ | Typed field reader (M1 debt) |
| Persistent key-value store | ❌ | ⚠️ | `bar.store.get/set` — survives reload |
| Shared state between elements | ❌ | 🔧 | Lua module-level variables |
| Cross-element communication | ❌ | 🔧 | `bar.trigger` custom events |
| Dynamic element creation / removal | ✅ | ✅ | `bar.add` / element:remove() |
| Programmatic reordering of elements | ❌ | ⚠️ | Needs element order API |
| Conditional rendering | ❌ | ✅ | Lua if/else, show/hide |
| Config from environment variables | ❌ | 🔧 | `os.getenv` in Lua |
| Config from file (JSON, TOML parsing) | ❌ | ⚠️ | Lua JSON library bundled? |
| Config from HTTP endpoint | ❌ | ⚠️ | Follows from HTTP provider |
| User-defined custom events | ✅ | ✅ | `bar.trigger` / `bar.subscribe` |
| IPC from external CLI | ✅ | ✅ | Unix socket (planned) |
| Broadcast to all subscribers | ✅ | ✅ | |
| Timeout / rate-limit callbacks | ❌ | ⚠️ | Debounce helper: `bar.debounce(fn, 0.1)` |
| Sandboxing (restrict os/io/require) | ❌ | ⚠️ | Q8 open; must decide policy |
| Access to clipboard | ❌ | ⚠️ | NSPasteboard bridge |
| Run AppleScript / JXA | ❌ | 🔧 | `os.execute` escape hatch |
| Custom Lua C extension loading | ❌ | ⚠️ | `.so` loading via `require` — sandbox concern |

**Key gap — persistent store:**
Without persistence, state resets on every hot-reload. A simple `bar.store.get(key)` / `bar.store.set(key, value)` backed by a JSON file lets users persist workspace, toggles, counters without writing their own file I/O.

**Key gap — debounce / throttle helpers:**
Users connecting to fast data sources (audio, mouse) will need `bar.debounce` and `bar.throttle` to avoid hammering the Lua queue.

---

## 10. System Integration

| Capability | sketchybar | noribar | Notes / gaps |
|---|---|---|---|
| Current Space / desktop number | ✅ event | ⚠️ | Provider needed |
| Space name | ❌ | ⚠️ | |
| Space layout (tiling WM info) | ❌ | 🔧 | IPC from yabai / Aerospace via CLI |
| Front application name / bundle ID | ✅ | ✅ | FrontAppProvider |
| Front app window title | ❌ | ⚠️ | Accessibility API; privacy concern |
| Front app icon | ❌ | ⚠️ | NSRunningApplication.icon |
| Front app menu bar items | ❌ | ⚠️ | Alias native menu bar items in bar |
| Battery: level, charging, time remaining | ❌ | ⚠️ | IOKit |
| Battery: power source (AC/battery) | ❌ | ⚠️ | |
| Network: SSID, signal strength | ❌ | ⚠️ | CoreWLAN |
| Network: IP address | ❌ | ⚠️ | |
| Network: up/down speed | ❌ | ⚠️ | |
| CPU: overall / per-core usage | ❌ | ⚠️ | |
| Memory: used / free / pressure | ❌ | ⚠️ | |
| Disk: usage / I/O | ❌ | ⚠️ | |
| Audio: output volume | ❌ | ⚠️ | CoreAudio |
| Audio: input volume (mic) | ❌ | ⚠️ | |
| Audio: output device name | ❌ | ⚠️ | |
| Audio: mute state | ❌ | ⚠️ | |
| Now playing: track, artist, artwork | ❌ | ⚠️ | MediaRemote private API or MRNowPlayingInfoCenter |
| Calendar: next event | ❌ | ⚠️ | EventKit — requires permission |
| Notification count | ❌ | ⚠️ | No public API; hard |
| Do Not Disturb / Focus state | ❌ | ⚠️ | |
| Night Shift / True Tone state | ❌ | ⚠️ | |
| Screen recording active | ❌ | ⚠️ | Privacy-sensitive |
| VPN connected | ❌ | ⚠️ | NetworkExtension |
| AirPods / Bluetooth devices | ❌ | ⚠️ | IOBluetooth |
| Time zone | ❌ | 🔧 | Lua os.date |

**Sketchybar relies on user scripts for all system data.** noribar native providers remove per-tick process spawning but require us to build (or expose) each data source. The escape hatch for anything not built-in is a shell command via `os.execute` — which must remain available (sandbox policy decision).

---

## Summary: most critical gaps to close before v1

Ranked by how badly a user would need to fork or give up:

1. **Animation chaining + handle** — without `on_complete` and `anim:cancel()`, complex animations are impossible to compose cleanly.
2. **Hover/focus input events** — fundamental to any interactive bar element.
3. **Multi-display model** — non-negotiable for a serious bar; needs a design spike.
4. **HTTP fetch provider** — removes the need to shell out to `curl` for every web-based widget.
5. **Persistent key-value store** — state lost on every reload is a constant pain point.
6. **Popup / overlay elements** — click-to-reveal is a core interaction pattern.
7. **Canvas / custom draw escape hatch** — the ultimate escape hatch; prevents any visual fork.
8. **Gradient backgrounds** — expected by the ricing community; straightforward to implement.
9. **Bundled font file support** — Nerd Fonts are ubiquitous in ricing configs.
10. **Reactive / observable values** — makes configs declarative instead of timer-driven.
11. **Debounce / throttle helpers** — quality-of-life for provider callbacks.
12. **Per-display layout** — needed for multi-monitor setups.
13. **Show/hide on app / Space / fullscreen rules** — per-context visibility without user-written observers.
14. **Constraint layout (limited)** — at least "align trailing of A to leading of B".
15. **Sandbox policy decision** — must be decided before shipping; affects what escape hatches are available.
