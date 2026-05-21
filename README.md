# tunaPop

[한국어 문서 (Korean Version)](README.ko.md)

[![Build Status](https://github.com/hang-in/tunaPop/actions/workflows/build.yml/badge.svg)](https://github.com/hang-in/tunaPop/actions/workflows/build.yml)
[![Lint Status](https://github.com/hang-in/tunaPop/actions/workflows/lint.yml/badge.svg)](https://github.com/hang-in/tunaPop/actions/workflows/lint.yml)
[![Platform](https://img.shields.io/badge/platform-macOS_14.0+-black.svg?style=flat&logo=apple)](https://img.shields.io/badge/platform-macOS_14.0+-black.svg?style=flat&logo=apple)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg?style=flat&logo=swift)](https://img.shields.io/badge/Swift-5.9+-orange.svg?style=flat&logo=swift)
[![Homebrew](https://img.shields.io/badge/Homebrew-hang--in%2Ftap-orange.svg?style=flat&logo=homebrew)](https://github.com/hang-in/homebrew-tap)

tunaPop is a PopClip-style native macOS utility that helps you quickly perform AI-based actions and system tasks via a floating popup bar when selecting text on your screen.

## Key Features

- **Native UX**: Instantly detects text drag selections or double-clicks and displays an intuitive ActionBar popup right next to your cursor.
- **AI Actions**: Run pre-configured AI tasks (Summarize, Explain, Translate) with a single click, dynamically incorporating your text selection.
- **System Utilities**: Built-in support for 4 core system actions (Copy, Paste, Web Search, Dictionary Look-up) that execute locally without network overhead.
- **Action Customization**: Hide unused default actions, configure custom order, and easily reset to factory settings.
- **Custom Action Editor**: Create your own custom AI prompt or system actions with customized SF Symbols icons.
- **Provider Integrations**: Supports local Ollama endpoints (running on your machine for maximum privacy) as well as cloud API providers (Gemini, OpenAI, Anthropic).
- **Secure Token Storage**: Safely manages API keys and passwords using the native macOS Keychain.
- **Accessibility & Permissions**: Easy checking and requesting of macOS Accessibility permissions through the status bar and Settings window.

## Getting Started

### Requirements

- macOS 14.0 or later (Swift 5.9+, AppKit & SwiftUI)
- Local or remote Ollama server (default: http://localhost:11434) or API keys for other external provider integrations.

### Installation (OSS Build)

Since the app is built locally without signing, macOS Gatekeeper may block it upon first launch. Use one of the methods below to run it.

#### Method 1 (Homebrew - Recommended)
```bash
brew tap hang-in/tap
brew install --cask tunapop
```

#### Method 2 (Direct DMG)
1. Download `tunaPop-x.y.z.dmg` from the GitHub Releases page and mount it.
2. Drag `tunaPop.app` into your `/Applications` folder.
3. Remove the quarantine attribute so macOS allows the unsigned bundle to launch:
   ```bash
   xattr -dr com.apple.quarantine /Applications/tunaPop.app
   ```
   Alternatively, right-click `tunaPop.app` -> **Open** (first launch only), or go to
   **System Settings** -> **Privacy & Security** -> **Open Anyway**.

### Build and Run

You can build and run the application from the project root directory:

```bash
swift build
```

*Note: The application requires macOS Accessibility permissions to monitor mouse drags and automate text insertions.*

## Settings

Customize the app's behavior through the Settings Window:

- **Agent**: Pick your LLM provider, endpoint URL, model, and securely enter API keys (saved in Keychain).
- **Response Language**: Fix the output language for AI actions (Auto, English, Korean, Japanese, Chinese).
- **ActionBar**: Fine-tune the popup offset and positioning (8 directions).
- **Actions**: Customize, reorder, hide default actions, or create new custom actions.
- **Permissions**: Verify and easily request accessibility permissions.

## Architecture & Refactoring

tunaPop is written in Swift with a combination of AppKit window management and SwiftUI views. To keep the project clean, scalable, and stable, we recently completed a major architectural refactoring:

- **MVVM Architecture**: Separated user configuration logic, timer polling, and provider API model refreshing from the declaration of `SettingsView` into a newly established `SettingsViewModel`.
- **Decoupled LLM Task Runner**: Enhanced Single Responsibility Principle (SRP) by extracting async streaming LLM call coordination from `PopupController` into a dedicated `LLMTaskRunner`.
- **Unified SSE Stream Parser**: Replaced custom, redundant server-sent events parsing logic in each provider (`GeminiClient`, `OpenAIClient`, `OllamaClient`, `AnthropicClient`) with a single generic helper class `SSEStreamParser` to reconstruct byte chunk streams reliably.
