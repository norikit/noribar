//
//  BarPanel.swift — the window half of the spike.
//
//  A1: configure a borderless, non-activating NSPanel using ONLY public AppKit API.
//  A2: additionally retag the panel's real CGWindowID through the private SLS API so
//      it gains the ricing powers AppKit can't fully express (prevents-activation,
//      above-fullscreen level, belt-and-braces stickiness).
//

import AppKit

enum Approach: String {
    case a1   // public AppKit only
    case a2   // A1 + private SLS retag (expected winner)
}

/// Non-activating panel that refuses to become key/main so the previously focused
/// app keeps keyboard focus even while our bar updates.
final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class Bar {
    let panel: BarPanel
    let strip: SymbolStrip
    let approach: Approach
    private(set) var dedicatedSpace: UInt64 = 0

    init(approach: Approach, useDedicatedSpace: Bool) {
        self.approach = approach

        let screen = NSScreen.main!.frame
        let height: CGFloat = 32
        let frame = NSRect(x: screen.minX, y: screen.maxY - height, width: screen.width, height: height)

        panel = BarPanel(contentRect: frame,
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered,
                         defer: false)

        // ---- A1: public-API ricing config ----------------------------------
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

        strip = SymbolStrip(frame: NSRect(origin: .zero, size: frame.size))
        panel.contentView = strip

        if useDedicatedSpace { self.wantsDedicatedSpace = true }
    }

    private var wantsDedicatedSpace = false

    func show() {
        panel.orderFrontRegardless()   // show without activating the app
        if approach == .a2 { applySLS(useDedicated: wantsDedicatedSpace) }
    }

    /// The real on-screen window id AppKit allocated for the panel.
    var windowID: UInt32 { UInt32(panel.windowNumber) }

    // ---- A2: private SLS retag ---------------------------------------------
    private func applySLS(useDedicated: Bool) {
        let cid = SLS.mainConnectionID
        let wid = windowID
        guard cid > 0, wid > 0 else {
            print("‼️  SLS unavailable (cid=\(cid) wid=\(wid))")
            return
        }

        // 1. Never participate in activation, no matter what AppKit does.
        SLS.setWindowTags(cid, wid, SLS.kCGSPreventsActivationTagBit)
        // 2. Smooth Expose/Mission-Control fade like the real menu bar.
        SLS.setWindowTags(cid, wid, SLS.kCGSExposeFadeTagBit)
        // 3. Belt-and-braces stickiness (AppKit already gives all-Spaces).
        SLS.setWindowTags(cid, wid, SLS.kCGSStickyTagBit)

        // 4. Push above fullscreen. CGShieldingWindowLevel sits above the menu bar
        //    and above most fullscreen content; experiment range documented in FINDINGS.
        let lvl = Int32(CGShieldingWindowLevel())
        SLS.setWindowLevel(cid, wid, lvl)

        // 5. Optional maximal-stickiness route: a dedicated, absolute-level space that
        //    is shown on every display. Off by default (it perturbs Mission Control).
        if useDedicated {
            let sid = SLS.createSpace()
            if sid != 0 {
                dedicatedSpace = sid
                SLS.setSpaceAbsoluteLevel(sid, lvl)
                SLS.showSpace(sid)
                SLS.addWindow(wid, toSpace: sid)
            } else {
                print("‼️  SLSSpaceCreate returned 0 (route unavailable on this OS)")
            }
        }
    }
}
