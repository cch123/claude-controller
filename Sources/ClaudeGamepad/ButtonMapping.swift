import Foundation

/// Actions that can be assigned to a button.
enum ButtonAction: String, Codable, CaseIterable {
    case enter = "Enter (确认)"
    case ctrlC = "Ctrl+C (中断)"
    case accept = "Accept (y+Enter)"
    case reject = "Reject (n+Enter)"
    case tab = "Tab (补全)"
    case escape = "Escape"
    case voiceInput = "Voice Input (语音输入)"
    case presetMenu = "Preset Menu (预设菜单)"
    case clear = "/clear"
    case arrowUp = "Arrow Up (↑)"
    case arrowDown = "Arrow Down (↓)"
    case arrowLeft = "Arrow Left (←)"
    case arrowRight = "Arrow Right (→)"
    case quit = "Quit (退出)"
    case none = "None (无)"
}

/// Preset prompt configuration and quick prompt mappings.
struct ButtonMapping: Codable {
    var presetPrompts: [String]
    var ltPrompts: QuickPrompts
    var rtPrompts: QuickPrompts
    var buttonActions: ButtonActions

    struct QuickPrompts: Codable {
        var a: String
        var b: String
        var x: String
        var y: String
    }

    struct ButtonActions: Codable {
        var a: ButtonAction
        var b: ButtonAction
        var x: ButtonAction
        var y: ButtonAction
        var lb: ButtonAction
        var rb: ButtonAction
        var start: ButtonAction
        var select: ButtonAction
        var stickClick: ButtonAction
        var dpadUp: ButtonAction
        var dpadDown: ButtonAction
        var dpadLeft: ButtonAction
        var dpadRight: ButtonAction

        static let `default` = ButtonActions(
            a: .enter,
            b: .ctrlC,
            x: .accept,
            y: .reject,
            lb: .tab,
            rb: .escape,
            start: .presetMenu,
            select: .clear,
            stickClick: .voiceInput,
            dpadUp: .arrowUp,
            dpadDown: .arrowDown,
            dpadLeft: .arrowLeft,
            dpadRight: .arrowRight
        )
    }

    static let `default` = ButtonMapping(
        presetPrompts: [
            "fix the failing tests",
            "explain what this code does",
            "add error handling",
            "write tests for this",
            "refactor this to be cleaner",
            "find and fix the bug",
            "optimize this for performance",
            "add types and documentation",
        ],
        ltPrompts: QuickPrompts(
            a: "fix the failing tests",
            b: "explain this error",
            x: "continue",
            y: "undo the last change"
        ),
        rtPrompts: QuickPrompts(
            a: "run the tests",
            b: "show me the diff",
            x: "looks good, commit this",
            y: "refactor this to be cleaner"
        ),
        buttonActions: .default
    )

    // MARK: - Persistence

    private static var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ClaudeGamepad")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> ButtonMapping {
        guard let data = try? Data(contentsOf: configURL),
              let mapping = try? JSONDecoder().decode(ButtonMapping.self, from: data) else {
            return .default
        }
        return mapping
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: ButtonMapping.configURL)
    }
}
