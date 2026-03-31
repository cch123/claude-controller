import AVFoundation
import Foundation

/// Local Whisper speech recognition via whisper.cpp CLI.
/// Auto-downloads whisper-cpp binary and model on first use.
final class WhisperEngine {
    static let shared = WhisperEngine()

    // Configurable
    var modelName: String = "ggml-base.bin"

    // Recording parameters (matching Python version)
    private let silenceThreshold: Float = 0.01
    private let silenceDuration: TimeInterval = 1.5
    private let maxRecordSeconds: TimeInterval = 30

    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private var isRecording = false
    private var recordingSampleRate: Double = 48000

    var onAudioLevel: ((Float) -> Void)?
    var onStatusUpdate: ((String) -> Void)?
    var onResult: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private init() {}

    // MARK: - Paths

    private static var dataDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ClaudeGamepad/whisper")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var modelPath: URL { WhisperEngine.dataDir.appendingPathComponent(modelName) }

    private var binaryPath: String {
        // whisper-cpp brew installs as "whisper-cli"
        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/opt/homebrew/bin/whisper",
            "/usr/local/bin/whisper-cli",
            "/usr/local/bin/whisper-cpp",
            "/usr/local/bin/whisper",
            WhisperEngine.dataDir.appendingPathComponent("whisper-cli").path,
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
    }

    // MARK: - Setup Check

    var isSetUp: Bool {
        FileManager.default.isExecutableFile(atPath: binaryPath) && FileManager.default.fileExists(atPath: modelPath.path)
    }

    var hasBinary: Bool {
        FileManager.default.isExecutableFile(atPath: binaryPath)
    }

    var hasModel: Bool {
        FileManager.default.fileExists(atPath: modelPath.path)
    }

    /// Download model with progress. All callbacks on main thread.
    func downloadModel(
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (Bool, String) -> Void
    ) {
        let modelURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(modelName)"
        guard let url = URL(string: modelURL) else {
            onComplete(false, "Invalid model URL")
            return
        }

        let delegate = DownloadDelegate(
            destination: modelPath,
            onProgress: onProgress,
            onComplete: onComplete
        )
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        task.resume()
    }

    /// Also try to install whisper-cpp via homebrew.
    func installBinary(onComplete: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
            // Fallback for Intel Mac
            if !FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
                process.executableURL = URL(fileURLWithPath: "/usr/local/bin/brew")
            }
            process.arguments = ["install", "whisper-cpp"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let ok = process.terminationStatus == 0
                DispatchQueue.main.async {
                    onComplete(ok, ok ? "whisper-cpp installed!" : "brew install failed (exit \(process.terminationStatus))")
                }
            } catch {
                DispatchQueue.main.async {
                    onComplete(false, "Homebrew not found. Install from brew.sh first.")
                }
            }
        }
    }

    // MARK: - Recording

    func startListening() {
        guard !isRecording else { return }

        // Check setup first
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            onError?("whisper-cpp not installed. Run: brew install whisper-cpp")
            return
        }

        if !FileManager.default.fileExists(atPath: modelPath.path) {
            onError?("Model not downloaded. Go to Settings → Speech Recognition → Download Model.")
            return
        }

        doStartListening()
    }

    private func doStartListening() {
        isRecording = true
        audioBuffer = []

        let engine = AVAudioEngine()
        self.audioEngine = engine
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            onError?("Invalid audio format. Check microphone.")
            isRecording = false
            return
        }

        recordingSampleRate = nativeFormat.sampleRate
        let nativeChannels = Int(nativeFormat.channelCount)

        var silentChunks = 0
        var hasSpeech = false
        let chunkDuration: TimeInterval = 0.1
        let silenceChunksNeeded = Int(silenceDuration / chunkDuration)
        let maxChunks = Int(maxRecordSeconds / chunkDuration)
        var totalChunks = 0

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            guard let self, self.isRecording else { return }
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)

            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount * nativeChannels))
            self.audioBuffer.append(contentsOf: samples)

            // RMS on first channel only
            var sum: Float = 0
            for i in stride(from: 0, to: min(frameCount * nativeChannels, samples.count), by: nativeChannels) {
                sum += samples[i] * samples[i]
            }
            let rms = sqrt(sum / Float(frameCount))
            let level = min(rms * 5, 1.0)

            DispatchQueue.main.async { self.onAudioLevel?(level) }

            if rms > self.silenceThreshold {
                hasSpeech = true
                silentChunks = 0
            } else {
                silentChunks += 1
            }
            totalChunks += 1

            if (hasSpeech && silentChunks >= silenceChunksNeeded) || totalChunks >= maxChunks {
                DispatchQueue.main.async { self.finishRecording(nativeChannels: nativeChannels) }
            }
        }

        do {
            engine.prepare()
            try engine.start()
            onStatusUpdate?("Listening...")
        } catch {
            onError?("Failed to start recording: \(error.localizedDescription)")
            isRecording = false
        }
    }

    func stopListening() {
        isRecording = false
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
    }

    private func finishRecording(nativeChannels: Int) {
        let rawSamples = audioBuffer
        let srcRate = recordingSampleRate
        stopListening()

        // Convert to mono
        var mono: [Float]
        if nativeChannels > 1 {
            mono = stride(from: 0, to: rawSamples.count, by: nativeChannels).map { rawSamples[$0] }
        } else {
            mono = rawSamples
        }

        // Downsample to 16kHz
        let targetRate: Double = 16000
        if srcRate != targetRate {
            let ratio = targetRate / srcRate
            let newCount = Int(Double(mono.count) * ratio)
            var downsampled = [Float](repeating: 0, count: newCount)
            for i in 0..<newCount {
                let idx = Int(Double(i) / ratio)
                if idx < mono.count { downsampled[i] = mono[idx] }
            }
            mono = downsampled
        }

        let duration = Double(mono.count) / targetRate
        if duration < 0.5 {
            onError?("Too short, ignored.")
            return
        }

        onStatusUpdate?("Transcribing \(String(format: "%.1f", duration))s...")

        // Save to temp WAV and run whisper-cpp
        transcribeWithCLI(samples: mono, sampleRate: targetRate)
    }

    // MARK: - Whisper CLI

    private func transcribeWithCLI(samples: [Float], sampleRate: Double) {
        let wavData = samplesToWAV(samples, sampleRate: sampleRate)
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("claude_gamepad_\(UUID().uuidString).wav")

        do {
            try wavData.write(to: tmpFile)
        } catch {
            onError?("Failed to write temp audio: \(error.localizedDescription)")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.binaryPath)
            process.arguments = [
                "-m", self.modelPath.path,
                "-f", tmpFile.path,
                "-l", "auto",      // auto-detect language
                "--no-timestamps",  // clean text output
                "-otxt",            // output as text
            ]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                // whisper-cpp -otxt writes to <input>.txt
                let txtFile = tmpFile.appendingPathExtension("txt")
                // Also try reading stdout
                let stdoutData = pipe.fileHandleForReading.readDataToEndOfFile()
                var text = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                // Check txt file output
                if text.isEmpty, let txtContent = try? String(contentsOf: txtFile, encoding: .utf8) {
                    text = txtContent.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                // Cleanup
                try? FileManager.default.removeItem(at: tmpFile)
                try? FileManager.default.removeItem(at: txtFile)

                DispatchQueue.main.async {
                    if text.isEmpty {
                        self.onError?("Didn't catch that. Try again.")
                    } else {
                        self.onResult?(text)
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at: tmpFile)
                DispatchQueue.main.async {
                    self.onError?("whisper-cpp failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - WAV Encoding

    private func samplesToWAV(_ samples: [Float], sampleRate: Double) -> Data {
        let numSamples = samples.count
        let bitsPerSample = 16
        let numChannels = 1
        let byteRate = Int(sampleRate) * numChannels * bitsPerSample / 8
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = numSamples * blockAlign
        let fileSize = 36 + dataSize

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Data($0) })
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(numChannels).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Data($0) })
        data.append("data".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Data($0) })

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Val = Int16(clamped * 32767)
            data.append(withUnsafeBytes(of: int16Val.littleEndian) { Data($0) })
        }
        return data
    }
}

// MARK: - Download Delegate with Progress

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let destination: URL
    let onProgress: (Double) -> Void
    let onComplete: (Bool, String) -> Void

    init(destination: URL, onProgress: @escaping (Double) -> Void, onComplete: @escaping (Bool, String) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.onProgress(progress) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            DispatchQueue.main.async { self.onComplete(true, "Model downloaded!") }
        } catch {
            DispatchQueue.main.async { self.onComplete(false, "Failed to save: \(error.localizedDescription)") }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            DispatchQueue.main.async { self.onComplete(false, "Download failed: \(error.localizedDescription)") }
        }
    }
}
