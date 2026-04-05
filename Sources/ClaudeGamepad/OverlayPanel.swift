import AppKit

/// A floating HUD panel that shows feedback (button presses, voice status, transcription).
/// Non-activating so it doesn't steal focus from the terminal.
final class OverlayPanel: NSPanel {
    private enum PresentationKind {
        case standard
        case listening
        case transcribing
        case transcription
    }

    private let effectView: NSVisualEffectView
    private let accentBubble = NSView()
    private let iconView = NSImageView()
    private let waveformView = WaveformView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let promptSheetContainer = NSView()
    private var hideTimer: Timer?

    static let shared = OverlayPanel()

    private init() {
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 20
        effectView.layer?.masksToBounds = true
        self.effectView = effectView

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 94),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false

        setupUI()
    }

    private func setupUI() {
        guard let contentView else { return }
        effectView.frame = contentView.bounds
        effectView.autoresizingMask = [.width, .height]
        contentView.addSubview(effectView)

        accentBubble.wantsLayer = true
        accentBubble.layer?.cornerRadius = 14
        effectView.addSubview(accentBubble)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .white
        effectView.addSubview(iconView)

        waveformView.isHidden = true
        effectView.addSubview(waveformView)

        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.86)
        effectView.addSubview(titleLabel)

        bodyLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        bodyLabel.textColor = .white
        bodyLabel.maximumNumberOfLines = 3
        bodyLabel.lineBreakMode = .byTruncatingTail
        effectView.addSubview(bodyLabel)

        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.66)
        effectView.addSubview(hintLabel)

        promptSheetContainer.isHidden = true
        effectView.addSubview(promptSheetContainer)
    }

    /// Show a brief message (auto-hides after duration).
    func showMessage(_ text: String, duration: TimeInterval = 2.0) {
        let parsed = parseMessage(text)
        present(
            kind: parsed.kind,
            title: parsed.title,
            body: parsed.body,
            hint: parsed.hint,
            symbolName: parsed.symbolName,
            accentColor: parsed.accentColor,
            duration: duration
        )
    }

    /// Show voice listening state with waveform.
    func showListening() {
        present(
            kind: .listening,
            title: "Voice Input",
            body: "Listening for your prompt",
            hint: "Speak naturally. The recording stops after silence is detected.",
            symbolName: "waveform",
            accentColor: NSColor.systemRed,
            duration: 30
        )
    }

    /// Update the waveform audio level (0.0 - 1.0).
    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async {
            self.waveformView.audioLevel = level
        }
    }

    /// Show transcribing state.
    func showTranscribing() {
        present(
            kind: .transcribing,
            title: "Voice Input",
            body: "Transcribing speech...",
            hint: "This can take a moment for longer recordings or larger Whisper models.",
            symbolName: "text.badge.magnifyingglass",
            accentColor: NSColor.systemOrange,
            duration: 30
        )
    }

    /// Create a prompt card (rounded rect with text inside).
    private func makeCard(text: String, color: NSColor, font: NSFont, maxWidth: CGFloat) -> (view: NSView, size: NSSize) {
        let cardPadH: CGFloat = 12
        let cardPadV: CGFloat = 8
        let maxTextW = maxWidth - cardPadH * 2

        // Use NSTextField's own layout engine for accurate sizing
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = .white
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0

        // Measure single-line size
        label.sizeToFit()
        let singleW = label.frame.width
        let singleH = label.frame.height

        if singleW <= maxTextW {
            // Fits in one line
            label.frame = NSRect(x: cardPadH, y: cardPadV, width: singleW, height: singleH)
        } else {
            // Needs wrapping
            label.preferredMaxLayoutWidth = maxTextW
            label.frame.size.width = maxTextW
            label.sizeToFit()
            label.frame.origin = NSPoint(x: cardPadH, y: cardPadV)
        }

        let cardW = label.frame.width + cardPadH * 2
        let cardH = label.frame.height + cardPadV * 2

        let card = NSView(frame: NSRect(x: 0, y: 0, width: cardW, height: cardH))
        card.wantsLayer = true
        card.layer?.cornerRadius = 8
        card.layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = color.withAlphaComponent(0.2).cgColor
        card.addSubview(label)

        return (card, NSSize(width: cardW, height: cardH))
    }

    /// Add a diamond badge with centered letter + PS5 symbol.
    private func makeBadge(btn: String, ps: String, color: NSColor, badgeSize: CGFloat) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: badgeSize + 18, height: badgeSize))

        let badge = NSView(frame: NSRect(x: 0, y: 0, width: badgeSize, height: badgeSize))
        badge.wantsLayer = true
        badge.layer?.cornerRadius = badgeSize / 2
        badge.layer?.backgroundColor = color.withAlphaComponent(0.85).cgColor
        container.addSubview(badge)

        let letter = NSTextField(labelWithString: btn)
        letter.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        letter.textColor = .white
        letter.alignment = .center
        letter.sizeToFit()
        letter.frame = NSRect(
            x: (badgeSize - letter.frame.width) / 2,
            y: (badgeSize - letter.frame.height) / 2,
            width: letter.frame.width,
            height: letter.frame.height
        )
        container.addSubview(letter)

        let psLabel = NSTextField(labelWithString: ps)
        psLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        psLabel.textColor = NSColor.white.withAlphaComponent(0.35)
        psLabel.sizeToFit()
        psLabel.frame.origin = NSPoint(x: badgeSize + 3, y: (badgeSize - psLabel.frame.height) / 2)
        container.addSubview(psLabel)

        return container
    }

    /// Show a prompt cheat sheet for trigger combos (LT/RT + face buttons).
    /// Radial layout: diamond in center, prompts around it on cards.
    func showPromptSheet(label: String, prompts: [(button: String, prompt: String)]) {
        DispatchQueue.main.async { [self] in
            hideTimer?.invalidate()

            titleLabel.isHidden = true
            bodyLabel.isHidden = true
            hintLabel.isHidden = true
            waveformView.isHidden = true
            iconView.isHidden = true
            accentBubble.isHidden = true

            promptSheetContainer.subviews.forEach { $0.removeFromSuperview() }
            promptSheetContainer.isHidden = false

            let psLabels: [String: String] = ["A": "✕", "B": "○", "X": "□", "Y": "△"]
            let buttonColors: [String: NSColor] = [
                "A": .systemGreen, "B": .systemRed,
                "X": .systemBlue, "Y": .systemYellow,
            ]
            let promptsDict = Dictionary(uniqueKeysWithValues: prompts.map { ($0.button, $0.prompt) })
            let font = NSFont.systemFont(ofSize: 12, weight: .medium)

            let outerPad: CGFloat = 20
            let titleH: CGFloat = 22
            let titleGap: CGFloat = 8
            let badgeSize: CGFloat = 26
            let step: CGFloat = 30
            let cardGap: CGFloat = 10
            let sideCardMaxW: CGFloat = 180
            let tbCardMaxW: CGFloat = 240

            // Measure all 4 cards
            let cardY = makeCard(text: promptsDict["Y"] ?? "", color: buttonColors["Y"]!, font: font, maxWidth: tbCardMaxW)
            let cardA = makeCard(text: promptsDict["A"] ?? "", color: buttonColors["A"]!, font: font, maxWidth: tbCardMaxW)
            let cardX = makeCard(text: promptsDict["X"] ?? "", color: buttonColors["X"]!, font: font, maxWidth: sideCardMaxW)
            let cardB = makeCard(text: promptsDict["B"] ?? "", color: buttonColors["B"]!, font: font, maxWidth: sideCardMaxW)

            // Diamond area size
            let diamondW = step * 2 + badgeSize + 18  // +18 for PS5 labels
            let diamondH = step * 2 + badgeSize

            // Panel dimensions
            let centerColW = max(diamondW, cardY.size.width, cardA.size.width)
            let panelWidth = outerPad + cardX.size.width + cardGap + centerColW + cardGap + cardB.size.width + outerPad
            let sideRowH = max(diamondH, cardX.size.height, cardB.size.height)
            let panelHeight = outerPad + titleH + titleGap + cardY.size.height + cardGap + sideRowH + cardGap + cardA.size.height + outerPad

            // Center of diamond
            let cx = outerPad + cardX.size.width + cardGap + centerColW / 2
            let cyBase = outerPad + cardA.size.height + cardGap
            let cy = cyBase + sideRowH / 2

            // ── Title ──
            let titleField = NSTextField(labelWithString: "⚡ \(label) Quick Prompts")
            titleField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            titleField.textColor = NSColor.white.withAlphaComponent(0.55)
            titleField.frame = NSRect(x: outerPad, y: panelHeight - outerPad - titleH, width: panelWidth - outerPad * 2, height: titleH)
            promptSheetContainer.addSubview(titleField)

            // ── Diamond badges ──
            let badges: [(String, CGFloat, CGFloat)] = [
                ("Y", cx, cy + step),
                ("A", cx, cy - step),
                ("X", cx - step, cy),
                ("B", cx + step, cy),
            ]
            for (btn, bx, by) in badges {
                let color = buttonColors[btn]!
                let ps = psLabels[btn]!
                let badgeView = makeBadge(btn: btn, ps: ps, color: color, badgeSize: badgeSize)
                badgeView.frame.origin = NSPoint(x: bx - badgeSize / 2, y: by - badgeSize / 2)
                promptSheetContainer.addSubview(badgeView)
            }

            // ── Cards ──
            // Y card: centered above diamond
            cardY.view.frame.origin = NSPoint(
                x: cx - cardY.size.width / 2,
                y: cy + step + badgeSize / 2 + cardGap
            )
            promptSheetContainer.addSubview(cardY.view)

            // A card: centered below diamond
            cardA.view.frame.origin = NSPoint(
                x: cx - cardA.size.width / 2,
                y: cy - step - badgeSize / 2 - cardGap - cardA.size.height
            )
            promptSheetContainer.addSubview(cardA.view)

            // X card: to the left of diamond, vertically centered
            cardX.view.frame.origin = NSPoint(
                x: cx - step - badgeSize / 2 - cardGap - cardX.size.width,
                y: cy - cardX.size.height / 2
            )
            promptSheetContainer.addSubview(cardX.view)

            // B card: to the right of diamond, vertically centered
            cardB.view.frame.origin = NSPoint(
                x: cx + step + badgeSize / 2 + 18 + cardGap,
                y: cy - cardB.size.height / 2
            )
            promptSheetContainer.addSubview(cardB.view)

            promptSheetContainer.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
            setContentSize(NSSize(width: panelWidth, height: panelHeight))
            effectView.frame = NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight))

            positionOnScreen()
            orderFrontRegardless()
            alphaValue = 1
        }
    }

    /// Show command mode overlay with input sequence and available combos.
    func showCommandMode(inputs: [ComboInput], combos: [ComboEntry], style: ComboStyle) {
        DispatchQueue.main.async { [self] in
            hideTimer?.invalidate()

            titleLabel.isHidden = true
            bodyLabel.isHidden = true
            hintLabel.isHidden = true
            waveformView.isHidden = true
            iconView.isHidden = true
            accentBubble.isHidden = true

            promptSheetContainer.subviews.forEach { $0.removeFromSuperview() }
            promptSheetContainer.isHidden = false

            let font = NSFont.systemFont(ofSize: 12, weight: .medium)
            let panelWidth: CGFloat = 420
            let pad: CGFloat = 20
            let titleH: CGFloat = 22
            let inputAreaH: CGFloat = 50
            let comboRowH: CGFloat = 24
            let sectionGap: CGFloat = 12

            // Filter to combos that still match the current input prefix
            let matching: [ComboEntry]
            if inputs.isEmpty {
                matching = combos
            } else {
                matching = combos.filter { Array($0.inputs.prefix(inputs.count)) == inputs }
            }
            let maxRows = min(matching.count, 8)
            let listH = CGFloat(maxRows) * comboRowH
            let totalHeight = pad + titleH + sectionGap + inputAreaH + sectionGap + listH + pad

            // ── Title ──
            let styleName = style == .fighting ? "🥊 Command Mode — Fighting" : "🎮 Command Mode — Helldivers"
            let titleField = NSTextField(labelWithString: styleName)
            titleField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            titleField.textColor = NSColor.systemOrange
            titleField.frame = NSRect(x: pad, y: totalHeight - pad - titleH, width: panelWidth - pad * 2, height: titleH)
            promptSheetContainer.addSubview(titleField)

            // ── Input sequence display ──
            let inputY = totalHeight - pad - titleH - sectionGap - inputAreaH
            let inputBg = NSView(frame: NSRect(x: pad, y: inputY, width: panelWidth - pad * 2, height: inputAreaH))
            inputBg.wantsLayer = true
            inputBg.layer?.cornerRadius = 10
            inputBg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            promptSheetContainer.addSubview(inputBg)

            if inputs.isEmpty {
                let hint = NSTextField(labelWithString: style == .helldivers ? "输入方向键组合..." : "输入方向键 + 按键组合...")
                hint.font = NSFont.systemFont(ofSize: 16, weight: .medium)
                hint.textColor = NSColor.white.withAlphaComponent(0.3)
                hint.sizeToFit()
                hint.frame.origin = NSPoint(x: (panelWidth - hint.frame.width) / 2, y: inputY + (inputAreaH - hint.frame.height) / 2)
                promptSheetContainer.addSubview(hint)
            } else {
                let inputColors: [ComboInput: NSColor] = [
                    .up: .white, .down: .white, .left: .white, .right: .white,
                    .a: .systemGreen, .b: .systemRed, .x: .systemBlue, .y: .systemYellow,
                ]
                let symbolSize: CGFloat = 30
                let gap: CGFloat = 8
                let totalW = CGFloat(inputs.count) * symbolSize + CGFloat(inputs.count - 1) * gap
                var sx = (panelWidth - totalW) / 2

                for input in inputs {
                    let color = inputColors[input] ?? .white
                    let isDirection = [ComboInput.up, .down, .left, .right].contains(input)

                    let symbol = NSView(frame: NSRect(x: sx, y: inputY + (inputAreaH - symbolSize) / 2, width: symbolSize, height: symbolSize))
                    symbol.wantsLayer = true
                    symbol.layer?.cornerRadius = isDirection ? 6 : symbolSize / 2
                    symbol.layer?.backgroundColor = (isDirection ? NSColor.white.withAlphaComponent(0.15) : color.withAlphaComponent(0.85)).cgColor
                    promptSheetContainer.addSubview(symbol)

                    let label = NSTextField(labelWithString: input.rawValue)
                    label.font = NSFont.systemFont(ofSize: isDirection ? 16 : 13, weight: .bold)
                    label.textColor = .white
                    label.alignment = .center
                    label.sizeToFit()
                    label.frame = NSRect(
                        x: sx + (symbolSize - label.frame.width) / 2,
                        y: inputY + (inputAreaH - label.frame.height) / 2,
                        width: label.frame.width,
                        height: label.frame.height
                    )
                    promptSheetContainer.addSubview(label)

                    sx += symbolSize + gap
                }
            }

            // ── Combo list ──
            let listTop = inputY - sectionGap
            for (i, combo) in matching.prefix(maxRows).enumerated() {
                let rowY = listTop - CGFloat(i + 1) * comboRowH

                // Combo name
                let nameField = NSTextField(labelWithString: combo.name)
                nameField.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
                nameField.textColor = NSColor.systemOrange.withAlphaComponent(0.7)
                nameField.frame = NSRect(x: pad, y: rowY, width: 80, height: comboRowH)
                promptSheetContainer.addSubview(nameField)

                // Input sequence
                let seqField = NSTextField(labelWithString: combo.inputDisplay)
                seqField.font = font
                seqField.textColor = NSColor.white.withAlphaComponent(0.5)
                seqField.frame = NSRect(x: pad + 80, y: rowY, width: 120, height: comboRowH)
                promptSheetContainer.addSubview(seqField)

                // Prompt
                let promptField = NSTextField(labelWithString: combo.prompt)
                promptField.font = font
                promptField.textColor = NSColor.white.withAlphaComponent(0.8)
                promptField.lineBreakMode = .byTruncatingTail
                promptField.frame = NSRect(x: pad + 200, y: rowY, width: panelWidth - pad - 200 - pad, height: comboRowH)
                promptSheetContainer.addSubview(promptField)
            }

            promptSheetContainer.frame = NSRect(x: 0, y: 0, width: panelWidth, height: totalHeight)
            setContentSize(NSSize(width: panelWidth, height: totalHeight))
            effectView.frame = NSRect(origin: .zero, size: NSSize(width: panelWidth, height: totalHeight))

            positionOnScreen()
            orderFrontRegardless()
            alphaValue = 1
        }
    }

    /// Show transcription result.
    func showTranscription(_ text: String) {
        present(
            kind: .transcription,
            title: "Transcription Ready",
            body: text,
            hint: "Press A to paste, or B to cancel.",
            symbolName: "quote.bubble",
            accentColor: NSColor.controlAccentColor,
            duration: 6.0
        )
    }

    func fadeOut() {
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.24
                self.animator().alphaValue = 0
            }) {
                self.orderOut(nil)
                self.alphaValue = 1.0
            }
        }
    }

    private func present(
        kind: PresentationKind,
        title: String,
        body: String,
        hint: String?,
        symbolName: String,
        accentColor: NSColor,
        duration: TimeInterval
    ) {
        DispatchQueue.main.async { [self] in
            hideTimer?.invalidate()

            // Restore standard elements if prompt sheet was showing
            promptSheetContainer.isHidden = true
            promptSheetContainer.subviews.forEach { $0.removeFromSuperview() }
            titleLabel.isHidden = false
            bodyLabel.isHidden = false
            accentBubble.isHidden = false

            titleLabel.stringValue = title
            bodyLabel.stringValue = body
            hintLabel.stringValue = hint ?? ""
            hintLabel.isHidden = hint == nil

            accentBubble.layer?.backgroundColor = accentColor.withAlphaComponent(0.28).cgColor
            accentBubble.layer?.borderWidth = 1
            accentBubble.layer?.borderColor = accentColor.withAlphaComponent(0.25).cgColor

            waveformView.isHidden = kind != .listening
            if kind == .listening {
                iconView.isHidden = true
            } else {
                iconView.isHidden = false
                let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
                iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            }

            layoutPanel(for: kind, body: body, hint: hint)
            positionOnScreen()
            orderFrontRegardless()
            alphaValue = 1

            hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.fadeOut()
            }
        }
    }

    private func layoutPanel(for kind: PresentationKind, body: String, hint: String?) {
        let maxWidth: CGFloat = kind == .transcription ? 540 : 440
        let minWidth: CGFloat = 250
        let bubbleSize: CGFloat = 44
        let sideInset: CGFloat = 16
        let textLeading: CGFloat = sideInset + bubbleSize + 14
        let textWidthGuess = maxWidth - textLeading - sideInset

        let bodySize = measuredSize(for: body, font: bodyLabel.font!, width: textWidthGuess, maxLines: kind == .transcription ? 3 : 2)
        let hintSize = measuredSize(for: hint ?? "", font: hintLabel.font!, width: textWidthGuess, maxLines: 2)
        let titleHeight: CGFloat = 16
        let bottomPadding: CGFloat = hint == nil ? 16 : 14
        let contentHeight = 14 + titleHeight + 6 + bodySize.height + (hint == nil ? 0 : 8 + hintSize.height) + bottomPadding
        let preferredWidth = min(max(minWidth, bodySize.width + textLeading + sideInset), maxWidth)

        setContentSize(NSSize(width: preferredWidth, height: contentHeight))
        effectView.frame = NSRect(origin: .zero, size: NSSize(width: preferredWidth, height: contentHeight))

        accentBubble.frame = NSRect(x: sideInset, y: 16, width: bubbleSize, height: bubbleSize)
        iconView.frame = NSRect(x: sideInset + 11, y: 27, width: 22, height: 22)
        waveformView.frame = NSRect(x: sideInset + 7, y: 23, width: 30, height: 30)

        titleLabel.frame = NSRect(x: textLeading, y: 16, width: preferredWidth - textLeading - sideInset, height: titleHeight)
        bodyLabel.frame = NSRect(x: textLeading, y: titleLabel.frame.maxY + 6, width: preferredWidth - textLeading - sideInset, height: bodySize.height)
        hintLabel.frame = NSRect(x: textLeading, y: bodyLabel.frame.maxY + 8, width: preferredWidth - textLeading - sideInset, height: hintSize.height)
    }

    private func measuredSize(for text: String, font: NSFont, width: CGFloat, maxLines: Int) -> NSSize {
        guard !text.isEmpty else { return NSSize(width: 0, height: 0) }
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let lineHeight = font.boundingRectForFont.height
        let cappedHeight = min(ceil(rect.height), ceil(lineHeight) * CGFloat(maxLines))
        let cappedWidth = min(width, ceil(rect.width))
        return NSSize(width: cappedWidth, height: max(lineHeight, cappedHeight))
    }

    private func parseMessage(_ text: String) -> (kind: PresentationKind, title: String, body: String, hint: String?, symbolName: String, accentColor: NSColor) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var hint: String?
        var kind: PresentationKind = .standard

        if let hintStart = trimmed.range(of: "["),
           trimmed.hasSuffix("]") {
            hint = String(trimmed[hintStart.lowerBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            trimmed = String(trimmed[..<hintStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            kind = .transcription
        }

        let mappings: [(prefix: String, title: String, symbol: String, color: NSColor)] = [
            ("🎮", "Controller", "gamecontroller", .systemBlue),
            ("⚠️", "Attention", "exclamationmark.triangle.fill", .systemOrange),
            ("⏎", "Action Sent", "return", .controlAccentColor),
            ("⌃C", "Interrupt", "hand.raised.fill", .systemRed),
            ("✅", "Action Sent", "checkmark.circle.fill", .systemGreen),
            ("❌", "Action Cancelled", "xmark.circle.fill", .systemRed),
            ("⇥", "Action Sent", "arrow.right.to.line.compact", .controlAccentColor),
            ("⎋", "Action Sent", "escape", .controlAccentColor),
            ("🧹", "Terminal Command", "sparkles", .systemTeal),
            ("👋", "Application", "power", .systemPink),
            ("📤", "Prompt Sent", "paperplane.fill", .systemBlue),
            ("⚡", "Quick Prompt", "bolt.fill", .systemYellow),
            ("🎤", kind == .transcription ? "Transcription Ready" : "Voice Input", "mic.fill", .systemRed),
            ("📋", "Preset Browser", "list.bullet.rectangle", .controlAccentColor),
        ]

        for mapping in mappings where trimmed.hasPrefix(mapping.prefix) {
            let body = trimmed.dropFirst(mapping.prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                kind,
                mapping.title,
                body.isEmpty ? trimmed : body,
                normalizedHint(hint),
                mapping.symbol,
                mapping.color
            )
        }

        return (
            kind,
            kind == .transcription ? "Transcription Ready" : "Claude Gamepad",
            trimmed,
            normalizedHint(hint),
            kind == .transcription ? "quote.bubble.fill" : "gamecontroller.fill",
            kind == .transcription ? .controlAccentColor : .systemBlue
        )
    }

    private func normalizedHint(_ hint: String?) -> String? {
        guard let hint, !hint.isEmpty else { return nil }
        return hint
            .replacingOccurrences(of: "A=确认", with: "A 确认")
            .replacingOccurrences(of: "B=取消", with: "B 取消")
    }

    private func positionOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.minY + 84
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - WaveformView

/// Simple animated waveform bars driven by audio level.
final class WaveformView: NSView {
    var audioLevel: Float = 0 {
        didSet { needsDisplay = true }
    }

    private let barCount = 5
    private let barWeights: [CGFloat] = [0.45, 0.75, 1.0, 0.72, 0.5]

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let barWidth: CGFloat = 4
        let gap: CGFloat = 3
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
        let startX = (bounds.width - totalWidth) / 2
        context.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)

        for index in 0..<barCount {
            let weight = barWeights[index]
            let level = CGFloat(audioLevel) * weight + CGFloat.random(in: 0...0.06)
            let height = max(4, bounds.height * min(level, 1.0))
            let x = startX + CGFloat(index) * (barWidth + gap)
            let y = (bounds.height - height) / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            path.fill()
        }
    }
}
