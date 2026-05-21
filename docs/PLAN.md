# TunaPop Plan

## Product Direction

TunaPop is a PopClip-style macOS utility that appears near selected content and runs local or hosted Ollama-compatible AI actions against text and images.

The product should feel like a system utility: fast, small, predictable, and keyboard friendly. The first milestone is not a full assistant. It is a reliable selection-to-popup loop.

## Milestone 1: Reliable Popup MVP

Goal: Selecting text in common macOS apps opens a dismissible popup and returns an Ollama response.

Scope:
- Global drag completion monitoring.
- Accessibility selected text extraction.
- Clipboard fallback that restores the previous pasteboard.
- Floating panel with loading, response, retry actions, Escape close, close button, and click-outside dismissal.
- Local Ollama `/api/chat` request with optional bearer token.
- Basic settings for endpoint, model, token, and default prompt.

Acceptance:
- `swift build` succeeds.
- Text selection in TextEdit and a browser can trigger the popup.
- Popup can be dismissed without quitting the app.
- Failed model requests show a readable error.

## Milestone 2: Diagnostics And Permissions

Goal: The user can tell why TunaPop is not triggering.

Scope:
- Menu item showing Accessibility/Input Monitoring status.
- Lightweight debug window or log panel for recent selection events.
- Explicit event tap status and re-enable on timeout.
- Clear messages for missing permissions and copy fallback failures.

Acceptance:
- Missing permissions are visible from the menu bar.
- Event tap failures are reported.
- Selection extraction failures leave inspectable recent state.

## Milestone 3: Ollama Provider UX

Goal: Local Ollama, Ollama Cloud, and compatible endpoints are easy to configure.

Scope:
- Endpoint validation.
- Model list discovery from `/api/tags` where available.
- Per-action model override.
- Token handling through Keychain instead of plain `UserDefaults`.
- Request timeout and cancel support.

Acceptance:
- User can switch between local and hosted endpoints without editing files.
- Bad endpoint/token/model errors are distinguishable.

## Milestone 4: Action System

Goal: User can define reusable AI actions similar to PopClip extensions.

Scope:
- Built-in actions: explain, summarize, translate, rewrite, code review.
- User-defined prompt templates.
- Selection placeholder support.
- Per-action visibility for text/image payloads.
- Persisted action order.

Acceptance:
- Adding a custom action requires no code change.
- Actions remain stable across app restarts.

## Milestone 5: Image And OCR

Goal: Image selections work with vision models and non-vision fallbacks.

Scope:
- Better image extraction from clipboard.
- Vision-model payload support.
- Optional OCR fallback for non-vision models.
- Image preview in popup.
- Payload size guardrails.

Acceptance:
- Screenshots or copied images can be analyzed with a vision model.
- Non-vision model paths fail gracefully or use OCR.

## Milestone 6: Packaging

Goal: TunaPop can be installed and run like a normal macOS app.

Scope:
- Xcode app target or SwiftPM-compatible app bundling.
- App icon and menu bar icon.
- Hardened runtime and entitlement review.
- Signed/notarized build path.
- First-run onboarding for permissions.

Acceptance:
- A `.app` bundle launches from Finder.
- Permissions are requested in a user-facing flow.

## tunaLlama Delegation Policy

Use tunaLlama for bounded implementation tasks:
- file-level refactors,
- SwiftUI/AppKit component generation,
- focused test or diagnostic helpers,
- review of specific files.

Keep local ownership for:
- product architecture,
- macOS permission model decisions,
- final integration and build verification,
- user-facing tradeoff decisions.

Each delegated task should include current file paths, relevant constraints, and expected acceptance checks.
