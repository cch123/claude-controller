import AppKit

/// Settings window with tabs: Button Mapping, Preset Prompts, Speech Recognition.
final class SettingsWindow: NSWindowController {
    private var mapping = ButtonMapping.load()
    private var speechSettings = SpeechSettings.load()

    // Button mapping tab
    private var gamepadView: GamepadConfigView!

    // Preset prompts tab
    private var presetFields: [NSTextField] = []
    private var ltFields: [String: NSTextField] = [:]
    private var rtFields: [String: NSTextField] = [:]

    // Speech tab
    private var enginePopup: NSPopUpButton!
    private var whisperModelPopup: NSPopUpButton!
    private var whisperStatusLabel: NSTextField!
    private var whisperProgressBar: NSProgressIndicator!
    private var whisperDownloadButton: NSButton!
    private var whisperInstallButton: NSButton!
    private var llmCheckbox: NSButton!
    private var llmURLField: NSTextField!
    private var llmKeyField: NSSecureTextField!
    private var llmModelField: NSTextField!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 830, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Gamepad Settings"
        window.center()
        window.minSize = NSSize(width: 700, height: 500)
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let tabView = NSTabView(frame: contentView.bounds)
        tabView.autoresizingMask = [.width, .height]

        // Tab 1: Button Mapping
        let tab1 = NSTabViewItem(identifier: "buttons")
        tab1.label = "Button Mapping"
        tab1.view = buildButtonMappingTab()
        tabView.addTabViewItem(tab1)

        // Tab 2: Preset Prompts
        let tab2 = NSTabViewItem(identifier: "prompts")
        tab2.label = "Preset Prompts"
        tab2.view = buildPromptsTab()
        tabView.addTabViewItem(tab2)

        // Tab 3: Speech Recognition
        let tab3 = NSTabViewItem(identifier: "speech")
        tab3.label = "Speech Recognition"
        tab3.view = buildSpeechTab()
        tabView.addTabViewItem(tab3)

        contentView.addSubview(tabView)

        // Save / Reset buttons at bottom
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.frame = NSRect(x: contentView.bounds.width - 100, y: 10, width: 80, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(saveButton)

        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetDefaults))
        resetButton.frame = NSRect(x: contentView.bounds.width - 260, y: 10, width: 145, height: 32)
        resetButton.bezelStyle = .rounded
        resetButton.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(resetButton)
    }

    // MARK: - Tab 1: Button Mapping

    private func buildButtonMappingTab() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 50, width: 820, height: 530))
        gamepadView = GamepadConfigView(mapping: mapping)
        gamepadView.frame = NSRect(x: 0, y: 0, width: 820, height: 580)
        container.addSubview(gamepadView)
        return container
    }

    // MARK: - Tab 2: Preset Prompts

    private func buildPromptsTab() -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 50, width: 820, height: 530))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let docH: CGFloat = 800
        let doc = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: docH))
        scroll.documentView = doc

        var y = docH - 30

        // Preset Prompts
        let presetHeader = makeLabel("Preset Prompts (预设提示词)", fontSize: 15, bold: true)
        presetHeader.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        doc.addSubview(presetHeader)
        let hint = makeLabel("Start → D-pad cycle, A to send", fontSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 400, y: y + 2, width: 300, height: 16)
        doc.addSubview(hint)
        y -= 10

        presetFields = []
        for (i, prompt) in mapping.presetPrompts.enumerated() {
            y -= 30
            let num = makeLabel("\(i + 1).")
            num.textColor = .secondaryLabelColor
            num.frame = NSRect(x: 20, y: y, width: 24, height: 22)
            doc.addSubview(num)
            let field = NSTextField(string: prompt)
            field.frame = NSRect(x: 48, y: y, width: 730, height: 22)
            field.font = NSFont.systemFont(ofSize: 13)
            doc.addSubview(field)
            presetFields.append(field)
        }

        y -= 40
        addSeparator(to: doc, y: y)
        y -= 25

        // LT Quick Prompts
        let ltHeader = makeLabel("LT / L2 + Button (快捷提示词)", fontSize: 15, bold: true)
        ltHeader.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        doc.addSubview(ltHeader)

        ltFields = [:]
        let ltData: [(String, String, String)] = [
            ("A / ✕", "a", mapping.ltPrompts.a),
            ("B / ○", "b", mapping.ltPrompts.b),
            ("X / □", "x", mapping.ltPrompts.x),
            ("Y / △", "y", mapping.ltPrompts.y),
        ]
        for (label, key, value) in ltData {
            y -= 30
            let lbl = makeLabel("  \(label):")
            lbl.textColor = .secondaryLabelColor
            lbl.frame = NSRect(x: 20, y: y, width: 65, height: 22)
            doc.addSubview(lbl)
            let field = NSTextField(string: value)
            field.frame = NSRect(x: 90, y: y, width: 688, height: 22)
            field.font = NSFont.systemFont(ofSize: 13)
            doc.addSubview(field)
            ltFields[key] = field
        }

        y -= 40
        addSeparator(to: doc, y: y)
        y -= 25

        // RT Quick Prompts
        let rtHeader = makeLabel("RT / R2 + Button (快捷提示词)", fontSize: 15, bold: true)
        rtHeader.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        doc.addSubview(rtHeader)

        rtFields = [:]
        let rtData: [(String, String, String)] = [
            ("A / ✕", "a", mapping.rtPrompts.a),
            ("B / ○", "b", mapping.rtPrompts.b),
            ("X / □", "x", mapping.rtPrompts.x),
            ("Y / △", "y", mapping.rtPrompts.y),
        ]
        for (label, key, value) in rtData {
            y -= 30
            let lbl = makeLabel("  \(label):")
            lbl.textColor = .secondaryLabelColor
            lbl.frame = NSRect(x: 20, y: y, width: 65, height: 22)
            doc.addSubview(lbl)
            let field = NSTextField(string: value)
            field.frame = NSRect(x: 90, y: y, width: 688, height: 22)
            field.font = NSFont.systemFont(ofSize: 13)
            doc.addSubview(field)
            rtFields[key] = field
        }

        return scroll
    }

    // MARK: - Tab 3: Speech Recognition

    private func buildSpeechTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 50, width: 820, height: 530))
        var y: CGFloat = 490

        // Engine selection
        let engineHeader = makeLabel("Speech Engine (语音识别引擎)", fontSize: 15, bold: true)
        engineHeader.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        view.addSubview(engineHeader)
        y -= 32

        let engineLabel = makeLabel("Engine:")
        engineLabel.frame = NSRect(x: 30, y: y, width: 60, height: 22)
        view.addSubview(engineLabel)
        enginePopup = NSPopUpButton(frame: NSRect(x: 100, y: y - 2, width: 350, height: 26), pullsDown: false)
        enginePopup.font = NSFont.systemFont(ofSize: 13)
        for t in SpeechEngineType.allCases { enginePopup.addItem(withTitle: t.rawValue) }
        enginePopup.selectItem(withTitle: speechSettings.engineType.rawValue)
        view.addSubview(enginePopup)
        y -= 35

        // Whisper settings
        addSeparator(to: view, y: y)
        y -= 25

        let whisperHeader = makeLabel("Whisper Settings (本地 whisper.cpp)", fontSize: 14, bold: true)
        whisperHeader.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        view.addSubview(whisperHeader)
        y -= 30

        // Model selector
        let modelLabel = makeLabel("Model:")
        modelLabel.frame = NSRect(x: 30, y: y, width: 50, height: 22)
        view.addSubview(modelLabel)

        whisperModelPopup = NSPopUpButton(frame: NSRect(x: 85, y: y - 2, width: 300, height: 26), pullsDown: false)
        whisperModelPopup.font = NSFont.systemFont(ofSize: 12)
        whisperModelPopup.target = self
        whisperModelPopup.action = #selector(modelSelectionChanged)
        // Models with sizes for user reference
        let models: [(String, String)] = [
            ("ggml-tiny.bin",      "~75 MB  - fastest, lowest quality"),
            ("ggml-base.bin",      "~142 MB - fast, good quality"),
            ("ggml-small.bin",     "~466 MB - balanced"),
            ("ggml-medium.bin",    "~1.5 GB - high quality"),
            ("ggml-large-v3.bin",  "~3.1 GB - best quality, slowest"),
        ]
        for (file, desc) in models {
            whisperModelPopup.addItem(withTitle: "\(file)  (\(desc))")
            whisperModelPopup.lastItem?.representedObject = file
        }
        // Select current model
        if let idx = models.firstIndex(where: { $0.0 == speechSettings.whisperModel }) {
            whisperModelPopup.selectItem(at: idx)
        }
        view.addSubview(whisperModelPopup)
        y -= 35

        // whisper-cpp binary status + install button
        whisperInstallButton = NSButton(title: "Install whisper-cpp (brew)", target: self, action: #selector(installWhisperCpp))
        whisperInstallButton.frame = NSRect(x: 30, y: y, width: 220, height: 26)
        whisperInstallButton.bezelStyle = .rounded
        view.addSubview(whisperInstallButton)
        y -= 32

        // Model download button + progress bar
        whisperDownloadButton = NSButton(title: "Download Model", target: self, action: #selector(downloadWhisperModel))
        whisperDownloadButton.frame = NSRect(x: 30, y: y, width: 140, height: 26)
        whisperDownloadButton.bezelStyle = .rounded
        view.addSubview(whisperDownloadButton)

        whisperProgressBar = NSProgressIndicator(frame: NSRect(x: 180, y: y + 4, width: 350, height: 18))
        whisperProgressBar.style = .bar
        whisperProgressBar.minValue = 0
        whisperProgressBar.maxValue = 1
        whisperProgressBar.doubleValue = 0
        whisperProgressBar.isHidden = true
        view.addSubview(whisperProgressBar)
        y -= 28

        // Status label
        whisperStatusLabel = makeLabel("")
        whisperStatusLabel.textColor = .secondaryLabelColor
        whisperStatusLabel.frame = NSRect(x: 30, y: y, width: 520, height: 18)
        view.addSubview(whisperStatusLabel)

        // Auto-check status
        updateWhisperStatus()

        // LLM Refinement
        y -= 35
        addSeparator(to: view, y: y)
        y -= 25

        let llmHeader = makeLabel("LLM Refinement (LLM 语音纠错)", fontSize: 14, bold: true)
        llmHeader.frame = NSRect(x: 20, y: y, width: 300, height: 20)
        view.addSubview(llmHeader)

        llmCheckbox = NSButton(checkboxWithTitle: "Enable (启用)", target: nil, action: nil)
        llmCheckbox.frame = NSRect(x: 320, y: y - 2, width: 120, height: 22)
        llmCheckbox.state = speechSettings.llmEnabled ? .on : .off
        view.addSubview(llmCheckbox)
        y -= 32

        let urlLabel = makeLabel("API URL:")
        urlLabel.frame = NSRect(x: 30, y: y, width: 65, height: 22)
        view.addSubview(urlLabel)
        llmURLField = NSTextField(string: speechSettings.llmAPIURL)
        llmURLField.frame = NSRect(x: 100, y: y, width: 450, height: 22)
        llmURLField.font = NSFont.systemFont(ofSize: 13)
        llmURLField.placeholderString = "http://localhost:11434/v1 (Ollama)"
        view.addSubview(llmURLField)
        y -= 28

        let keyLabel = makeLabel("API Key:")
        keyLabel.frame = NSRect(x: 30, y: y, width: 65, height: 22)
        view.addSubview(keyLabel)
        llmKeyField = NSSecureTextField(string: speechSettings.llmAPIKey)
        llmKeyField.frame = NSRect(x: 100, y: y, width: 450, height: 22)
        llmKeyField.font = NSFont.systemFont(ofSize: 13)
        llmKeyField.placeholderString = "Leave empty for Ollama"
        view.addSubview(llmKeyField)
        y -= 28

        let mdlLabel = makeLabel("Model:")
        mdlLabel.frame = NSRect(x: 30, y: y, width: 65, height: 22)
        view.addSubview(mdlLabel)
        llmModelField = NSTextField(string: speechSettings.llmModel)
        llmModelField.frame = NSRect(x: 100, y: y, width: 200, height: 22)
        llmModelField.font = NSFont.systemFont(ofSize: 13)
        llmModelField.placeholderString = "qwen2.5:7b"
        view.addSubview(llmModelField)

        let llmHint = makeLabel("Ollama / LM Studio / OpenAI compatible", fontSize: 11)
        llmHint.textColor = .tertiaryLabelColor
        llmHint.frame = NSRect(x: 310, y: y + 2, width: 280, height: 16)
        view.addSubview(llmHint)

        return view
    }

    // MARK: - Actions

    private var selectedModelName: String {
        whisperModelPopup.selectedItem?.representedObject as? String ?? "ggml-base.bin"
    }

    @objc private func modelSelectionChanged() {
        updateWhisperStatus()
    }

    private func updateWhisperStatus() {
        let whisper = WhisperEngine.shared
        whisper.modelName = selectedModelName

        var parts: [String] = []
        if whisper.hasBinary {
            parts.append("✅ whisper-cpp installed")
            whisperInstallButton.isEnabled = false
            whisperInstallButton.title = "✅ whisper-cpp installed"
        } else {
            parts.append("❌ whisper-cpp not found")
            whisperInstallButton.isEnabled = true
            whisperInstallButton.title = "Install whisper-cpp (brew)"
        }
        if whisper.hasModel {
            parts.append("✅ model ready")
            whisperDownloadButton.isEnabled = false
            whisperDownloadButton.title = "✅ Model ready"
        } else {
            parts.append("⬇️ model not downloaded")
            whisperDownloadButton.isEnabled = true
            whisperDownloadButton.title = "Download Model"
        }
        whisperStatusLabel.stringValue = parts.joined(separator: "  |  ")
        whisperStatusLabel.textColor = (whisper.hasBinary && whisper.hasModel) ? .systemGreen : .secondaryLabelColor
    }

    @objc private func installWhisperCpp() {
        whisperInstallButton.isEnabled = false
        whisperInstallButton.title = "Installing..."
        whisperStatusLabel.stringValue = "Installing whisper-cpp via Homebrew..."
        whisperStatusLabel.textColor = .secondaryLabelColor

        WhisperEngine.shared.installBinary { [weak self] ok, msg in
            self?.whisperStatusLabel.stringValue = ok ? "✅ \(msg)" : "❌ \(msg)"
            self?.whisperStatusLabel.textColor = ok ? .systemGreen : .systemRed
            self?.updateWhisperStatus()
        }
    }

    @objc private func downloadWhisperModel() {
        let whisper = WhisperEngine.shared
        whisper.modelName = selectedModelName

        whisperDownloadButton.isEnabled = false
        whisperDownloadButton.title = "Downloading..."
        whisperProgressBar.isHidden = false
        whisperProgressBar.doubleValue = 0
        whisperStatusLabel.stringValue = "Downloading \(whisper.modelName)..."
        whisperStatusLabel.textColor = .secondaryLabelColor

        whisper.downloadModel(
            onProgress: { [weak self] progress in
                self?.whisperProgressBar.doubleValue = progress
                let pct = Int(progress * 100)
                self?.whisperStatusLabel.stringValue = "Downloading... \(pct)%"
            },
            onComplete: { [weak self] ok, msg in
                self?.whisperProgressBar.isHidden = true
                self?.whisperStatusLabel.stringValue = ok ? "✅ \(msg)" : "❌ \(msg)"
                self?.whisperStatusLabel.textColor = ok ? .systemGreen : .systemRed
                self?.updateWhisperStatus()
            }
        )
    }

    @objc private func saveSettings() {
        // Button actions from gamepad view
        mapping.buttonActions = ButtonMapping.ButtonActions(
            a: gamepadView.actionForSlot("a"),
            b: gamepadView.actionForSlot("b"),
            x: gamepadView.actionForSlot("x"),
            y: gamepadView.actionForSlot("y"),
            lb: gamepadView.actionForSlot("lb"),
            rb: gamepadView.actionForSlot("rb"),
            start: gamepadView.actionForSlot("start"),
            select: gamepadView.actionForSlot("select"),
            stickClick: gamepadView.actionForSlot("stickL"),
            dpadUp: gamepadView.actionForSlot("dpadUp"),
            dpadDown: gamepadView.actionForSlot("dpadDown"),
            dpadLeft: gamepadView.actionForSlot("dpadLeft"),
            dpadRight: gamepadView.actionForSlot("dpadRight")
        )

        // Preset prompts
        mapping.presetPrompts = presetFields.map { $0.stringValue }

        // Quick prompts
        mapping.ltPrompts = ButtonMapping.QuickPrompts(
            a: ltFields["a"]!.stringValue,
            b: ltFields["b"]!.stringValue,
            x: ltFields["x"]!.stringValue,
            y: ltFields["y"]!.stringValue
        )
        mapping.rtPrompts = ButtonMapping.QuickPrompts(
            a: rtFields["a"]!.stringValue,
            b: rtFields["b"]!.stringValue,
            x: rtFields["x"]!.stringValue,
            y: rtFields["y"]!.stringValue
        )
        mapping.save()

        // Speech settings
        if let title = enginePopup.titleOfSelectedItem,
           let engine = SpeechEngineType.allCases.first(where: { $0.rawValue == title }) {
            speechSettings.engineType = engine
        }
        speechSettings.whisperModel = selectedModelName
        speechSettings.llmEnabled = llmCheckbox.state == .on
        speechSettings.llmAPIURL = llmURLField.stringValue
        speechSettings.llmAPIKey = llmKeyField.stringValue
        speechSettings.llmModel = llmModelField.stringValue
        speechSettings.save()

        GamepadManager.shared.reloadMapping()
        GamepadManager.shared.reloadSpeechSettings()
        window?.close()
    }

    @objc private func resetDefaults() {
        mapping = .default
        speechSettings = .default
        guard let contentView = window?.contentView else { return }
        contentView.subviews.forEach { $0.removeFromSuperview() }
        presetFields.removeAll()
        ltFields.removeAll()
        rtFields.removeAll()
        setupUI()
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String, fontSize: CGFloat = 13, bold: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
        return label
    }

    private func addSeparator(to view: NSView, y: CGFloat) {
        let sep = NSBox()
        sep.boxType = .separator
        sep.frame = NSRect(x: 20, y: y, width: 760, height: 1)
        view.addSubview(sep)
    }
}
