import AppKit

/// The main-thread item registry and the **single place** that applies `BarCommand`s to
/// the view tree (D7's marshalling target: `LuaRuntime.emit` does
/// `DispatchQueue.main.async { store.apply(cmd) }`).
///
/// `BarStore` maps item id → `ItemView` and inserts each into the correct `BarView` region.
/// It enforces the main-thread contract with a `dispatchPrecondition`; per-item animation
/// safety (D6) is delegated to each `ItemView`'s `SymbolAnimator`.
final class BarStore {
    private let barView: BarView
    private var views: [Int: ItemView] = [:]

    init(barView: BarView) {
        self.barView = barView
    }

    func apply(_ command: BarCommand) {
        dispatchPrecondition(condition: .onQueue(.main))
        switch command {
        case .clear:
            for v in views.values { v.removeFromSuperview() }
            views.removeAll()

        case let .add(id, position, icon, label):
            let v = ItemView(icon: icon, label: label)
            views[id] = v
            barView.stack(for: position).addArrangedSubview(v)

        case let .set(id, icon, label, effect):
            views[id]?.apply(icon: icon, label: label, effect: effect)
        }
    }

    /// Item count — used by the self-test to confirm commands landed.
    var count: Int { views.count }
}
