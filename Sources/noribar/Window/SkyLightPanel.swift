import AppKit

/// The production window backend (D3 / D6): a borderless **non-activating `NSPanel`** that
/// owns the AppKit view tree, with its real `CGWindowID` **additively** retagged through
/// the private SkyLight API for the ricing powers AppKit can't fully express
/// (prevents-activation, above-fullscreen level, belt-and-braces stickiness).
///
/// Promoted from Spike A's `BarPanel` + `Bar`. The pure-SLS viewless window was rejected
/// (symbol effects need an AppKit host) — see decisions D6.
final class SkyLightPanel: WindowBackend {

    /// Non-activating panel that refuses key/main so the previously focused app keeps
    /// keyboard focus even while the bar updates.
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private let panel: Panel
    let barView: BarView
    private let useDedicatedSpace: Bool

    init(useDedicatedSpace: Bool = false) {
        self.useDedicatedSpace = useDedicatedSpace

        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let height: CGFloat = 28
        let frame = NSRect(x: screen.minX, y: screen.maxY - height, width: screen.width, height: height)

        panel = Panel(contentRect: frame,
                      styleMask: [.borderless, .nonactivatingPanel],
                      backing: .buffered,
                      defer: false)

        // Public-API ricing config (Spike A "A1").
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        // Above the system menu bar so we can replace it.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        // all-Spaces + over fullscreen + don't appear in Cmd-` cycle.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        barView = BarView(frame: NSRect(origin: .zero, size: frame.size))
        barView.autoresizingMask = [.width, .height]
        panel.contentView = barView
    }

    /// The real on-screen window id AppKit allocated for the panel.
    private var windowID: UInt32 { UInt32(panel.windowNumber) }
    private var dedicatedSpace: UInt64 = 0

    func show() {
        panel.orderFrontRegardless()   // show without activating the app
        applySLS()
    }

    // MARK: - Additive SLS retag (Spike A "A2")

    private func applySLS() {
        let cid = SLS.mainConnectionID
        let wid = windowID
        guard cid > 0, wid > 0 else {
            FileHandle.standardError.write(Data("‼️  SLS unavailable (cid=\(cid) wid=\(wid))\n".utf8))
            return
        }

        // Never participate in activation; smooth Expose/Mission-Control fade; sticky.
        SLS.setWindowTags(cid, wid, SLS.kCGSPreventsActivationTagBit)
        SLS.setWindowTags(cid, wid, SLS.kCGSExposeFadeTagBit)
        SLS.setWindowTags(cid, wid, SLS.kCGSStickyTagBit)

        // Push above fullscreen.
        let lvl = Int32(CGShieldingWindowLevel())
        SLS.setWindowLevel(cid, wid, lvl)

        // Optional maximal-stickiness route (off by default; perturbs Mission Control).
        if useDedicatedSpace {
            let sid = SLS.createSpace()
            if sid != 0 {
                dedicatedSpace = sid
                SLS.setSpaceAbsoluteLevel(sid, lvl)
                SLS.showSpace(sid)
                SLS.addWindow(wid, toSpace: sid)
            }
        }
    }

    func diagnostics() -> [String: String] {
        var d: [String: String] = [
            "WINDOWID": String(windowID),
            "SLS_CID": String(SLS.mainConnectionID),
            "ACTIVATION_POLICY": String(NSApp.activationPolicy().rawValue),
            "PANEL_IS_KEY": String(panel.isKeyWindow),
            "PANEL_LEVEL": String(panel.level.rawValue),
            "SPACES_FOR_WINDOW": String(SLS.spaceCount(forWindow: windowID))
        ]
        if dedicatedSpace != 0 { d["DEDICATED_SPACE"] = String(dedicatedSpace) }
        if !SLS.missing.isEmpty { d["SLS_MISSING_SYMBOLS"] = SLS.missing.sorted().joined(separator: ",") }
        return d
    }
}
