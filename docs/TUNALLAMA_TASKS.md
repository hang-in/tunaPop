# tunaLlama Task Queue

These tasks are intentionally bounded so they can be delegated to tunaLlama and then reviewed locally.

## 1. Copy Response Button

Files:
- `Sources/TunaPop/PopupView.swift`

Requirements:
- Add a copy button in the popup header or response area.
- Copy the current response text to `NSPasteboard.general`.
- Disable the button when there is no response.
- Show a short copied confirmation.

Acceptance:
- `swift build` succeeds.
- Copying places the exact AI response on the system clipboard.
- The confirmation resets automatically.

## 2. Ollama Model Discovery

Files:
- `Sources/TunaPop/OllamaClient.swift`
- `Sources/TunaPop/SettingsView.swift`
- `Sources/TunaPop/AppSettings.swift`

Requirements:
- Fetch models from `GET /api/tags`.
- Show fetched model names in Settings.
- Keep manual model entry available when fetch fails.
- Persist the selected model.

Acceptance:
- Settings can load local Ollama model names.
- Existing manual model behavior still works.
- Network errors are visible but non-blocking.

## 3. Streaming Chat Responses

Files:
- `Sources/TunaPop/OllamaClient.swift`
- `Sources/TunaPop/PopupView.swift`

Requirements:
- Add a streaming `/api/chat` path using `stream: true`.
- Append response content incrementally.
- Cancel in-flight requests when a new action starts or the popup closes.

Acceptance:
- Responses render progressively.
- Dismissal cancels active work.
- Repeated actions do not interleave old text.

## 4. Popup Error Banner

Files:
- `Sources/TunaPop/PopupView.swift`
- `Sources/TunaPop/OllamaClient.swift`

Requirements:
- Show connection, timeout, non-200, and empty response errors in a compact banner.
- Allow dismissing the banner without closing the popup.
- Clear old errors on new requests.

Acceptance:
- Stopping Ollama produces a user-readable error.
- Retrying clears the previous error.

## 5. Permission And Event Diagnostics

Files:
- `Sources/TunaPop/Accessibility.swift`
- `Sources/TunaPop/SelectionMonitor.swift`
- `Sources/TunaPop/TunaPopApp.swift`
- `Sources/TunaPop/SettingsView.swift`

Requirements:
- Display Accessibility trust status.
- Surface event tap creation failure.
- Re-enable event tap after timeout.
- Add a small menu item or settings section for recent diagnostics.

Acceptance:
- Missing permissions are visible from the menu.
- Event tap failure is discoverable.
