import AppKit

/// Enforces **D6's hard rule**: *one in-flight symbol animation per `NSImageView`.*
///
/// Spike A found that stacking a content transition (`.replace`) and a discrete effect
/// (e.g. `.drawOn` / `.bounce`) on the *same* `NSImageView` in the *same* run-loop turn
/// crashes Apple's RenderBox animation thread (`EXC_BAD_ACCESS` in
/// `RB::Symbol::Animation::apply`). A fast Lua timer (`bar.every(0.1, …)`) that swaps an
/// icon *and* requests an effect is exactly the trap.
///
/// `SymbolAnimator` is the single-animator unit guarding one icon view. It:
///   1. **Coalesces** rapid `request(...)`s for the same view into one apply per run-loop
///      turn (a burst of queued `:set`s collapses to the latest desired state), and
///   2. **Resolves** that desired state into **at most one animating mutation** — never a
///      content transition *and* a discrete effect together.
///
/// The resolution is a pure function (`Resolution.resolve`) so the D6 invariant can be
/// unit-tested headlessly, with no window server (see `SelfTest`).
final class SymbolAnimator {

    /// One concrete mutation to apply to the image view. A plain `.setImage` is *not* an
    /// animation; `.contentTransition` and `.discreteEffect` each are. The resolver
    /// guarantees a plan holds **at most one** animating mutation.
    enum Mutation: Equatable {
        case setImage(icon: String)                 // non-animated; just swap the image
        case contentTransition(icon: String)        // animated swap (.replace)
        case discreteEffect(SymbolEffect)           // animated effect added to current symbol
    }

    /// Pure planner — given the icon currently shown and the coalesced desired state,
    /// produce the mutation list. Enforces the D6 invariant (≤1 animating mutation; never
    /// a content transition together with a discrete effect).
    enum Resolution {
        static func resolve(currentIcon: String,
                            desiredIcon: String?,
                            effect: SymbolEffect?) -> [Mutation] {
            let iconChanges = desiredIcon != nil && desiredIcon != currentIcon
            let newIcon = desiredIcon ?? currentIcon

            switch effect {
            case .some(let e) where e.isContentTransition:
                // The swap itself is the animation. If the icon didn't actually change,
                // there's nothing to transition to — fall back to a discrete-free no-op.
                return iconChanges ? [.contentTransition(icon: newIcon)] : []

            case .some(let e):
                // Discrete effect: set the (possibly new) image *without* animation first,
                // then add exactly one discrete effect. One in-flight animation total.
                return iconChanges ? [.setImage(icon: newIcon), .discreteEffect(e)]
                                   : [.discreteEffect(e)]

            case .none:
                return iconChanges ? [.setImage(icon: newIcon)] : []
            }
        }

        /// The D6 invariant a plan must satisfy. Exposed for the self-test.
        static func isValid(_ plan: [Mutation]) -> Bool {
            let animating = plan.filter {
                if case .setImage = $0 { return false }
                return true
            }
            return animating.count <= 1
        }
    }

    private weak var imageView: NSImageView?
    /// The icon name currently displayed (so we can tell whether a `:set` changes it).
    private var currentIcon: String

    // Coalescing state: the latest desired icon/effect awaiting the next-turn flush.
    private var pendingIcon: String?
    private var pendingEffect: SymbolEffect?
    private var flushScheduled = false

    init(imageView: NSImageView, initialIcon: String) {
        self.imageView = imageView
        self.currentIcon = initialIcon
    }

    /// Request an icon and/or effect. Safe to call many times per turn; the animator
    /// applies the *coalesced* result once, on the next run-loop turn.
    func request(icon: String?, effect: SymbolEffect?) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let icon { pendingIcon = icon }
        // Last writer wins for the effect within a turn (mirrors how rapid :sets collapse).
        if let effect { pendingEffect = effect }
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        // One async hop coalesces every request already queued this turn into a single apply.
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }

    private func flush() {
        flushScheduled = false
        let plan = Resolution.resolve(currentIcon: currentIcon,
                                      desiredIcon: pendingIcon,
                                      effect: pendingEffect)
        pendingIcon = nil
        pendingEffect = nil
        guard let imageView, !plan.isEmpty else { return }

        for mutation in plan {
            switch mutation {
            case .setImage(let icon):
                if let img = NSImage(systemSymbolName: icon, accessibilityDescription: icon) {
                    imageView.image = img
                }
                currentIcon = icon
            case .contentTransition(let icon):
                guard let img = NSImage(systemSymbolName: icon, accessibilityDescription: icon) else { break }
                if #available(macOS 14.0, *) {
                    imageView.setSymbolImage(img, contentTransition: .replace)
                } else {
                    imageView.image = img   // D5: static fallback on macOS 13
                }
                currentIcon = icon
            case .discreteEffect(let effect):
                applyDiscrete(effect, to: imageView)
            }
        }
    }

    private func applyDiscrete(_ effect: SymbolEffect, to view: NSImageView) {
        guard #available(macOS 14.0, *) else { return }   // D5: no-op (static) on macOS 13
        switch effect {
        case .bounce: view.addSymbolEffect(.bounce)
        case .pulse:  view.addSymbolEffect(.pulse)
        case .scale:  view.addSymbolEffect(.scale.up)
        case .replace: break   // handled as a content transition, never here
        }
    }
}
