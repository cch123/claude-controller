# Claude Gamepad Controller

A native macOS menu bar app that lets you control [Claude Code](https://claude.ai/claude-code) with a game controller. Lean back, vibe code from your couch.

Supports Xbox, PS5 DualSense, and any MFi-compatible controller. Includes voice input via Apple Speech Recognition or local [whisper.cpp](https://github.com/ggerganov/whisper.cpp), with optional LLM-powered speech correction.

## Features

- **Menu bar app** - runs in the background, no Dock icon
- **Plug and play** - auto-detects Xbox / PS5 / MFi controllers via `GCController`
- **Full button mapping** - every button configurable via GUI settings
- **Voice input** - press stick to speak, transcription pasted to terminal
  - System speech recognition (zero setup)
  - Local whisper.cpp (higher quality, offline)
  - Optional LLM refinement (Ollama / OpenAI compatible)
- **Quick prompts** - LT/RT + face button sends preset prompts
- **Preset menu** - Start button opens D-pad-navigable prompt list
- **Floating HUD** - non-intrusive overlay shows button feedback and transcription
- **macOS native** - pure Swift + AppKit, no Electron, no Python

## Default Button Mapping

| Button | Action |
|--------|--------|
| A / x | Enter (confirm) |
| B / ○ | Ctrl+C (interrupt) |
| X / □ | Accept (y + Enter) |
| Y / △ | Reject (n + Enter) |
| D-pad | Arrow keys |
| LB / L1 | Tab (autocomplete) |
| RB / R1 | Escape |
| L3 / R3 Press | Voice input |
| Start / Menu | Preset menu |
| Select / View | `/clear` |
| LT + Face | Quick prompt (configurable) |
| RT + Face | Quick prompt (configurable) |
| LT + RT + Select | Quit |

All mappings are fully customizable in Settings.

## Screenshots

### Button Mapping

Buttons grouped by region — scan and reassign high-frequency actions at a glance.

![Button Mapping](screenshots/button-mapping.png)

### Preset Prompts

Edit all trigger combos from one focused workspace. Pick a preset or write custom text, with live character count and preview.

![Preset Prompts](screenshots/quick-prompts.png)

### Speech Recognition

See the full voice pipeline at a glance: engine, binary install state, model download status, and LLM cleanup toggle.

![Speech Recognition](screenshots/speech-recognition.png)

### Menu Bar

The app lives in your menu bar. Green icon when a controller is connected.

![Menu Bar](screenshots/menu-bar.png)

## Installation

### Requirements

- macOS 14.0 (Sonoma) or later
- A game controller (Xbox, PS5 DualSense, or MFi compatible)
- For Whisper: `brew install whisper-cpp` (optional)

### Build from Source

```bash
git clone https://github.com/xargin/claude-controller.git
cd claude-controller
swift build -c release
# Binary at .build/release/ClaudeGamepad
```

### Run

```bash
swift run
```

Or build and copy to your PATH:

```bash
swift build -c release
cp .build/release/ClaudeGamepad /usr/local/bin/
```

## First Launch

1. Run `swift run` or the built binary
2. Grant **Accessibility** permission when prompted (System Settings > Privacy & Security > Accessibility) — needed for keyboard simulation
3. Grant **Speech Recognition** permission if using voice input
4. Connect your controller — the menu bar icon turns active
5. Focus your terminal running Claude Code
6. Start pressing buttons!

## Configuration

Click the menu bar icon > **Settings** to open the settings window. The settings panel uses a dark-themed card layout with three tabs.

### Button Mapping

All button bindings organized by region: Shoulders, Face Buttons, Navigation, and System & Sticks. Each button has a dropdown to pick its action. LT/RT serve as modifier keys — their quick prompts are managed in the Preset Prompts tab.

### Preset Prompts

The left panel lists all quick prompt slots (LT+A, LT+B, RT+A, etc.); the right panel is a focused editor. Each slot can use a preset prompt or custom text, with live character count and preview.

Default quick prompts:

| Trigger | Prompt |
|---------|--------|
| LT + A | showtime |
| LT + B | fix the failing tests |
| LT + X | continue |
| LT + Y | undo the last change |
| RT + A | run the tests |
| RT + B | show me the diff |
| RT + X | looks good, commit this |
| RT + Y | add types and documentation |

### Speech Recognition

A top-level Voice Pipeline status bar shows engine, binary install state, model status, and LLM cleanup toggle at a glance. Below are two cards:

- **Whisper Local** — select a model (tiny 75MB to large-v3 3.1GB), one-click install binary, one-click download model
- **LLM Refinement** — configure API URL, API Key, and model name; works with Ollama, LM Studio, or any OpenAI-compatible endpoint

## Voice Input Flow

1. Press **L3 / R3** (stick click)
2. Floating HUD shows "Listening..." with a live waveform
3. Speak your prompt (auto-detects Chinese and English)
4. HUD shows transcription with `[A=confirm B=cancel]`
5. Press **A** to paste to terminal, or **B** to cancel

## Architecture

```
Sources/ClaudeGamepad/
  main.swift              # Entry point, menu bar app setup
  AppDelegate.swift       # Status bar icon, menu, permissions
  GamepadManager.swift    # GCController input handling + button mapping
  KeySimulator.swift      # CGEvent keyboard simulation
  SpeechEngine.swift      # Apple SFSpeechRecognizer integration
  WhisperEngine.swift     # Local whisper.cpp CLI integration
  LLMRefiner.swift        # Optional LLM speech post-processing
  OverlayPanel.swift      # Floating HUD panel + waveform visualization
  ButtonMapping.swift     # Button action config + persistence
  SpeechSettings.swift    # Speech/LLM config + persistence
  GamepadConfigView.swift # Visual button mapping editor
  SettingsWindow.swift    # Dark-themed card-based settings window
```

## License

MIT
