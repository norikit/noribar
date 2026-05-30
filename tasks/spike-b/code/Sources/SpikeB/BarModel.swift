import Foundation

/// Where an item sits on the bar.
enum BarPosition: String {
    case left
    case right
    case center
}

/// A state-change command produced on the Lua queue and applied on the main
/// thread. This is the marshalling boundary: the Lua side never touches AppKit;
/// it only emits these, which `DispatchQueue.main` drains into the view tree.
enum BarCommand {
    /// Create a new item. Sent once per `bar.add`.
    case add(id: Int, position: BarPosition, icon: String, label: String)
    /// Mutate an existing item. `nil` fields are left unchanged.
    case set(id: Int, icon: String?, label: String?)
    /// Tear everything down (used by hot reload before a fresh config runs).
    case clear
}

/// The authoritative item record. Lives on the Lua side; the renderer keeps its
/// own mirror built from commands.
struct BarItem {
    let id: Int
    let position: BarPosition
    var icon: String
    var label: String
}
