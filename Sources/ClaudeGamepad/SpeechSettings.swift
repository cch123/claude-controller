import Foundation

/// Which speech recognition engine to use.
enum SpeechEngineType: String, Codable, CaseIterable {
    case system = "System (系统语音识别)"
    case whisperLocal = "Whisper (本地 whisper.cpp)"
}

/// Persistent settings for speech recognition and LLM refinement.
struct SpeechSettings: Codable {
    var engineType: SpeechEngineType = .system
    var whisperModel: String = "ggml-base.bin"   // whisper.cpp model file name
    var llmEnabled: Bool = false
    var llmAPIURL: String = "http://localhost:11434/v1"
    var llmAPIKey: String = ""
    var llmModel: String = "qwen2.5:7b"

    static let `default` = SpeechSettings()

    // MARK: - Persistence

    private static var settingsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ClaudeGamepad")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("speech_settings.json")
    }

    static func load() -> SpeechSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(SpeechSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: SpeechSettings.settingsURL)
    }
}
