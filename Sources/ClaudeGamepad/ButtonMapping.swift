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

/// Input element for command combos.
enum ComboInput: String, Codable, CaseIterable {
    case up = "↑"
    case down = "↓"
    case left = "←"
    case right = "→"
    case a = "A"
    case b = "B"
    case x = "X"
    case y = "Y"
}

/// Command combo input style.
enum ComboStyle: String, Codable, CaseIterable {
    case fighting = "Fighting Game (格斗游戏)"
    case helldivers = "Helldivers 2 (绝地潜兵)"
}

/// A command combo: a sequence of inputs that triggers a prompt.
struct ComboEntry: Codable {
    var name: String
    var inputs: [ComboInput]
    var prompt: String
    var style: ComboStyle

    /// Display string for the input sequence.
    var inputDisplay: String {
        inputs.map(\.rawValue).joined(separator: " ")
    }
}

/// A category of preset prompts.
struct PresetCategory: Codable {
    var name: String
    var prompts: [String]
}

/// Preset prompt configuration and quick prompt mappings.
struct ButtonMapping: Codable {
    var categories: [PresetCategory]
    var presetPrompts: [String]  // flat list for Start menu cycling (derived from categories)
    var ltPrompts: QuickPrompts
    var rtPrompts: QuickPrompts
    var buttonActions: ButtonActions

    struct QuickPrompts: Codable {
        var a: String
        var b: String
        var x: String
        var y: String
    }

    /// All prompts flattened from categories.
    var allPrompts: [String] {
        categories.flatMap { $0.prompts }
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

    static let defaultCategories: [PresetCategory] = [
        PresetCategory(name: "Debug", prompts: [
            "fix the failing tests",
            "find and fix the bug",
            "explain this error",
        ]),
        PresetCategory(name: "Code", prompts: [
            "explain what this code does",
            "refactor this to be cleaner",
            "optimize this for performance",
            "add types and documentation",
        ]),
        PresetCategory(name: "Edit", prompts: [
            "add error handling",
            "write tests for this",
            "continue",
            "undo the last change",
        ]),
        PresetCategory(name: "Git", prompts: [
            "show me the diff",
            "looks good, commit this",
        ]),
    ]

    static let defaultCombos: [ComboEntry] = [
        // Helldivers-style (d-pad only)
        ComboEntry(name: "Reinforce", inputs: [.up, .down, .right, .left, .up], prompt: "fix all the errors", style: .helldivers),
        ComboEntry(name: "Resupply", inputs: [.down, .down, .up, .right], prompt: "add the missing dependencies", style: .helldivers),
        ComboEntry(name: "Air Strike", inputs: [.up, .right, .down, .right], prompt: "delete all unused code", style: .helldivers),
        ComboEntry(name: "Shield", inputs: [.down, .up, .left, .right], prompt: "add error handling to this", style: .helldivers),
        ComboEntry(name: "Orbital", inputs: [.right, .right, .up], prompt: "refactor this completely", style: .helldivers),
        ComboEntry(name: "EAT", inputs: [.up, .down, .left, .up, .right], prompt: "write comprehensive tests", style: .helldivers),
        // Fighting-game-style (directions + face button finisher)
        ComboEntry(name: "Hadouken", inputs: [.down, .right, .a], prompt: "run the tests", style: .fighting),
        ComboEntry(name: "Shoryuken", inputs: [.right, .down, .right, .a], prompt: "fix the bug", style: .fighting),
        ComboEntry(name: "Tatsumaki", inputs: [.down, .left, .b], prompt: "explain this code", style: .fighting),
        ComboEntry(name: "Sonic Boom", inputs: [.left, .right, .x], prompt: "looks good, commit this", style: .fighting),
        ComboEntry(name: "Super", inputs: [.down, .right, .down, .right, .a], prompt: "find and fix all bugs in this file", style: .fighting),
    ]

    static let `default` = ButtonMapping(
        categories: defaultCategories,
        presetPrompts: defaultCategories.flatMap { $0.prompts },
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
        buttonActions: .default,
        comboStyle: .helldivers,
        combos: defaultCombos
    )

    // MARK: - Command Combos

    var comboStyle: ComboStyle
    var combos: [ComboEntry]

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
