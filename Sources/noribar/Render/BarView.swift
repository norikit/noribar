import AppKit

/// The layer-backed AppKit host for the bar's items, laid out as three regions
/// (left / center / right). This is the content view of whatever `WindowBackend` hosts it
/// (D2 — an AppKit/CALayer tree, so native SF Symbol effects work).
///
/// It owns layout only; item lifecycle/state lives in `BarStore`.
final class BarView: NSView {
    let leftStack = BarView.region()
    let centerStack = BarView.region()
    let rightStack = BarView.region()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.92).cgColor

        addSubview(leftStack)
        addSubview(centerStack)
        addSubview(rightStack)
        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            centerStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func stack(for position: BarPosition) -> NSStackView {
        switch position {
        case .left: return leftStack
        case .center: return centerStack
        case .right: return rightStack
        }
    }

    private static func region() -> NSStackView {
        let s = NSStackView()
        s.orientation = .horizontal
        s.spacing = 2
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }
}
