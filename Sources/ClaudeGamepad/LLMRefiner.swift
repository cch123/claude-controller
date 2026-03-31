import Foundation

/// Refines speech recognition results using an OpenAI-compatible LLM API.
/// Fixes common recognition errors like Chinese homophones and misrecognized technical terms.
final class LLMRefiner {
    static let shared = LLMRefiner()

    var isEnabled: Bool = false
    var apiBaseURL: String = "https://api.openai.com/v1"
    var apiKey: String = ""
    var model: String = "gpt-4o-mini"
    var timeoutSeconds: TimeInterval = 10

    private init() {}

    /// Refine transcribed text via LLM. Returns original text on failure.
    func refine(_ text: String, completion: @escaping (String) -> Void) {
        guard isEnabled else {
            completion(text)
            return
        }

        let endpoint = apiBaseURL.hasSuffix("/") ? "\(apiBaseURL)chat/completions" : "\(apiBaseURL)/chat/completions"
        guard let url = URL(string: endpoint) else {
            completion(text)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeoutSeconds

        let systemPrompt = """
        You are a speech recognition post-processor. The user will give you a raw speech-to-text transcription. \
        Your job is to conservatively fix ONLY obvious recognition errors:
        - Chinese homophone mistakes (同音字错误)
        - Misrecognized English technical terms (e.g., "react" → "React", "get hub" → "GitHub")
        - Missing or wrong punctuation

        Rules:
        - Do NOT rewrite, summarize, or polish the text
        - Do NOT change the meaning or add words
        - Do NOT translate between languages
        - If unsure, keep the original
        - Return ONLY the corrected text, nothing else
        """

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.3,
            "max_tokens": 1024,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(text)
            return
        }
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                completion(text)
                return
            }
            let refined = content.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(refined.isEmpty ? text : refined)
        }.resume()
    }

    // MARK: - Persistence

    private static var settingsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ClaudeGamepad")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("llm_settings.json")
    }

    func loadSettings() {
        guard let data = try? Data(contentsOf: LLMRefiner.settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        isEnabled = json["enabled"] as? Bool ?? false
        apiBaseURL = json["apiBaseURL"] as? String ?? "https://api.openai.com/v1"
        apiKey = json["apiKey"] as? String ?? ""
        model = json["model"] as? String ?? "gpt-4o-mini"
    }

    func saveSettings() {
        let json: [String: Any] = [
            "enabled": isEnabled,
            "apiBaseURL": apiBaseURL,
            "apiKey": apiKey,
            "model": model,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) else { return }
        try? data.write(to: LLMRefiner.settingsURL)
    }
}
