import AppKit
import GameController

/// Menu bar application delegate.
/// Manages the status bar icon, menu, and coordinates all subsystems.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: SettingsWindow?

    private var accessibilityTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        requestPermissions()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: "Claude Gamepad")
            button.image?.isTemplate = true
            // Gray when no controller
            button.appearsDisabled = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Claude Gamepad Controller", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let statusMenuItem = NSMenuItem(title: "No controller connected", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        // Set targets
        for item in menu.items {
            if item.action != nil {
                item.target = self
            }
        }

        statusItem.menu = menu
    }

    // MARK: - Gamepad

    private func setupGamepad() {
        let manager = GamepadManager.shared

        manager.onControllerConnected = { [weak self] name in
            DispatchQueue.main.async {
                self?.statusItem.button?.appearsDisabled = false
                self?.updateStatusMenuItem("🎮 \(name)")
            }
        }

        manager.onControllerDisconnected = { [weak self] in
            DispatchQueue.main.async {
                self?.statusItem.button?.appearsDisabled = true
                self?.updateStatusMenuItem("No controller connected")
            }
        }

        manager.start()
    }

    private func updateStatusMenuItem(_ text: String) {
        guard let menu = statusItem.menu,
              let item = menu.item(withTag: 100) else { return }
        item.title = text
    }

    // MARK: - Permissions

    private func requestPermissions() {
        // All TCC permission requests (Speech, Accessibility) are deferred to
        // actual use to avoid __TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__ in
        // non-bundled executables on macOS 26+.
        // OverlayPanel (floating NSPanel) is also deferred — creating it at
        // launch can trigger a screen-overlay TCC check on macOS 26.

        if AXIsProcessTrusted() {
            setupGamepad()
        } else {
            print("[ClaudeGamepad] Accessibility not granted.")
            print("[ClaudeGamepad] Add this terminal app in System Settings → Privacy & Security → Accessibility.")
            print("[ClaudeGamepad] Waiting for permission...")
            // Poll until the user grants permission — no UI at this stage
            accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.accessibilityTimer = nil
                    print("[ClaudeGamepad] Accessibility granted!")
                    self?.setupGamepad()
                }
            }
        }
    }

    // MARK: - Menu Actions

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow()
        }
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

@objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
