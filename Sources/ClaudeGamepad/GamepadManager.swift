import GameController
import AppKit

/// Manages gamepad input using Apple's GameController framework.
/// Maps controller buttons to Claude Code terminal actions.
final class GamepadManager {
    static let shared = GamepadManager()

    private(set) var controller: GCController?
    private var mapping = ButtonMapping.load()
    private var presetIndex = 0
    private var isInPresetMenu = false
    private var isVoiceActive = false
    private var lastPartialText = ""

    var onControllerConnected: ((String) -> Void)?
    var onControllerDisconnected: (() -> Void)?

    private let keys = KeySimulator.shared
    private let overlay = OverlayPanel.shared
    private let systemSpeech = SpeechEngine.shared
    private let whisperSpeech = WhisperEngine.shared
    private let llmRefiner = LLMRefiner.shared
    private(set) var speechSettings = SpeechSettings.load()

    private init() {
        setupSpeechCallbacks()
    }

    /// Start listening for gamepad connections.
    func start() {
        // Receive gamepad input even when app is not focused (essential for menu bar app)
        GCController.shouldMonitorBackgroundEvents = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerConnected(_:)),
            name: .GCControllerDidConnect, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerDisconnected(_:)),
            name: .GCControllerDidDisconnect, object: nil
        )

        GCController.startWirelessControllerDiscovery {}

        // Check if already connected
        if let existing = GCController.controllers().first {
            configureController(existing)
        }
    }

    @objc private func controllerConnected(_ notification: Notification) {
        guard let gc = notification.object as? GCController else { return }
        configureController(gc)
    }

    @objc private func controllerDisconnected(_ notification: Notification) {
        controller = nil
        onControllerDisconnected?()
        overlay.showMessage("🎮 Controller disconnected")
    }

    private func configureController(_ gc: GCController) {
        controller = gc
        let name = gc.vendorName ?? "Unknown Controller"
        onControllerConnected?(name)
        overlay.showMessage("🎮 \(name) connected")

        guard let gamepad = gc.extendedGamepad else {
            overlay.showMessage("⚠️ Controller not supported (no extended gamepad)")
            return
        }

        // Face buttons
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onButtonA() }
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onButtonB() }
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onButtonX() }
        }
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onButtonY() }
        }

        // Shoulders
        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onLB() }
        }
        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onRB() }
        }

        // Menu buttons
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onStart() }
        }
        gamepad.buttonOptions?.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onSelect() }
        }

        // Stick clicks
        gamepad.leftThumbstickButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onStickClick() }
        }
        gamepad.rightThumbstickButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.onStickClick() }
        }

        // D-pad
        gamepad.dpad.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.onDpad(x: xValue, y: yValue)
        }

        // Left stick for scrolling
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.onLeftStick(x: xValue, y: yValue)
        }
    }

    // MARK: - Modifier State

    private var ltHeld: Bool {
        controller?.extendedGamepad?.leftTrigger.value ?? 0 > 0.3
    }

    private var rtHeld: Bool {
        controller?.extendedGamepad?.rightTrigger.value ?? 0 > 0.3
    }

    // MARK: - Button Actions

    /// Execute a configured button action.
    private func executeAction(_ action: ButtonAction) {
        switch action {
        case .enter:
            overlay.showMessage("⏎ Enter")
            keys.pressEnter()
        case .ctrlC:
            overlay.showMessage("⌃C Interrupt")
            keys.pressCtrlC()
        case .accept:
            overlay.showMessage("✅ Accept (y)")
            keys.typeAccept()
        case .reject:
            overlay.showMessage("❌ Reject (n)")
            keys.typeReject()
        case .tab:
            overlay.showMessage("⇥ Tab")
            keys.pressTab()
        case .escape:
            overlay.showMessage("⎋ Escape")
            keys.pressEscape()
        case .voiceInput:
            guard !isVoiceActive else { return }
            startVoiceInput()
        case .presetMenu:
            if isInPresetMenu {
                isInPresetMenu = false
                overlay.showMessage("❌ Menu closed")
            } else {
                isInPresetMenu = true
                presetIndex = 0
                showPresetOverlay()
            }
        case .clear:
            overlay.showMessage("🧹 /clear")
            keys.typeString("/clear")
        case .arrowUp:    keys.pressArrow(.up)
        case .arrowDown:  keys.pressArrow(.down)
        case .arrowLeft:  keys.pressArrow(.left)
        case .arrowRight: keys.pressArrow(.right)
        case .quit:
            overlay.showMessage("👋 Bye!")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NSApplication.shared.terminate(nil)
            }
        case .none:
            break
        }
    }

    /// Handle a face button with voice/preset/modifier checks.
    private func handleFaceButton(action: ButtonAction, ltPrompt: String, rtPrompt: String) {
        // Voice mode: A = confirm, B = cancel
        if isVoiceActive {
            if action == mapping.buttonActions.a || action == .enter {
                confirmVoice()
            } else if action == mapping.buttonActions.b || action == .ctrlC {
                cancelVoice()
            }
            return
        }
        // Preset menu mode
        if isInPresetMenu {
            if action == mapping.buttonActions.a || action == .enter {
                let prompt = mapping.presetPrompts[presetIndex]
                isInPresetMenu = false
                overlay.showMessage("📤 \(prompt)")
                keys.typeString(prompt)
            } else if action == mapping.buttonActions.b || action == .ctrlC {
                isInPresetMenu = false
                overlay.showMessage("❌ Menu cancelled")
            }
            return
        }
        // Modifier combos
        if ltHeld {
            overlay.showMessage("⚡ \(ltPrompt)")
            keys.typeString(ltPrompt)
        } else if rtHeld {
            overlay.showMessage("⚡ \(rtPrompt)")
            keys.typeString(rtPrompt)
        } else {
            executeAction(action)
        }
    }

    private func confirmVoice() {
        let text = lastPartialText
        stopCurrentSpeech()
        isVoiceActive = false
        lastPartialText = ""
        if !text.isEmpty {
            overlay.showMessage("🎤 ✅ \(text)", duration: 2)
            keys.pasteString(text)
        } else {
            overlay.showMessage("🎤 Nothing to paste")
        }
    }

    private func cancelVoice() {
        stopCurrentSpeech()
        isVoiceActive = false
        lastPartialText = ""
        overlay.showMessage("🎤 Cancelled")
    }

    private func onButtonA() {
        handleFaceButton(action: mapping.buttonActions.a,
                         ltPrompt: mapping.ltPrompts.a, rtPrompt: mapping.rtPrompts.a)
    }

    private func onButtonB() {
        handleFaceButton(action: mapping.buttonActions.b,
                         ltPrompt: mapping.ltPrompts.b, rtPrompt: mapping.rtPrompts.b)
    }

    private func onButtonX() {
        handleFaceButton(action: mapping.buttonActions.x,
                         ltPrompt: mapping.ltPrompts.x, rtPrompt: mapping.rtPrompts.x)
    }

    private func onButtonY() {
        handleFaceButton(action: mapping.buttonActions.y,
                         ltPrompt: mapping.ltPrompts.y, rtPrompt: mapping.rtPrompts.y)
    }

    private func onLB() {
        executeAction(mapping.buttonActions.lb)
    }

    private func onRB() {
        executeAction(mapping.buttonActions.rb)
    }

    private func onStart() {
        executeAction(mapping.buttonActions.start)
    }

    private func onSelect() {
        // LT+RT+Select = always quit (safety override)
        if ltHeld && rtHeld {
            executeAction(.quit)
            return
        }
        executeAction(mapping.buttonActions.select)
    }

    private func onStickClick() {
        executeAction(mapping.buttonActions.stickClick)
    }

    private func onDpad(x: Float, y: Float) {
        if isInPresetMenu {
            if y > 0.5 {
                presetIndex = (presetIndex - 1 + mapping.presetPrompts.count) % mapping.presetPrompts.count
                showPresetOverlay()
            } else if y < -0.5 {
                presetIndex = (presetIndex + 1) % mapping.presetPrompts.count
                showPresetOverlay()
            }
            return
        }

        if y > 0.5 { executeAction(mapping.buttonActions.dpadUp) }
        else if y < -0.5 { executeAction(mapping.buttonActions.dpadDown) }
        if x > 0.5 { executeAction(mapping.buttonActions.dpadRight) }
        else if x < -0.5 { executeAction(mapping.buttonActions.dpadLeft) }
    }

    private var lastScrollTime: TimeInterval = 0

    private func onLeftStick(x: Float, y: Float) {
        guard !isInPresetMenu else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastScrollTime > 0.12 else { return }

        if y > 0.4 {
            keys.pressArrow(.up)
            lastScrollTime = now
        } else if y < -0.4 {
            keys.pressArrow(.down)
            lastScrollTime = now
        }
    }

    // MARK: - Preset Menu

    private func showPresetOverlay() {
        let prompt = mapping.presetPrompts[presetIndex]
        let total = mapping.presetPrompts.count
        overlay.showMessage("📋 [\(presetIndex + 1)/\(total)] \(prompt)", duration: 10)
    }

    // MARK: - Voice Input

    private func startVoiceInput() {
        isVoiceActive = true
        overlay.showListening()

        if speechSettings.engineType == .whisperLocal {
            whisperSpeech.startListening()
        } else {
            systemSpeech.startListening()
        }
    }

    private func stopCurrentSpeech() {
        systemSpeech.stopListening()
        whisperSpeech.stopListening()
    }

    /// Called when we get a final recognition result — optionally refine with LLM.
    private func handleRecognitionResult(_ text: String) {
        if speechSettings.llmEnabled {
            overlay.showMessage("🎤 Refining...", duration: 15)
            llmRefiner.refine(text) { [weak self] refined in
                DispatchQueue.main.async {
                    self?.lastPartialText = refined
                    self?.overlay.showMessage("🎤 \(refined)  [A=确认 B=取消]", duration: 30)
                }
            }
        } else {
            lastPartialText = text
            overlay.showMessage("🎤 \(text)  [A=确认 B=取消]", duration: 30)
        }
    }

    private func setupSpeechCallbacks() {
        // System speech (SFSpeechRecognizer) - has partial results
        systemSpeech.onPartialResult = { [weak self] text in
            self?.lastPartialText = text
            self?.overlay.showMessage("🎤 \(text)  [A=确认 B=取消]", duration: 30)
        }

        systemSpeech.onFinalResult = { [weak self] text in
            DispatchQueue.main.async {
                self?.handleRecognitionResult(text)
            }
        }

        systemSpeech.onError = { [weak self] error in
            self?.isVoiceActive = false
            self?.overlay.showMessage("🎤 \(error)")
        }

        systemSpeech.onAudioLevel = { [weak self] level in
            self?.overlay.updateAudioLevel(level)
        }

        // Whisper engine - batch result (no partial)
        whisperSpeech.onStatusUpdate = { [weak self] status in
            self?.overlay.showMessage("🎤 \(status)", duration: 30)
        }

        whisperSpeech.onResult = { [weak self] text in
            DispatchQueue.main.async {
                self?.handleRecognitionResult(text)
            }
        }

        whisperSpeech.onError = { [weak self] error in
            self?.isVoiceActive = false
            self?.overlay.showMessage("🎤 \(error)")
        }

        whisperSpeech.onAudioLevel = { [weak self] level in
            self?.overlay.updateAudioLevel(level)
        }
    }

    /// Reload settings from disk.
    func reloadMapping() {
        mapping = ButtonMapping.load()
    }

    func reloadSpeechSettings() {
        speechSettings = SpeechSettings.load()
        // Apply LLM settings
        llmRefiner.isEnabled = speechSettings.llmEnabled
        llmRefiner.apiBaseURL = speechSettings.llmAPIURL
        llmRefiner.apiKey = speechSettings.llmAPIKey
        llmRefiner.model = speechSettings.llmModel
        // Apply Whisper settings
        whisperSpeech.modelName = speechSettings.whisperModel
    }
}
