import AppKit

/// A floating HUD panel that shows feedback (button presses, voice status, transcription).
/// Non-activating so it doesn't steal focus from the terminal.
final class OverlayPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let waveformView = WaveformView()
    private let effectView: NSVisualEffectView
    private var hideTimer: Timer?
    private var widthConstraint: NSLayoutConstraint!

    static let shared = OverlayPanel()

    private init() {
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 28
        effectView.layer?.masksToBounds = true
        self.effectView = effectView

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 56),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.hidesOnDeactivate = false

        setupUI()
    }

    private func setupUI() {
        guard let contentView = self.contentView else { return }
        contentView.addSubview(effectView)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: contentView.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        // Waveform (hidden by default)
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        waveformView.isHidden = true
        effectView.addSubview(waveformView)

        // Label
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        effectView.addSubview(label)

        widthConstraint = effectView.widthAnchor.constraint(equalToConstant: 280)

        NSLayoutConstraint.activate([
            effectView.heightAnchor.constraint(equalToConstant: 56),
            widthConstraint,

            waveformView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
            waveformView.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            waveformView.widthAnchor.constraint(equalToConstant: 40),
            waveformView.heightAnchor.constraint(equalToConstant: 30),

            label.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -20),
            label.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
        ])
    }

    /// Show a brief message (auto-hides after duration).
    func showMessage(_ text: String, duration: TimeInterval = 2.0) {
        DispatchQueue.main.async { [self] in
            hideTimer?.invalidate()
            waveformView.isHidden = true
            label.isHidden = false
            label.stringValue = text

            // Adjust width based on text
            let textWidth = (text as NSString).size(withAttributes: [.font: label.font!]).width
            let newWidth = min(max(textWidth + 60, 160), 560)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                widthConstraint.animator().constant = newWidth
            }

            positionOnScreen()
            orderFrontRegardless()
            alphaValue = 1.0

            hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.fadeOut()
            }
        }
    }

    /// Show voice listening state with waveform.
    func showListening() {
        DispatchQueue.main.async { [self] in
            hideTimer?.invalidate()
            waveformView.isHidden = false
            label.isHidden = false
            label.stringValue = "Listening..."

            // Offset label when waveform is visible
            label.frame.origin.x = 64

            widthConstraint.constant = 280
            positionOnScreen()
            orderFrontRegardless()
            alphaValue = 1.0
        }
    }

    /// Update the waveform audio level (0.0 - 1.0).
    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async {
            self.waveformView.audioLevel = level
        }
    }

    /// Show transcribing state.
    func showTranscribing() {
        showMessage("Transcribing...", duration: 30)
    }

    /// Show transcription result.
    func showTranscription(_ text: String) {
        showMessage(text, duration: 4.0)
    }

    func fadeOut() {
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                self.animator().alphaValue = 0
            }) {
                self.orderOut(nil)
                self.alphaValue = 1.0
            }
        }
    }

    private func positionOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.minY + 80
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
    private let barWeights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let barWidth: CGFloat = 4
        let gap: CGFloat = 3
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
        let startX = (bounds.width - totalWidth) / 2

        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)

        for i in 0..<barCount {
            let weight = barWeights[i]
            let level = CGFloat(audioLevel) * weight + CGFloat.random(in: 0...0.05)
            let height = max(4, bounds.height * min(level, 1.0))
            let x = startX + CGFloat(i) * (barWidth + gap)
            let y = (bounds.height - height) / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            path.fill()
        }
    }
}
