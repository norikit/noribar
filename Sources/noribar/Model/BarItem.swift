/// Where an item sits on the bar. (Q5 — minimal: three regions, no nesting yet.)
enum BarPosition: String {
    case left
    case center
    case right
}

/// A native SF Symbol effect a Lua callback can request on an item.
///
/// M1 deliberately exposes a *small* set (Q6 defers the full matrix). Two kinds matter
/// for the D6 collision this milestone resolves:
///   - `.replace` is a **content transition** (the icon swap *is* the animation).
///   - the rest are **discrete** effects added to the current symbol.
/// The distinction is exactly what `SymbolAnimator` must keep from stacking (see D6).
enum SymbolEffect: String {
    case replace            // content transition — macOS 14+
    case bounce             // discrete — macOS 14+
    case pulse              // discrete — macOS 14+
    case scale              // discrete — macOS 14+

    /// True for content-transition effects (applied via `setSymbolImage(_:contentTransition:)`),
    /// false for discrete effects (applied via `addSymbolEffect(_:)`). The two must never be
    /// applied to the same view in the same run-loop turn (D6).
    var isContentTransition: Bool { self == .replace }
}

/// The minimal item schema users configure against in M1 (Q5).
///
/// Deliberately small: `position` (immutable after add) + a mutable `icon`/`label`.
/// Left out for later milestones: graphs, sliders, groups, popups, menu-bar aliases,
/// per-item styling (color/font/padding), click handlers, ordering control.
struct BarItem {
    let id: Int
    let position: BarPosition
    var icon: String
    var label: String
}

/// A state-change command produced on the Lua queue and applied on the main thread.
///
/// This is the marshalling boundary (D7): the Lua side never touches AppKit — it only
/// emits these, which `DispatchQueue.main` drains into the view tree via `BarStore`.
enum BarCommand {
    /// Create a new item. Emitted once per `bar.add`.
    case add(id: Int, position: BarPosition, icon: String, label: String)
    /// Mutate an existing item. `nil` fields are left unchanged; `effect` requests a
    /// native symbol animation on apply.
    case set(id: Int, icon: String?, label: String?, effect: SymbolEffect?)
    /// Tear everything down (hot reload runs this before a fresh config).
    case clear
}
