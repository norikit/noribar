//
//  SymbolStrip.swift — the actual "bar": a layer-backed AppKit view tree of
//  NSImageViews showing SF Symbols, exercising every native symbol effect we can
//  reach on the build SDK. This is the half of the spike the window must not break.
//

import AppKit

/// One symbol slot + the rendering mode it demonstrates.
private struct Slot {
    let name: String
    let config: NSImage.SymbolConfiguration
    /// 0...1 variable value for variable-rendering symbols (wifi, speaker…). nil = none.
    let variable: Double?
}

final class SymbolStrip: NSView {

    private var imageViews: [NSImageView] = []
    private var slots: [Slot] = []
    private var tick = 0

    /// Restrict to a single effect for crash bisection. nil = all. One of:
    /// bounce, varcolor, pulse, replace, draw.
    var only: String? = nil
    private func wants(_ e: String) -> Bool { only == nil || only == e }

    /// Per-effect run log so we can print a support table at the end.
    static var effectLog: [String: String] = [:]   // effect -> "ran" / "unavailable" / "n/a (OS)"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.92).cgColor
        buildSlots()
        layoutSlots()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildSlots() {
        // A spread of rendering modes, all on macOS 13+ surface.
        var palette = NSImage.SymbolConfiguration(paletteColors: [.systemRed, .systemYellow, .systemGreen])
        palette = palette.applying(.init(pointSize: 18, weight: .semibold))

        var hierarchical = NSImage.SymbolConfiguration(hierarchicalColor: .systemTeal)
        hierarchical = hierarchical.applying(.init(pointSize: 18, weight: .semibold))

        var multicolor = NSImage.SymbolConfiguration.preferringMulticolor()
        multicolor = multicolor.applying(.init(pointSize: 18, weight: .semibold))

        let mono = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            .applying(.init(paletteColors: [.white]))

        // One animation per view: each NSImageView hosts exactly one effect. Stacking a
        // content-transition (.replace) and a discrete effect (.drawOn) on the SAME view
        // in the same run-loop turn crashes RenderBox on macOS 26 (see FINDINGS.md).
        slots = [
            Slot(name: "wifi",               config: hierarchical, variable: 1.0),  // [0] variableValue + .pulse
            Slot(name: "speaker.wave.3.fill", config: mono,        variable: 1.0),  // [1] .variableColor.iterative
            Slot(name: "battery.100.bolt",   config: multicolor,   variable: nil),  // [2] multicolor + .bounce
            Slot(name: "bell.fill",           config: palette,     variable: nil),  // [3] palette + magic .replace
            Slot(name: "square.and.arrow.up", config: hierarchical, variable: nil), // [4] .drawOn / .drawOff
        ]
    }

    private func layoutSlots() {
        let pad: CGFloat = 14
        let gap: CGFloat = 22
        var x = pad
        for slot in slots {
            let iv = NSImageView(frame: NSRect(x: x, y: 0, width: 24, height: bounds.height))
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.symbolConfiguration = slot.config
            iv.image = makeImage(slot)
            iv.wantsLayer = true
            addSubview(iv)
            imageViews.append(iv)
            x += 24 + gap
        }
    }

    private func makeImage(_ slot: Slot) -> NSImage? {
        let img: NSImage?
        if let v = slot.variable {
            img = NSImage(systemSymbolName: slot.name, variableValue: v, accessibilityDescription: slot.name)
        } else {
            img = NSImage(systemSymbolName: slot.name, accessibilityDescription: slot.name)
        }
        return img
    }

    // MARK: - Fire every effect we can reach, cycling so they're observable.

    func fireEffects() {
        tick += 1
        guard #available(macOS 14.0, *) else {
            SymbolStrip.effectLog[".bounce"] = "n/a (<14)"
            SymbolStrip.effectLog[".variableColor"] = "n/a (<14)"
            SymbolStrip.effectLog["magic .replace"] = "n/a (<14)"
            return
        }

        // 0: bounce  (macOS 14+)
        if wants("bounce") {
            imageViews[2].addSymbolEffect(.bounce)
            SymbolStrip.effectLog[".bounce"] = "ran"
        }

        // 1: variableColor iterative (macOS 14+)
        if wants("varcolor") {
            imageViews[1].addSymbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
            SymbolStrip.effectLog[".variableColor.iterative"] = "ran"
        }

        // 2: pulse (macOS 14+) — extra effect to show the engine is live.
        if wants("pulse") {
            imageViews[0].addSymbolEffect(.pulse)
            SymbolStrip.effectLog[".pulse"] = "ran"
        }

        // 3: magic replace content transition (macOS 14+; "magic replace" improved 15+)
        if wants("replace") {
            let bellOn  = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "bell")
            let bellOff = NSImage(systemSymbolName: "bell.slash.fill", accessibilityDescription: "bell off")
            let replaceImg = (tick % 2 == 0) ? bellOn : bellOff
            if let replaceImg {
                imageViews[3].setSymbolImage(replaceImg, contentTransition: .replace)
                SymbolStrip.effectLog["magic .replace"] = "ran"
            }
        }

        // 4: draw-on / draw-off (SF Symbols 7 / macOS 26) — the showcase effects.
        if wants("draw") { fireDrawOnOff() }
    }

    private func fireDrawOnOff() {
        #if compiler(>=6.0)
        if #available(macOS 26.0, *) {
            // .drawOn / .drawOff are content transitions in SF Symbols 7.
            if tick % 2 == 0 {
                imageViews[4].addSymbolEffect(.drawOff)
                SymbolStrip.effectLog[".drawOff"] = "ran"
            } else {
                imageViews[4].addSymbolEffect(.drawOn)
                SymbolStrip.effectLog[".drawOn"] = "ran"
            }
        } else {
            SymbolStrip.effectLog[".drawOn/.drawOff"] = "n/a (<26)"
        }
        #else
        SymbolStrip.effectLog[".drawOn/.drawOff"] = "unavailable (SDK < 26)"
        #endif
    }

    // Click anywhere on the bar also fires the effects (manual trigger).
    override func mouseDown(with event: NSEvent) { fireEffects() }
}
