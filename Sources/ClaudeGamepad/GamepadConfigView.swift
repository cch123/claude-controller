import AppKit

/// A visual gamepad diagram (Xbox-style) with leader lines to dropdowns.
/// Inspired by the classic controller diagram with labels on both sides.
final class GamepadConfigView: NSView {
    struct ButtonSlot {
        let key: String
        let label: String
        let buttonPoint: NSPoint   // position on gamepad drawing
        let popupSide: Side
        let popup: NSPopUpButton
    }

    enum Side { case left, right }

    private(set) var slots: [ButtonSlot] = []

    // Coordinate system: flipped (origin top-left), total size 820x580
    override var isFlipped: Bool { true }

    // Drawing constants
    private let cx: CGFloat = 410   // gamepad center x
    private let cy: CGFloat = 260   // gamepad center y

    init(mapping: ButtonMapping) {
        super.init(frame: NSRect(x: 0, y: 0, width: 820, height: 580))

        // Button positions on the gamepad (flipped coords)
        // Left side
        let ltPt  = NSPoint(x: cx - 145, y: cy - 145)  // left trigger
        let lbPt  = NSPoint(x: cx - 130, y: cy - 105)  // left bumper
        let dUpPt = NSPoint(x: cx - 85, y: cy + 33)    // d-pad up
        let dDnPt = NSPoint(x: cx - 85, y: cy + 77)    // d-pad down
        let dLtPt = NSPoint(x: cx - 108, y: cy + 55)   // d-pad left
        let dRtPt = NSPoint(x: cx - 62, y: cy + 55)    // d-pad right
        let selPt = NSPoint(x: cx - 35, y: cy - 35)    // select/view
        let lsPt  = NSPoint(x: cx - 85, y: cy - 10)    // left stick

        // Right side
        let rtPt  = NSPoint(x: cx + 145, y: cy - 145)  // right trigger
        let rbPt  = NSPoint(x: cx + 130, y: cy - 105)  // right bumper
        let yPt   = NSPoint(x: cx + 85, y: cy - 45)    // Y
        let xPt   = NSPoint(x: cx + 55, y: cy - 15)    // X
        let bPt   = NSPoint(x: cx + 115, y: cy - 15)   // B
        let aPt   = NSPoint(x: cx + 85, y: cy + 15)    // A
        let stPt  = NSPoint(x: cx + 35, y: cy - 35)    // start/menu
        let rsPt  = NSPoint(x: cx + 50, y: cy + 55)    // right stick

        let defs: [(String, String, NSPoint, Side)] = [
            // Left: triggers, bumper, stick, select, d-pad
            ("lt",       "LT / L2",       ltPt,  .left),
            ("lb",       "LB / L1",       lbPt,  .left),
            ("stickL",   "LS (按下)",      lsPt,  .left),
            ("select",   "View / Select",  selPt, .left),
            ("dpadUp",   "D-pad ↑",       dUpPt, .left),
            ("dpadDown", "D-pad ↓",       dDnPt, .left),
            ("dpadLeft", "D-pad ←",       dLtPt, .left),
            ("dpadRight","D-pad →",       dRtPt, .left),

            // Right: triggers, bumper, face buttons, start, stick
            ("rt",       "RT / R2",       rtPt,  .right),
            ("rb",       "RB / R1",       rbPt,  .right),
            ("y",        "Y / △",         yPt,   .right),
            ("x",        "X / □",         xPt,   .right),
            ("b",        "B / ○",         bPt,   .right),
            ("a",        "A / ✕",         aPt,   .right),
            ("start",    "Menu / Start",  stPt,  .right),
            ("stickR",   "RS (按下)",      rsPt,  .right),
        ]

        let leftDefs = defs.filter { $0.3 == .left }
        let rightDefs = defs.filter { $0.3 == .right }

        let popupW: CGFloat = 165
        let rowH: CGFloat = 33

        func buildSlots(_ items: [(String, String, NSPoint, Side)], popupX: CGFloat, labelAlign: NSTextAlignment) -> [ButtonSlot] {
            var result: [ButtonSlot] = []
            let startY: CGFloat = 55
            for (i, def) in items.enumerated() {
                let py = startY + CGFloat(i) * rowH

                // Label
                let lbl = NSTextField(labelWithString: def.1)
                lbl.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
                lbl.textColor = .secondaryLabelColor
                lbl.alignment = labelAlign
                lbl.frame = NSRect(x: popupX, y: py - 16, width: popupW, height: 14)
                addSubview(lbl)

                // Popup
                let popup = NSPopUpButton(frame: NSRect(x: popupX, y: py, width: popupW, height: 22), pullsDown: false)
                popup.font = NSFont.systemFont(ofSize: 11)
                popup.controlSize = .small
                for action in ButtonAction.allCases {
                    popup.addItem(withTitle: action.rawValue)
                }
                let configKey = mapKey(def.0)
                popup.selectItem(withTitle: actionForKey(configKey, mapping: mapping).rawValue)
                addSubview(popup)

                result.append(ButtonSlot(key: def.0, label: def.1, buttonPoint: def.2, popupSide: def.3, popup: popup))
            }
            return result
        }

        slots = buildSlots(leftDefs, popupX: 5, labelAlign: .left)
              + buildSlots(rightDefs, popupX: 650, labelAlign: .left)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func mapKey(_ key: String) -> String {
        if key == "stickL" || key == "stickR" { return "stickClick" }
        if key == "lt" || key == "rt" { return "none" } // triggers are modifiers
        return key
    }

    private func actionForKey(_ key: String, mapping: ButtonMapping) -> ButtonAction {
        switch key {
        case "a": return mapping.buttonActions.a
        case "b": return mapping.buttonActions.b
        case "x": return mapping.buttonActions.x
        case "y": return mapping.buttonActions.y
        case "lb": return mapping.buttonActions.lb
        case "rb": return mapping.buttonActions.rb
        case "start": return mapping.buttonActions.start
        case "select": return mapping.buttonActions.select
        case "stickClick": return mapping.buttonActions.stickClick
        case "dpadUp": return mapping.buttonActions.dpadUp
        case "dpadDown": return mapping.buttonActions.dpadDown
        case "dpadLeft": return mapping.buttonActions.dpadLeft
        case "dpadRight": return mapping.buttonActions.dpadRight
        default: return .none
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawController(ctx)
        drawLeaderLines(ctx)
    }

    private func drawController(_ ctx: CGContext) {
        // === Main body ===
        let body = NSBezierPath()
        // Top edge with bumper notches
        body.move(to: p(cx - 155, cy - 90))
        body.curve(to: p(cx - 80, cy - 110), controlPoint1: p(cx - 155, cy - 110), controlPoint2: p(cx - 120, cy - 110))
        body.curve(to: p(cx, cy - 100), controlPoint1: p(cx - 50, cy - 110), controlPoint2: p(cx - 20, cy - 100))
        body.curve(to: p(cx + 80, cy - 110), controlPoint1: p(cx + 20, cy - 100), controlPoint2: p(cx + 50, cy - 110))
        body.curve(to: p(cx + 155, cy - 90), controlPoint1: p(cx + 120, cy - 110), controlPoint2: p(cx + 155, cy - 110))
        // Right side into right grip
        body.curve(to: p(cx + 155, cy + 10), controlPoint1: p(cx + 165, cy - 60), controlPoint2: p(cx + 165, cy - 20))
        body.curve(to: p(cx + 120, cy + 120), controlPoint1: p(cx + 155, cy + 50), controlPoint2: p(cx + 145, cy + 95))
        body.curve(to: p(cx + 80, cy + 145), controlPoint1: p(cx + 105, cy + 140), controlPoint2: p(cx + 95, cy + 150))
        body.curve(to: p(cx + 55, cy + 120), controlPoint1: p(cx + 65, cy + 145), controlPoint2: p(cx + 55, cy + 135))
        body.curve(to: p(cx + 45, cy + 40), controlPoint1: p(cx + 50, cy + 90), controlPoint2: p(cx + 45, cy + 65))
        // Bottom middle
        body.curve(to: p(cx, cy + 30), controlPoint1: p(cx + 40, cy + 20), controlPoint2: p(cx + 20, cy + 25))
        body.curve(to: p(cx - 45, cy + 40), controlPoint1: p(cx - 20, cy + 25), controlPoint2: p(cx - 40, cy + 20))
        // Left grip
        body.curve(to: p(cx - 55, cy + 120), controlPoint1: p(cx - 50, cy + 65), controlPoint2: p(cx - 50, cy + 90))
        body.curve(to: p(cx - 80, cy + 145), controlPoint1: p(cx - 55, cy + 135), controlPoint2: p(cx - 65, cy + 145))
        body.curve(to: p(cx - 120, cy + 120), controlPoint1: p(cx - 95, cy + 150), controlPoint2: p(cx - 105, cy + 140))
        body.curve(to: p(cx - 155, cy + 10), controlPoint1: p(cx - 145, cy + 95), controlPoint2: p(cx - 155, cy + 50))
        body.curve(to: p(cx - 155, cy - 90), controlPoint1: p(cx - 165, cy - 20), controlPoint2: p(cx - 165, cy - 60))
        body.close()

        // Fill with subtle gradient effect
        let bodyFill = NSColor.controlBackgroundColor.withAlphaComponent(0.4)
        bodyFill.setFill()
        body.fill()
        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        body.lineWidth = 2.0
        body.lineJoinStyle = .round
        body.stroke()

        // === Triggers (LT / RT) ===
        drawTrigger(ctx, center: p(cx - 130, cy - 120), label: "LT")
        drawTrigger(ctx, center: p(cx + 130, cy - 120), label: "RT")

        // === Bumpers (LB / RB) ===
        drawBumper(ctx, rect: NSRect(x: cx - 148, y: cy - 98, width: 75, height: 14), label: "LB")
        drawBumper(ctx, rect: NSRect(x: cx + 73, y: cy - 98, width: 75, height: 14), label: "RB")

        // === Left stick (upper left) ===
        drawStick(ctx, center: p(cx - 85, cy - 10))

        // === D-pad (lower left) ===
        drawDpad(ctx, center: p(cx - 85, cy + 55))

        // === Right stick (lower right) ===
        drawStick(ctx, center: p(cx + 50, cy + 55))

        // === Face buttons diamond ===
        drawFaceButton(ctx, center: p(cx + 85, cy - 45), label: "Y", color: .systemYellow)
        drawFaceButton(ctx, center: p(cx + 55, cy - 15), label: "X", color: .systemBlue)
        drawFaceButton(ctx, center: p(cx + 115, cy - 15), label: "B", color: .systemRed)
        drawFaceButton(ctx, center: p(cx + 85, cy + 15), label: "A", color: .systemGreen)

        // === Center buttons (View / Menu) ===
        drawCenterButton(ctx, center: p(cx - 35, cy - 35), label: "View")
        drawCenterButton(ctx, center: p(cx + 35, cy - 35), label: "Menu")

        // === Xbox button (center) ===
        let xboxR: CGFloat = 12
        let xboxRect = NSRect(x: cx - xboxR, y: cy - 60 - xboxR, width: xboxR * 2, height: xboxR * 2)
        let xboxCircle = NSBezierPath(ovalIn: xboxRect)
        NSColor.separatorColor.withAlphaComponent(0.2).setFill()
        xboxCircle.fill()
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        xboxCircle.lineWidth = 1.5
        xboxCircle.stroke()
    }

    // MARK: - Component Drawing

    private func drawTrigger(_ ctx: CGContext, center: NSPoint, label: String) {
        let w: CGFloat = 50, h: CGFloat = 22
        let rect = NSRect(x: center.x - w/2, y: center.y - h/2, width: w, height: h)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.separatorColor.withAlphaComponent(0.25).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1.2
        path.stroke()
        drawText(label, at: center, fontSize: 10, weight: .semibold, color: .secondaryLabelColor)
    }

    private func drawBumper(_ ctx: CGContext, rect: NSRect, label: String) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        NSColor.separatorColor.withAlphaComponent(0.2).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.4).setStroke()
        path.lineWidth = 1.0
        path.stroke()
        let center = NSPoint(x: rect.midX, y: rect.midY)
        drawText(label, at: center, fontSize: 9, weight: .medium, color: .tertiaryLabelColor)
    }

    private func drawStick(_ ctx: CGContext, center: NSPoint) {
        // Outer ring
        let outerR: CGFloat = 22
        let outerRect = NSRect(x: center.x - outerR, y: center.y - outerR, width: outerR * 2, height: outerR * 2)
        let outer = NSBezierPath(ovalIn: outerRect)
        NSColor.separatorColor.withAlphaComponent(0.15).setFill()
        outer.fill()
        NSColor.separatorColor.withAlphaComponent(0.4).setStroke()
        outer.lineWidth = 1.5
        outer.stroke()

        // Inner circle (thumbstick top)
        let innerR: CGFloat = 14
        let innerRect = NSRect(x: center.x - innerR, y: center.y - innerR, width: innerR * 2, height: innerR * 2)
        let inner = NSBezierPath(ovalIn: innerRect)
        NSColor.separatorColor.withAlphaComponent(0.1).setFill()
        inner.fill()
        NSColor.separatorColor.withAlphaComponent(0.3).setStroke()
        inner.lineWidth = 1.0
        inner.stroke()

        // Grip texture (small cross)
        let g: CGFloat = 5
        NSColor.separatorColor.withAlphaComponent(0.2).setStroke()
        ctx.setLineWidth(0.8)
        strokeLine(ctx, from: p(center.x - g, center.y), to: p(center.x + g, center.y))
        strokeLine(ctx, from: p(center.x, center.y - g), to: p(center.x, center.y + g))
    }

    private func drawDpad(_ ctx: CGContext, center: NSPoint) {
        let arm: CGFloat = 22
        let w: CGFloat = 14

        let path = NSBezierPath()
        // Cross shape
        path.move(to: p(center.x - w/2, center.y - arm))
        path.line(to: p(center.x + w/2, center.y - arm))
        path.line(to: p(center.x + w/2, center.y - w/2))
        path.line(to: p(center.x + arm, center.y - w/2))
        path.line(to: p(center.x + arm, center.y + w/2))
        path.line(to: p(center.x + w/2, center.y + w/2))
        path.line(to: p(center.x + w/2, center.y + arm))
        path.line(to: p(center.x - w/2, center.y + arm))
        path.line(to: p(center.x - w/2, center.y + w/2))
        path.line(to: p(center.x - arm, center.y + w/2))
        path.line(to: p(center.x - arm, center.y - w/2))
        path.line(to: p(center.x - w/2, center.y - w/2))
        path.close()

        NSColor.separatorColor.withAlphaComponent(0.25).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.4).setStroke()
        path.lineWidth = 1.2
        path.stroke()

        // Direction arrows
        let arrowColor = NSColor.tertiaryLabelColor
        drawText("▲", at: p(center.x, center.y - 13), fontSize: 7, weight: .regular, color: arrowColor)
        drawText("▼", at: p(center.x, center.y + 13), fontSize: 7, weight: .regular, color: arrowColor)
        drawText("◀", at: p(center.x - 13, center.y), fontSize: 7, weight: .regular, color: arrowColor)
        drawText("▶", at: p(center.x + 13, center.y), fontSize: 7, weight: .regular, color: arrowColor)
    }

    private func drawFaceButton(_ ctx: CGContext, center: NSPoint, label: String, color: NSColor) {
        let r: CGFloat = 13
        let rect = NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        let circle = NSBezierPath(ovalIn: rect)
        color.withAlphaComponent(0.15).setFill()
        circle.fill()
        color.withAlphaComponent(0.6).setStroke()
        circle.lineWidth = 1.8
        circle.stroke()
        drawText(label, at: center, fontSize: 11, weight: .bold, color: color.withAlphaComponent(0.8))
    }

    private func drawCenterButton(_ ctx: CGContext, center: NSPoint, label: String) {
        let w: CGFloat = 10, h: CGFloat = 8
        let rect = NSRect(x: center.x - w/2, y: center.y - h/2, width: w, height: h)
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        NSColor.separatorColor.withAlphaComponent(0.3).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 0.8
        path.stroke()
    }

    // MARK: - Leader Lines

    private func drawLeaderLines(_ ctx: CGContext) {
        let lineColor = NSColor.secondaryLabelColor.withAlphaComponent(0.35)

        for slot in slots {
            let btnPt = slot.buttonPoint
            let popupFrame = slot.popup.frame

            // Anchor point on popup edge
            let endPt: NSPoint
            if slot.popupSide == .left {
                endPt = NSPoint(x: popupFrame.maxX + 4, y: popupFrame.midY)
            } else {
                endPt = NSPoint(x: popupFrame.minX - 4, y: popupFrame.midY)
            }

            // Draw: horizontal from button → then straight/angled to popup
            let path = NSBezierPath()
            path.move(to: btnPt)

            // Elbow style: go horizontal first, then vertical
            let elbowX = slot.popupSide == .left
                ? max(endPt.x + 10, btnPt.x - (btnPt.x - endPt.x) * 0.3)
                : min(endPt.x - 10, btnPt.x + (endPt.x - btnPt.x) * 0.3)

            path.line(to: NSPoint(x: elbowX, y: btnPt.y))
            path.line(to: NSPoint(x: elbowX, y: endPt.y))
            path.line(to: endPt)

            lineColor.setStroke()
            path.lineWidth = 1.0
            path.stroke()

            // Small dot at button position
            let dotR: CGFloat = 3
            let dotRect = NSRect(x: btnPt.x - dotR, y: btnPt.y - dotR, width: dotR * 2, height: dotR * 2)
            let dot = NSBezierPath(ovalIn: dotRect)
            NSColor.secondaryLabelColor.withAlphaComponent(0.5).setFill()
            dot.fill()
        }
    }

    // MARK: - Helpers

    private func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }

    private func drawText(_ text: String, at center: NSPoint, fontSize: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: color,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attrs)
    }

    private func strokeLine(_ ctx: CGContext, from a: NSPoint, to b: NSPoint) {
        ctx.move(to: CGPoint(x: a.x, y: a.y))
        ctx.addLine(to: CGPoint(x: b.x, y: b.y))
        ctx.strokePath()
    }

    /// Get the configured action for a slot key.
    func actionForSlot(_ key: String) -> ButtonAction {
        guard let slot = slots.first(where: { $0.key == key }),
              let title = slot.popup.titleOfSelectedItem,
              let action = ButtonAction.allCases.first(where: { $0.rawValue == title }) else {
            return .none
        }
        return action
    }
}
