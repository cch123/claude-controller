# Claude Gamepad Controller

macOS 菜单栏应用，用游戏手柄控制 [Claude Code](https://claude.ai/claude-code)。躺在沙发上 vibe coding。

支持 Xbox、PS5 DualSense 及所有 MFi 兼容手柄。内置语音输入（Apple 系统语音识别 / 本地 [whisper.cpp](https://github.com/ggerganov/whisper.cpp)），可选 LLM 语音纠错。

## 功能

- **菜单栏常驻** - 后台运行，无 Dock 图标
- **即插即用** - 通过 `GCController` 自动识别 Xbox / PS5 / MFi 手柄
- **全按键自定义** - 每个按键可通过 GUI 设置面板配置
- **语音输入** - 按摇杆说话，转写结果粘贴到终端
  - 系统语音识别（零配置）
  - 本地 whisper.cpp（更高精度，离线可用）
  - 可选 LLM 纠错（Ollama / OpenAI 兼容接口）
- **快捷指令** - LT/RT + 功能键发送预设 prompt
- **预设菜单** - Start 键打开可用方向键导航的 prompt 列表
- **浮动 HUD** - 非侵入式悬浮层显示按键反馈和转写结果
- **原生 macOS** - 纯 Swift + AppKit，无 Electron，无 Python

## 默认按键映射

| 按键 | 动作 |
|------|------|
| A / x | Enter（确认） |
| B / ○ | Ctrl+C（中断） |
| X / □ | Accept（y + Enter） |
| Y / △ | Reject（n + Enter） |
| D-pad | 方向键 |
| LB / L1 | Tab（补全） |
| RB / R1 | Escape |
| L3 / R3 按下 | 语音输入 |
| Start / Menu | 预设菜单 |
| Select / View | `/clear` |
| LT + 功能键 | 快捷指令（可配置） |
| RT + 功能键 | 快捷指令（可配置） |
| LT + RT + Select | 退出 |

所有映射均可在设置中自定义。

## 截图

### 按键映射

按区域分组展示所有按键绑定，快速扫描和重新分配高频操作。

![Button Mapping](screenshots/button-mapping.png)

### 预设指令

在一个聚焦的工作区中编辑所有触发组合，支持预设和自定义 prompt，实时显示字符数和预览。

![Preset Prompts](screenshots/quick-prompts.png)

### 语音识别

一览语音管线全貌：引擎选择、二进制安装状态、模型下载情况、LLM 纠错开关。

![Speech Recognition](screenshots/speech-recognition.png)

### 菜单栏

应用常驻菜单栏，手柄连接时图标变绿。

![Menu Bar](screenshots/menu-bar.png)

## 安装

### 前置要求

- macOS 14.0 (Sonoma) 或更高版本
- 游戏手柄（Xbox、PS5 DualSense 或 MFi 兼容）
- Whisper 用户可选：`brew install whisper-cpp`

### 从源码构建

```bash
git clone https://github.com/xargin/claude-controller.git
cd claude-controller
swift build -c release
# 产物位于 .build/release/ClaudeGamepad
```

### 运行

```bash
swift run
```

或构建后复制到系统路径：

```bash
swift build -c release
cp .build/release/ClaudeGamepad /usr/local/bin/
```

## 首次启动

1. 运行 `swift run` 或构建好的二进制
2. 按提示授予**辅助功能**权限（系统设置 > 隐私与安全性 > 辅助功能）— 键盘模拟所需
3. 如使用语音输入，授予**语音识别**权限
4. 连接手柄 — 菜单栏图标变为激活状态
5. 将焦点切到运行 Claude Code 的终端
6. 开始按按钮！

## 配置

点击菜单栏图标 > **Settings** 打开设置窗口。设置面板采用深色主题卡片式布局，分为三个标签页。

### 按键映射

按区域展示所有按键绑定：Shoulders（肩键）、Face Buttons（功能键）、Navigation（方向键）、System & Sticks（系统键和摇杆）。每个按键可从下拉菜单选择动作。LT/RT 作为修饰键，对应的快捷指令在预设指令标签页管理。

### 预设指令

左侧列出所有快捷指令槽位（LT+A、LT+B、RT+A 等），右侧为聚焦编辑区。每个槽位可选择预设 prompt 或自定义文本，实时显示字符数和预览。

默认快捷指令：

| 触发 | Prompt |
|------|--------|
| LT + A | showtime |
| LT + B | fix the failing tests |
| LT + X | continue |
| LT + Y | undo the last change |
| RT + A | run the tests |
| RT + B | show me the diff |
| RT + X | looks good, commit this |
| RT + Y | add types and documentation |

### 语音识别

顶部 Voice Pipeline 状态栏一览引擎、二进制安装状态、模型下载情况和 LLM 纠错开关。下方分两个卡片：

- **Whisper Local** — 选择模型（tiny 75MB ~ large-v3 3.1GB）、一键安装二进制、一键下载模型
- **LLM Refinement** — 配置 API URL、API Key、模型名，支持 Ollama、LM Studio 或任何 OpenAI 兼容端点

## 语音输入流程

1. 按 **L3 / R3**（摇杆按下）
2. 浮动 HUD 显示 "Listening..."，带实时波形
3. 说出你的 prompt（自动检测中英文）
4. HUD 显示转写结果，`[A=确认 B=取消]`
5. 按 **A** 粘贴到终端，或 **B** 取消

## 架构

```
Sources/ClaudeGamepad/
  main.swift              # 入口，菜单栏应用启动
  AppDelegate.swift       # 状态栏图标、菜单、权限管理
  GamepadManager.swift    # GCController 输入处理 + 按键映射
  KeySimulator.swift      # CGEvent 键盘模拟
  SpeechEngine.swift      # Apple SFSpeechRecognizer 集成
  WhisperEngine.swift     # 本地 whisper.cpp CLI 集成
  LLMRefiner.swift        # 可选 LLM 语音后处理
  OverlayPanel.swift      # 浮动 HUD 面板 + 波形可视化
  ButtonMapping.swift     # 按键动作配置 + 持久化
  SpeechSettings.swift    # 语音/LLM 配置 + 持久化
  GamepadConfigView.swift # 可视化按键映射编辑器
  SettingsWindow.swift    # 深色主题卡片式设置窗口
```

## 许可证

MIT
