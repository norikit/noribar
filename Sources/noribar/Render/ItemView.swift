import AppKit

/// One bar item on screen: an SF Symbol icon + a text label. **The single-animator unit**
/// — its `SymbolAnimator` owns the icon view and guarantees at most one in-flight symbol
/// animation (D6). All mutation is main-thread only.
final class ItemView: NSStackView {
    private let iconView = NSImageView()
    private let labelField = NSTextField(labelWithString: "")
    private var animator: SymbolAnimator!
    private var currentIconName: String

    init(icon: String, label: String) {
        self.currentIconName = icon
        super.init(frame: .zero)

        orientation = .horizontal
        alignment = .centerY
        spacing = 4
        edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

        iconView.contentTintColor = .white
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true

        labelField.textColor = .white
        labelField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        labelField.backgroundColor = .clear
        labelField.isBezeled = false
        labelField.isEditable = false

        addArrangedSubview(iconView)
        addArrangedSubview(labelField)

        animator = SymbolAnimator(imageView: iconView, initialIcon: icon)
        setIconImmediately(icon)
        setLabel(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Apply a `:set`. Label changes are immediate (cheap, non-animated); icon/effect
    /// changes are routed through the animator so D6's one-animation rule is honored and
    /// rapid updates coalesce.
    func apply(icon: String?, label: String?, effect: SymbolEffect?) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let label { setLabel(label) }
        if icon != nil || effect != nil {
            animator.request(icon: icon, effect: effect)
            if let icon { currentIconName = icon }
        }
    }

    private func setLabel(_ label: String) {
        labelField.stringValue = label
        labelField.isHidden = label.isEmpty
    }

    /// Initial, non-animated icon set at construction (before any effect is possible).
    private func setIconImmediately(_ icon: String) {
        if icon.isEmpty {
            iconView.isHidden = true
            return
        }
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: icon) {
            iconView.image = img
            iconView.isHidden = false
        } else {
            // Unknown SF Symbol — hide rather than crash; the author sees a missing icon.
            iconView.isHidden = true
        }
    }
}
