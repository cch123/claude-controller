#!/usr/bin/env python3
"""
🎮 Claude Code Gamepad Controller
Control Claude Code with a gamepad + voice input for prompts.
Lean back, vibe code from your couch.

Requirements:
    pip install pygame-ce pynput faster-whisper sounddevice numpy

Usage:
    python gamepad_claude.py

Controller Profiles:
    --xbox       Force Xbox controller mapping (default)
    --ps5        Force PS5 DualSense mapping
    (auto-detected if not specified)

Button Mapping (Xbox / PS5):
    A / ✕        → Enter (confirm)
    B / ○        → Ctrl+C (interrupt)
    X / □        → Type 'y' + Enter (accept edit)
    Y / △        → Type 'n' + Enter (reject edit)
    D-pad ↑/↓    → Arrow Up/Down (history / scroll)
    D-pad ←/→    → Arrow Left/Right
    LB / L1      → Tab (autocomplete)
    RB / R1      → Escape
    L-Stick Click → Trigger voice input for prompt
    R-Stick Click → Trigger voice input for prompt (same, either thumb)
    Start / Options → Preset prompt menu (cycle with D-pad, confirm with A/✕)
    Select / Create → Type '/clear' + Enter
    LT+RT+Select → Quit the controller

    LT/L2 + A/B/X/Y → Quick prompts (hold LT/L2 then press)
        LT + A / L2 + ✕  → "fix the failing tests"
        LT + B / L2 + ○  → "explain this error"
        LT + X / L2 + □  → "continue"
        LT + Y / L2 + △  → "undo the last change"

    RT/R2 + A/B/X/Y → More quick prompts (hold RT/R2 then press)
        RT + A / R2 + ✕  → "run the tests"
        RT + B / R2 + ○  → "show me the diff"
        RT + X / R2 + □  → "looks good, commit this"
        RT + Y / R2 + △  → "refactor this to be cleaner"
"""

import os
import sys
import time
import json
import threading
import subprocess
from enum import Enum, auto

# --- Lazy imports with helpful errors ---

def check_import(module_name, pip_name=None):
    try:
        return __import__(module_name)
    except ImportError:
        pip_name = pip_name or module_name
        install_name = "pygame-ce" if pip_name == "pygame" else pip_name
        print(f"❌ Missing '{module_name}'. Install with: pip install {install_name}")
        sys.exit(1)

pygame = check_import("pygame")
pynput_keyboard = check_import("pynput.keyboard", "pynput")

from pynput.keyboard import Key, Controller as KBController

# Speech recognition via faster-whisper (optional - degrades gracefully)
try:
    from faster_whisper import WhisperModel
    import sounddevice as sd
    import numpy as np
    HAS_SPEECH = True
except ImportError:
    HAS_SPEECH = False
    print("⚠️  Voice input disabled. Install with:")
    print("   pip install faster-whisper sounddevice numpy")

# ─── Voice Config ─────────────────────────────────────────────────

# Whisper model size: "large-v3" for best quality, "medium" for faster, "small" for low RAM
WHISPER_MODEL_SIZE = "large-v3"
# Device: "cpu" or "cuda" (Apple Silicon uses cpu with CTranslate2 auto-optimization)
WHISPER_DEVICE = "cpu"
WHISPER_COMPUTE_TYPE = "int8"  # int8 is fast on CPU, use float16 for GPU

# Audio recording settings
SAMPLE_RATE = 16000  # Whisper expects 16kHz
SILENCE_THRESHOLD = 0.01  # RMS threshold for silence detection
SILENCE_DURATION = 1.5  # Seconds of silence to stop recording
MAX_RECORD_SECONDS = 30  # Safety cap

# Lazy-loaded model (first voice input will take a few seconds to load)
_whisper_model = None

def get_whisper_model():
    global _whisper_model
    if _whisper_model is None:
        osd(f"🎤 Loading Whisper {WHISPER_MODEL_SIZE} (first time only)...")
        _whisper_model = WhisperModel(
            WHISPER_MODEL_SIZE,
            device=WHISPER_DEVICE,
            compute_type=WHISPER_COMPUTE_TYPE,
        )
        osd(f"🎤 Whisper model loaded!")
    return _whisper_model


# ─── Config ───────────────────────────────────────────────────────

# Polling rate (seconds) - 60Hz is plenty
POLL_INTERVAL = 1 / 60

# Analog stick deadzone
DEADZONE = 0.4

# Scroll repeat rate when stick is held
SCROLL_REPEAT_MS = 120

# D-pad as hat index
HAT_INDEX = 0

# ─── Controller Profiles ─────────────────────────────────────────

# Button/axis indices differ between Xbox and PS5 controllers.
# Run with --identify to check your controller's actual mapping.

PROFILES = {
    "xbox": {
        "name": "Xbox",
        "btn": {
            "A": 0, "B": 1, "X": 3, "Y": 4,
            "LB": 6, "RB": 7,
            "SELECT": 10, "START": 11,
            "L_STICK": 13, "R_STICK": 14,
        },
        "axis": {
            "LX": 0, "LY": 1, "RX": 2, "RY": 3,
            "LT": 4, "RT": 5,
        },
        # Xbox triggers go from -1 (released) to 1 (pressed)
        "trigger_threshold": 0.3,
    },
    "ps5": {
        "name": "PS5 DualSense",
        "btn": {
            "A": 0,   # ✕ Cross
            "B": 1,   # ○ Circle
            "X": 2,   # □ Square
            "Y": 3,   # △ Triangle
            "LB": 4,  # L1
            "RB": 5,  # R1
            "SELECT": 6,   # Create
            "START": 7,    # Options
            "L_STICK": 8,  # L3
            "R_STICK": 9,  # R3
            # 10 = PS button, 11 = Touchpad click
        },
        "axis": {
            "LX": 0, "LY": 1, "RX": 2, "RY": 3,
            "LT": 4,  # L2
            "RT": 5,  # R2
        },
        # PS5 triggers go from -1 (released) to 1 (pressed)
        "trigger_threshold": 0.3,
    },
}

# Auto-detect keywords in controller name → profile
PS5_KEYWORDS = ["dualsense", "ps5", "wireless controller", "054c:0ce6"]
XBOX_KEYWORDS = ["xbox", "xinput"]


def detect_profile(controller_name: str) -> str:
    """Auto-detect controller profile from its name."""
    name_lower = controller_name.lower()
    for kw in PS5_KEYWORDS:
        if kw in name_lower:
            return "ps5"
    for kw in XBOX_KEYWORDS:
        if kw in name_lower:
            return "xbox"
    return "xbox"  # default


def load_profile(profile_name: str):
    """Load a controller profile into global Btn and Axis classes."""
    profile = PROFILES[profile_name]
    for key, val in profile["btn"].items():
        setattr(Btn, key, val)
    for key, val in profile["axis"].items():
        setattr(Axis, key, val)
    Axis.TRIGGER_THRESHOLD = profile["trigger_threshold"]
    return profile


CONFIG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "controller_config.json")

class Btn:
    A = 0
    B = 1
    X = 3
    Y = 4
    LB = 6
    RB = 7
    SELECT = 10
    START = 11
    L_STICK = 13
    R_STICK = 14

class Axis:
    LX = 0
    LY = 1
    RX = 2
    RY = 3
    LT = 4
    RT = 5
    TRIGGER_THRESHOLD = 0.3


# ─── Preset prompts (cycle with Start + D-pad) ───────────────────

PRESET_PROMPTS = [
    "fix the failing tests",
    "explain what this code does",
    "add error handling",
    "write tests for this",
    "refactor this to be cleaner",
    "find and fix the bug",
    "optimize this for performance",
    "add types and documentation",
]

# Quick prompts - built dynamically after profile is loaded
LT_PROMPTS = {}
RT_PROMPTS = {}

def init_quick_prompts():
    """Initialize quick prompt dicts with current Btn values."""
    global LT_PROMPTS, RT_PROMPTS
    LT_PROMPTS = {
        Btn.A: "fix the failing tests",
        Btn.B: "explain this error",
        Btn.X: "continue",
        Btn.Y: "undo the last change",
    }
    RT_PROMPTS = {
        Btn.A: "run the tests",
        Btn.B: "show me the diff",
        Btn.X: "looks good, commit this",
        Btn.Y: "refactor this to be cleaner",
    }


# ─── State ────────────────────────────────────────────────────────

class Mode(Enum):
    NORMAL = auto()
    PRESET_MENU = auto()
    VOICE_INPUT = auto()

class State:
    mode: Mode = Mode.NORMAL
    preset_index: int = 0
    voice_listening: bool = False
    lt_held: bool = False
    rt_held: bool = False
    last_scroll_time: float = 0

state = State()
kb = KBController()
loaded_config = None  # Set after loading config file


# ─── Helpers ──────────────────────────────────────────────────────

def paste_string(s: str):
    """Paste a string into the focused app via clipboard, without pressing Enter.
    Uses AppleScript to set clipboard and keystroke paste for precise control."""
    s = s.replace("\n", " ").replace("\r", "").replace('"', '\\"').replace("\\", "\\\\")
    subprocess.run([
        "osascript",
        "-e", f'set the clipboard to "{s}"',
        "-e", 'tell application "System Events" to keystroke "v" using command down',
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.1)

def type_string(s: str):
    """Paste a string and press Enter."""
    paste_string(s)
    time.sleep(0.05)
    kb.press(Key.enter)
    kb.release(Key.enter)

def press_key(key):
    kb.press(key)
    kb.release(key)

def press_combo(*keys):
    """Press a key combination (e.g., Ctrl+C)."""
    for k in keys:
        kb.press(k)
    time.sleep(0.02)
    for k in reversed(keys):
        kb.release(k)

def notify(title: str, msg: str = ""):
    """macOS notification via osascript."""
    escaped = msg.replace('"', '\\"')
    subprocess.Popen([
        "osascript", "-e",
        f'display notification "{escaped}" with title "🎮 {title}"'
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def osd(msg: str):
    """On-screen display - just print + optional notification."""
    print(f"  🎮 {msg}")


# ─── Voice Input ──────────────────────────────────────────────────

def record_until_silence() -> np.ndarray:
    """Record audio from mic, stop after silence is detected."""
    osd("🎤 Listening... speak your prompt (auto-stops on silence)")
    notify("Voice Input", "Listening...")

    chunks = []
    silent_chunks = 0
    has_speech = False
    chunk_duration = 0.1  # 100ms chunks
    chunk_samples = int(SAMPLE_RATE * chunk_duration)
    silence_chunks_needed = int(SILENCE_DURATION / chunk_duration)
    max_chunks = int(MAX_RECORD_SECONDS / chunk_duration)

    with sd.InputStream(samplerate=SAMPLE_RATE, channels=1, dtype="float32") as stream:
        for _ in range(max_chunks):
            data, _ = stream.read(chunk_samples)
            chunks.append(data.copy())
            rms = np.sqrt(np.mean(data ** 2))

            if rms > SILENCE_THRESHOLD:
                has_speech = True
                silent_chunks = 0
            else:
                silent_chunks += 1

            # Stop after enough silence, but only if we've heard speech
            if has_speech and silent_chunks >= silence_chunks_needed:
                break

    audio = np.concatenate(chunks, axis=0).flatten()
    return audio


def voice_input_thread():
    """Record speech, transcribe with faster-whisper, type as prompt."""
    if not HAS_SPEECH:
        osd("Voice input not available (install faster-whisper sounddevice numpy)")
        state.voice_listening = False
        return

    state.voice_listening = True

    try:
        audio = record_until_silence()

        # Skip if too short (just noise)
        duration = len(audio) / SAMPLE_RATE
        if duration < 0.5:
            osd("🎤 Too short, ignored.")
            return

        osd(f"🎤 Transcribing {duration:.1f}s of audio...")

        model = get_whisper_model()
        segments, info = model.transcribe(
            audio,
            beam_size=5,
            language=None,  # auto-detect language (中英文都行)
            vad_filter=True,  # filter out non-speech
            vad_parameters=dict(min_silence_duration_ms=500),
        )

        text = "".join(seg.text for seg in segments).strip().replace("\n", " ")

        if text:
            lang = info.language
            osd(f"🎤 [{lang}] \"{text}\"")
            osd("🎤 Press A/✕ to send, B/○ to cancel")
            notify("Voice Input", text)
            paste_string(text)
        else:
            osd("🎤 Didn't catch that. Try again.")
            notify("Voice Input", "Couldn't understand. Try again.")

    except Exception as e:
        osd(f"🎤 Voice error: {e}")
    finally:
        state.voice_listening = False
        state.mode = Mode.NORMAL


# ─── Preset Menu ──────────────────────────────────────────────────

def show_preset_menu():
    """Display the preset prompt menu in terminal."""
    print("\n  ┌─────────────────────────────────────┐")
    print("  │  📋 Preset Prompts (D-pad ↑↓, A=go) │")
    print("  ├─────────────────────────────────────┤")
    for i, p in enumerate(PRESET_PROMPTS):
        marker = " ▸ " if i == state.preset_index else "   "
        print(f"  │{marker}{p:<34}│")
    print("  └─────────────────────────────────────┘\n")


# ─── Button Handlers ──────────────────────────────────────────────

def on_button_down(button: int):
    # --- D-pad as buttons (must check before other buttons to avoid collisions) ---
    if loaded_config and loaded_config.get("dpad_type") == "button":
        dpad = loaded_config.get("dpad", {})
        if button == dpad.get("UP"):
            if state.mode == Mode.PRESET_MENU:
                state.preset_index = (state.preset_index - 1) % len(PRESET_PROMPTS)
                show_preset_menu()
            else:
                press_key(Key.up)
            return
        elif button == dpad.get("DOWN"):
            if state.mode == Mode.PRESET_MENU:
                state.preset_index = (state.preset_index + 1) % len(PRESET_PROMPTS)
                show_preset_menu()
            else:
                press_key(Key.down)
            return
        elif button == dpad.get("LEFT"):
            press_key(Key.left)
            return
        elif button == dpad.get("RIGHT"):
            press_key(Key.right)
            return

    # --- LT + RT + Select = quit ---
    if button == Btn.SELECT and state.lt_held and state.rt_held:
        osd("Quitting! 👋")
        notify("Gamepad Controller", "Bye!")
        raise SystemExit(0)

    # --- Modifier detection ---
    if button == Btn.SELECT:
        osd("/clear")
        type_string("/clear")
        return

    if button == Btn.START:
        if state.mode == Mode.PRESET_MENU:
            state.mode = Mode.NORMAL
            osd("Preset menu closed")
        else:
            state.mode = Mode.PRESET_MENU
            state.preset_index = 0
            show_preset_menu()
        return

    if button in (Btn.L_STICK, Btn.R_STICK):
        if not state.voice_listening:
            state.mode = Mode.VOICE_INPUT
            threading.Thread(target=voice_input_thread, daemon=True).start()
        return

    # --- Preset menu mode ---
    if state.mode == Mode.PRESET_MENU:
        if button == Btn.A:
            prompt = PRESET_PROMPTS[state.preset_index]
            state.mode = Mode.NORMAL
            osd(f"Sending: {prompt}")
            type_string(prompt)
        elif button == Btn.B:
            state.mode = Mode.NORMAL
            osd("Preset menu cancelled")
        return

    # --- LT + button = quick prompt ---
    if state.lt_held and button in LT_PROMPTS:
        prompt = LT_PROMPTS[button]
        osd(f"Quick: {prompt}")
        type_string(prompt)
        return

    # --- RT + button = quick prompt ---
    if state.rt_held and button in RT_PROMPTS:
        prompt = RT_PROMPTS[button]
        osd(f"Quick: {prompt}")
        type_string(prompt)
        return

    # --- D-pad as buttons (when config says dpad_type == "button") ---
    if loaded_config and loaded_config.get("dpad_type") == "button":
        dpad = loaded_config.get("dpad", {})
        if button == dpad.get("UP"):
            if state.mode == Mode.PRESET_MENU:
                state.preset_index = (state.preset_index - 1) % len(PRESET_PROMPTS)
                show_preset_menu()
            else:
                press_key(Key.up)
            return
        elif button == dpad.get("DOWN"):
            if state.mode == Mode.PRESET_MENU:
                state.preset_index = (state.preset_index + 1) % len(PRESET_PROMPTS)
                show_preset_menu()
            else:
                press_key(Key.down)
            return
        elif button == dpad.get("LEFT"):
            press_key(Key.left)
            return
        elif button == dpad.get("RIGHT"):
            press_key(Key.right)
            return

    # --- Normal mode ---
    if button == Btn.A:
        osd("Enter")
        press_key(Key.enter)
    elif button == Btn.B:
        osd("Ctrl+C")
        press_combo(Key.ctrl, 'c')
    elif button == Btn.X:
        osd("Accept (y)")
        kb.type('y')
        time.sleep(0.02)
        press_key(Key.enter)
    elif button == Btn.Y:
        osd("Reject (n)")
        kb.type('n')
        time.sleep(0.02)
        press_key(Key.enter)
    elif button == Btn.LB:
        osd("Tab")
        press_key(Key.tab)
    elif button == Btn.RB:
        osd("Escape")
        press_key(Key.esc)


def on_hat(x: int, y: int):
    """D-pad input (hat switch)."""
    if state.mode == Mode.PRESET_MENU:
        if y == -1:  # Up
            state.preset_index = (state.preset_index - 1) % len(PRESET_PROMPTS)
            show_preset_menu()
        elif y == 1:  # Down
            state.preset_index = (state.preset_index + 1) % len(PRESET_PROMPTS)
            show_preset_menu()
        return

    if y == -1:
        press_key(Key.up)
    elif y == 1:
        press_key(Key.down)
    if x == 1:
        press_key(Key.right)
    elif x == -1:
        press_key(Key.left)


def handle_sticks(joystick):
    """Left stick for scrolling output."""
    try:
        ly = joystick.get_axis(Axis.LY)
    except:
        return

    now = time.time()
    if abs(ly) > DEADZONE and (now - state.last_scroll_time) > SCROLL_REPEAT_MS / 1000:
        if ly < -DEADZONE:
            press_key(Key.up)
        elif ly > DEADZONE:
            press_key(Key.down)
        state.last_scroll_time = now


def handle_triggers(joystick):
    """Track LT/RT held state for modifier combos."""
    try:
        lt = joystick.get_axis(Axis.LT)
        rt = joystick.get_axis(Axis.RT)
        state.lt_held = lt > Axis.TRIGGER_THRESHOLD
        state.rt_held = rt > Axis.TRIGGER_THRESHOLD
    except:
        pass


# ─── Init / Calibration Mode ─────────────────────────────────────

INIT_BUTTON_PROMPTS = [
    ("A / ✕ (确认)", "A"),
    ("B / ○ (取消/中断)", "B"),
    ("X / □ (接受)", "X"),
    ("Y / △ (拒绝)", "Y"),
    ("LB / L1 (左肩键)", "LB"),
    ("RB / R1 (右肩键)", "RB"),
    ("Select / Create (选择键)", "SELECT"),
    ("Start / Options (开始键)", "START"),
    ("左摇杆按下 (L3)", "L_STICK"),
    ("右摇杆按下 (R3)", "R_STICK"),
]

INIT_DPAD_PROMPTS = [
    ("D-pad ↑ (十字键上)", "UP"),
    ("D-pad ↓ (十字键下)", "DOWN"),
    ("D-pad ← (十字键左)", "LEFT"),
    ("D-pad → (十字键右)", "RIGHT"),
]

INIT_AXIS_PROMPTS = [
    ("左摇杆 → 往右推到底", "LX", 1),
    ("左摇杆 ↓ 往下推到底", "LY", 1),
    ("右摇杆 → 往右推到底", "RX", 1),
    ("右摇杆 ↓ 往下推到底", "RY", 1),
    ("LT / L2 (左扳机，按到底)", "LT", 1),
    ("RT / R2 (右扳机，按到底)", "RT", 1),
]


def wait_for_button(joystick):
    """Wait for a single button press and return its index."""
    # Drain pending events
    pygame.event.pump()
    pygame.event.get()
    while True:
        pygame.event.pump()
        for event in pygame.event.get():
            if event.type == pygame.JOYBUTTONDOWN:
                return ("button", event.button)
            elif event.type == pygame.JOYHATMOTION:
                if event.value != (0, 0):
                    return ("hat", event.hat, event.value)
        time.sleep(0.016)


def wait_for_dpad(joystick):
    """Wait for a D-pad press (button or hat) and return it."""
    pygame.event.pump()
    pygame.event.get()
    while True:
        pygame.event.pump()
        for event in pygame.event.get():
            if event.type == pygame.JOYBUTTONDOWN:
                return ("button", event.button)
            elif event.type == pygame.JOYHATMOTION:
                if event.value != (0, 0):
                    return ("hat", event.hat, event.value)
        time.sleep(0.016)


def wait_for_axis(joystick, threshold=0.8):
    """Wait for an axis to be pushed past threshold, return axis index."""
    pygame.event.pump()
    pygame.event.get()
    # Read baseline
    time.sleep(0.1)
    pygame.event.pump()
    while True:
        pygame.event.pump()
        pygame.event.get()
        for i in range(joystick.get_numaxes()):
            val = joystick.get_axis(i)
            if abs(val) > threshold:
                # Wait for release
                time.sleep(0.3)
                return i
        time.sleep(0.016)


def init_mode(joystick):
    """Interactive calibration: prompt user to press each button, save config."""
    print("\n  ╔═══════════════════════════════════════════════╗")
    print("  ║  🎮 手柄初始化 - 按照提示依次按下对应按键      ║")
    print("  ║     每次只按一个键，按完等待下一个提示          ║")
    print("  ║     按 Ctrl+C 取消                            ║")
    print("  ╚═══════════════════════════════════════════════╝\n")

    config = {"buttons": {}, "dpad": {}, "dpad_type": None, "axes": {}, "trigger_threshold": 0.3}

    try:
        # --- Buttons ---
        print("  ── 按键映射 ──\n")
        for prompt_text, key_name in INIT_BUTTON_PROMPTS:
            print(f"  👉 请按下: {prompt_text}", end="", flush=True)
            result = wait_for_button(joystick)
            if result[0] == "button":
                config["buttons"][key_name] = result[1]
                print(f"  ✅ Button {result[1]}")
            elif result[0] == "hat":
                config["buttons"][key_name] = result[1]  # hat index as fallback
                print(f"  ⚠️  Hat {result[1]} {result[2]} (意外，但已记录)")
            time.sleep(0.3)

        # --- D-pad ---
        print("\n  ── 十字键映射 ──\n")
        print("  （十字键可能被识别为 Hat 或按钮，两种都支持）\n")

        dpad_results = {}
        for prompt_text, direction in INIT_DPAD_PROMPTS:
            print(f"  👉 请按下: {prompt_text}", end="", flush=True)
            result = wait_for_dpad(joystick)
            dpad_results[direction] = result
            if result[0] == "button":
                print(f"  ✅ Button {result[1]}")
            elif result[0] == "hat":
                print(f"  ✅ Hat {result[1]} {result[2]}")
            time.sleep(0.3)

        # Determine dpad type
        dpad_types = set(r[0] for r in dpad_results.values())
        if "hat" in dpad_types and len(dpad_types) == 1:
            config["dpad_type"] = "hat"
            config["dpad"]["hat_index"] = dpad_results["UP"][1]
        else:
            config["dpad_type"] = "button"
            for direction, result in dpad_results.items():
                if result[0] == "button":
                    config["dpad"][direction] = result[1]
                else:
                    config["dpad"][direction] = -1  # fallback

        # --- Axes ---
        print("\n  ── 摇杆和扳机映射 ──\n")
        for prompt_text, axis_name, _ in INIT_AXIS_PROMPTS:
            print(f"  👉 请操作: {prompt_text}", end="", flush=True)
            axis_idx = wait_for_axis(joystick)
            config["axes"][axis_name] = axis_idx
            print(f"  ✅ Axis {axis_idx}")
            time.sleep(0.3)

        # Save
        with open(CONFIG_FILE, "w") as f:
            json.dump(config, f, indent=2, ensure_ascii=False)

        print(f"\n  ✅ 配置已保存到 {CONFIG_FILE}")
        print("  现在可以用 make run 启动了！\n")

    except KeyboardInterrupt:
        print("\n\n  ❌ 已取消初始化。\n")


def load_config():
    """Load saved config and apply to Btn/Axis classes. Returns config or None."""
    if not os.path.exists(CONFIG_FILE):
        return None
    try:
        with open(CONFIG_FILE) as f:
            config = json.load(f)

        # Apply button mapping
        for key_name, btn_idx in config.get("buttons", {}).items():
            setattr(Btn, key_name, btn_idx)

        # Apply axis mapping
        for axis_name, axis_idx in config.get("axes", {}).items():
            setattr(Axis, axis_name, axis_idx)

        Axis.TRIGGER_THRESHOLD = config.get("trigger_threshold", 0.3)
        return config
    except (json.JSONDecodeError, KeyError) as e:
        print(f"  ⚠️  配置文件损坏，忽略: {e}")
        return None


# ─── Identify Mode ────────────────────────────────────────────────

def identify_mode(joystick):
    """Interactive mode to identify button/axis mappings."""
    print("\n🔍 Controller Identify Mode")
    print("   Press buttons and move sticks to see their indices.")
    print("   Press Ctrl+C to exit.\n")

    try:
        while True:
            pygame.event.pump()
            for event in pygame.event.get():
                if event.type == pygame.JOYBUTTONDOWN:
                    print(f"   Button {event.button} pressed")
                elif event.type == pygame.JOYAXISMOTION:
                    if abs(event.value) > 0.3:
                        print(f"   Axis {event.axis} = {event.value:.2f}")
                elif event.type == pygame.JOYHATMOTION:
                    print(f"   Hat {event.hat} = {event.value}")
            time.sleep(0.016)
    except KeyboardInterrupt:
        print("\n   Done.")


# ─── Main Loop ────────────────────────────────────────────────────

def main():
    pygame.init()
    pygame.joystick.init()

    global loaded_config

    identify = "--identify" in sys.argv
    do_init = "--init" in sys.argv
    force_profile = None
    if "--ps5" in sys.argv:
        force_profile = "ps5"
    elif "--xbox" in sys.argv:
        force_profile = "xbox"

    print("""
  ╔═══════════════════════════════════════════════╗
  ║  🎮 Claude Code Gamepad Controller            ║
  ║                                               ║
  ║  A/✕=Enter  B/○=Ctrl+C  X/□=Accept  Y/△=Rej ║
  ║  D-pad=Navigate  LB/L1=Tab  RB/R1=Esc        ║
  ║  Click Stick=🎤 Voice  Start/Options=Presets  ║
  ║  LT/RT + Face=Quick Prompts                   ║
  ║                                               ║
  ║  --init      Interactive button calibration   ║
  ║  --identify  Check button mapping             ║
  ║  --ps5       Force PS5 DualSense profile      ║
  ║  --xbox      Force Xbox profile (default)     ║
  ╚═══════════════════════════════════════════════╝
    """)

    # Wait for controller
    print("  Waiting for controller...", end="", flush=True)
    joystick = None
    while joystick is None:
        pygame.joystick.quit()
        pygame.joystick.init()
        if pygame.joystick.get_count() > 0:
            joystick = pygame.joystick.Joystick(0)
            joystick.init()
        else:
            print(".", end="", flush=True)
            time.sleep(1)

    print(f"\n  ✅ Connected: {joystick.get_name()}")
    print(f"     Buttons: {joystick.get_numbuttons()}, "
          f"Axes: {joystick.get_numaxes()}, "
          f"Hats: {joystick.get_numhats()}")

    # --init: interactive calibration
    if do_init:
        init_mode(joystick)
        return

    # Try loading saved config first
    loaded_config = load_config()
    if loaded_config:
        print(f"  📂 已加载自定义配置: {CONFIG_FILE}")
        profile_source = "custom config"
    elif force_profile:
        profile = load_profile(force_profile)
        profile_source = "forced"
    else:
        detected = detect_profile(joystick.get_name())
        profile = load_profile(detected)
        profile_source = "auto-detected"

    init_quick_prompts()

    print(f"     Profile: {profile_source}")

    if not HAS_SPEECH:
        print("  ⚠️  Voice input disabled (missing faster-whisper/sounddevice)")
    print("\n  Ready! Focus your terminal with Claude Code.\n")

    notify("Connected", joystick.get_name())

    if identify:
        identify_mode(joystick)
        return

    try:
        while True:
            pygame.event.pump()

            for event in pygame.event.get():
                if event.type == pygame.JOYBUTTONDOWN:
                    on_button_down(event.button)
                elif event.type == pygame.JOYHATMOTION:
                    if event.hat == HAT_INDEX:
                        on_hat(*event.value)
                elif event.type == pygame.JOYDEVICEREMOVED:
                    osd("Controller disconnected! Waiting...")
                    notify("Disconnected", "Plug controller back in")
                    joystick = None
                    while joystick is None:
                        pygame.joystick.quit()
                        pygame.joystick.init()
                        if pygame.joystick.get_count() > 0:
                            joystick = pygame.joystick.Joystick(0)
                            joystick.init()
                            osd(f"Reconnected: {joystick.get_name()}")
                            notify("Reconnected", joystick.get_name())
                        else:
                            time.sleep(1)

            if joystick:
                handle_sticks(joystick)
                handle_triggers(joystick)

            time.sleep(POLL_INTERVAL)

    except KeyboardInterrupt:
        print("\n  👋 Bye!")
    finally:
        pygame.quit()


if __name__ == "__main__":
    main()
