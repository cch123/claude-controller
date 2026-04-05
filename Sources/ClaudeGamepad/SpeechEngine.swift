import Speech
import AVFoundation

/// Handles voice recording and speech recognition using Apple's SFSpeechRecognizer.
final class SpeechEngine {
    static let shared = SpeechEngine()

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Try Chinese first, fallback to English
    private let recognizers: [SFSpeechRecognizer?] = [
        SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans")),
        SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
    ]

    private var isRecording = false
    private var timeoutTimer: Timer?
    private let timeoutSeconds: TimeInterval = 15

    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    private init() {}

    /// Request speech recognition authorization.
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    /// Start recording and recognizing speech.
    func startListening() {
        // Prevent double start
        guard !isRecording else { return }

        // Request authorization on first use if not yet determined
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    if status == .authorized {
                        self?.startListening()
                    } else {
                        self?.onError?("Speech recognition not authorized. Check System Settings → Privacy.")
                    }
                }
            }
            return
        }
        guard authStatus == .authorized else {
            onError?("Speech recognition not authorized (status: \(authStatus.rawValue)). Check System Settings → Privacy.")
            return
        }

        // Find an available recognizer
        guard let recognizer = recognizers.compactMap({ $0 }).first(where: { $0.isAvailable }) else {
            onError?("No speech recognizer available")
            return
        }

        // Clean up any previous state
        cleanupAudio()

        // Create fresh audio engine each time to avoid state issues
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13, *) {
            request.addsPunctuation = true
        }
        self.recognitionRequest = request

        do {
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            // Validate format
            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                onError?("Invalid audio format. Check microphone connection.")
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                request.append(buffer)
                self?.computeAudioLevel(buffer: buffer)
            }

            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            cleanupAudio()
            onError?("Failed to start audio: \(error.localizedDescription)")
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    DispatchQueue.main.async {
                        self.finishWithText(text)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.onPartialResult?(text)
                        self.resetTimeout()
                    }
                }
            }

            if let error {
                let nsError = error as NSError
                // Ignore cancellation errors (code 216 = user cancelled, code 1110 = no speech detected)
                if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 1110) {
                    if nsError.code == 1110 {
                        DispatchQueue.main.async {
                            self.onError?("No speech detected. Try again.")
                            self.cleanupAudio()
                        }
                    }
                    return
                }
                DispatchQueue.main.async {
                    if self.isRecording {
                        self.onError?("Recognition error: \(error.localizedDescription)")
                        self.cleanupAudio()
                    }
                }
            }
        }

        // Start timeout
        resetTimeout()
    }

    /// Stop recording.
    func stopListening() {
        cleanupAudio()
    }

    private func cleanupAudio() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil

        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        audioEngine = nil
        isRecording = false
    }

    private func finishWithText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanupAudio()
        if trimmed.isEmpty {
            onError?("Didn't catch that. Try again.")
        } else {
            onFinalResult?(trimmed)
        }
    }

    private func resetTimeout() {
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeoutSeconds, repeats: false) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.recognitionRequest?.endAudio()
        }
    }

    private func computeAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        var sum: Float = 0
        for i in 0..<frameCount {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrt(sum / Float(frameCount))
        let level = min(rms * 5, 1.0)
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(level)
        }
    }
}
