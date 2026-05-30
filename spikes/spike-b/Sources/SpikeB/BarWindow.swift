import AppKit

/// One rendered item: an SF Symbol icon (public AppKit) + a text label.
private final class BarItemView: NSStackView {
    private let iconView = NSImageView()
    private let labelField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 4
        edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

        iconView.contentTintColor = .white
        iconView.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        labelField.textColor = .white
        labelField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        labelField.backgroundColor = .clear
        labelField.isBezeled = false
        labelField.isEditable = false

        addArrangedSubview(iconView)
        addArrangedSubview(labelField)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(icon: String?, label: String?) {
        if let icon {
            if icon.isEmpty {
                iconView.isHidden = true
            } else if let img = NSImage(systemSymbolName: icon, accessibilityDescription: icon) {
                iconView.image = img
                iconView.isHidden = false
            } else {
                // Not a known SF Symbol — show the raw name so the config author notices.
                iconView.isHidden = true
            }
        }
        if let label {
            labelField.stringValue = label
            labelField.isHidden = label.isEmpty
        }
    }
}

/// A plain, ordinary `NSWindow` rendering the bar as three horizontal regions.
/// Public AppKit only — deliberately no SkyLight/private APIs (decoupled from Spike A).
final class BarRenderer {
    let window: NSWindow
    private let leftStack = BarRenderer.region(.leading)
    private let centerStack = BarRenderer.region(.centerX)
    private let rightStack = BarRenderer.region(.trailing)
    private var views: [Int: BarItemView] = [:]
    private var positions: [Int: BarPosition] = [:]

    init() {
        let height: CGFloat = 28
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: 0, y: screen.maxY - height, width: screen.width, height: height)

        window = NSWindow(contentRect: frame,
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.ignoresMouseEvents = true

        let content = NSView(frame: frame)
        content.wantsLayer = true
        window.contentView = content

        content.addSubview(leftStack)
        content.addSubview(centerStack)
        content.addSubview(rightStack)
        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6),
            leftStack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            rightStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
            rightStack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            centerStack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    func show() {
        window.orderFrontRegardless()
    }

    /// Apply a marshalled command. MUST be called on the main thread.
    func apply(_ command: BarCommand) {
        dispatchPrecondition(condition: .onQueue(.main))
        switch command {
        case .clear:
            for v in views.values { v.removeFromSuperview() }
            views.removeAll()
            positions.removeAll()

        case let .add(id, position, icon, label):
            let v = BarItemView()
            v.update(icon: icon, label: label)
            views[id] = v
            positions[id] = position
            stack(for: position).addArrangedSubview(v)

        case let .set(id, icon, label):
            views[id]?.update(icon: icon, label: label)
        }
    }

    private func stack(for p: BarPosition) -> NSStackView {
        switch p {
        case .left: return leftStack
        case .center: return centerStack
        case .right: return rightStack
        }
    }

    private static func region(_ alignment: NSLayoutConstraint.Attribute) -> NSStackView {
        let s = NSStackView()
        s.orientation = .horizontal
        s.spacing = 2
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }
}
