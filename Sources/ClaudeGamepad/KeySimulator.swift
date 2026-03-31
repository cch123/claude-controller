import AppKit
import Carbon.HIToolbox

/// Simulates keyboard input via CGEvent API.
final class KeySimulator {
    static let shared = KeySimulator()
    private init() {}

    // Common key codes (Carbon virtual key codes)
    static let kVK_Return: CGKeyCode       = 0x24
    static let kVK_Tab: CGKeyCode          = 0x30
    static let kVK_Escape: CGKeyCode       = 0x35
    static let kVK_UpArrow: CGKeyCode      = 0x7E
    static let kVK_DownArrow: CGKeyCode    = 0x7D
    static let kVK_LeftArrow: CGKeyCode    = 0x7B
    static let kVK_RightArrow: CGKeyCode   = 0x7C
    static let kVK_ANSI_C: CGKeyCode       = 0x08
    static let kVK_ANSI_N: CGKeyCode       = 0x2D
    static let kVK_ANSI_Y: CGKeyCode       = 0x10
    static let kVK_ANSI_V: CGKeyCode       = 0x09

    /// Press and release a single key.
    func pressKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// Press Enter.
    func pressEnter() {
        pressKey(KeySimulator.kVK_Return)
    }

    /// Press Ctrl+C.
    func pressCtrlC() {
        pressKey(KeySimulator.kVK_ANSI_C, flags: .maskControl)
    }

    /// Press Tab.
    func pressTab() {
        pressKey(KeySimulator.kVK_Tab)
    }

    /// Press Escape.
    func pressEscape() {
        pressKey(KeySimulator.kVK_Escape)
    }

    /// Press arrow key.
    func pressArrow(_ direction: ArrowDirection) {
        switch direction {
        case .up:    pressKey(KeySimulator.kVK_UpArrow)
        case .down:  pressKey(KeySimulator.kVK_DownArrow)
        case .left:  pressKey(KeySimulator.kVK_LeftArrow)
        case .right: pressKey(KeySimulator.kVK_RightArrow)
        }
    }

    /// Paste a string via AppleScript (clipboard + Cmd+V), without pressing Enter.
    /// Uses System Events for reliable cross-app paste.
    func pasteString(_ text: String) {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")

        let script = """
        set the clipboard to "\(escaped)"
        tell application "System Events" to keystroke "v" using command down
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        usleep(100_000)
    }

    /// Paste a string and press Enter.
    func typeString(_ text: String) {
        pasteString(text)
        usleep(50_000)
        pressEnter()
    }

    /// Type 'y' + Enter (accept).
    func typeAccept() {
        pressKey(KeySimulator.kVK_ANSI_Y)
        usleep(20_000)
        pressEnter()
    }

    /// Type 'n' + Enter (reject).
    func typeReject() {
        pressKey(KeySimulator.kVK_ANSI_N)
        usleep(20_000)
        pressEnter()
    }

    enum ArrowDirection {
        case up, down, left, right
    }
}
