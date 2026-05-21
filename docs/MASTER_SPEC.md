# tunaPop — Production Master Specification

> Single source of truth for what tunaPop is, how it works, and what it
> needs to be ready for production distribution. Use this document as the
> top-level reference. Individual `docs/tasks/phase-N.md` files are
> derived implementation plans. The Roadmap section at the bottom tracks
> which phases are complete, in-flight, or planned.

---

## Document conventions

- "MUST", "SHOULD", "MAY" follow RFC 2119.
- File paths are repo-relative.
- `TBD` marks an open decision that needs an owner and a deadline.
- `→ Phase N` references the roadmap entry that delivers this item.

---

## 0. Glossary

- **Selection**: text or image captured from another macOS app via macOS
  Accessibility API or pasteboard fallback.
- **Action**: a named LLM intent (e.g. 설명, 요약, 번역) with a prompt
  template and SF Symbol icon.
- **ActionBar**: small floating icon bar shown near the selection.
- **ResponsePanel**: floating panel anchored to the ActionBar showing the
  LLM response.
- **Anchor**: top-left corner orientation of the ResponsePanel relative
  to the ActionBar (`.top` grows downward; `.bottom` grows upward).
- **Hot zone**: optional rectangle on screen where selection capture is
  enabled. Out of scope for v1.

---

## 1. Product Overview

### 1.1 Vision

A local-first, PopClip-style assistant for macOS that runs Ollama (and
later other providers) on the user's machine. The user drags or
double-clicks a word, picks an icon, and gets a quick AI response in a
floating panel — without sending data to a cloud unless they explicitly
configure a cloud endpoint.

### 1.2 Target users

- macOS power users who already run Ollama locally.
- Engineers, writers, students who want one-keystroke AI explain /
  summarize / translate on any text.
- Privacy-sensitive users who do not want their selection text leaving
  the device.

### 1.3 Core user journeys

1. **First-run setup**: install, grant Accessibility + Input Monitoring,
   pick a local Ollama model, see a working test selection.
2. **Drag-select → explain**: drag-select text in Safari, see ActionBar
   near the selection, click 설명, read the response in ResponsePanel,
   copy it, dismiss with ESC.
3. **Double-click → translate**: double-click a word, ActionBar appears,
   click 번역, ResponsePanel shows the translation.
4. **Pin a long response**: click 요약, click the pin icon, switch to
   another app to compose a message while the panel stays visible.
5. **Configure custom action**: open Settings → Actions → add an action
   "한국어 정중하게 다시 써줘" with custom prompt and icon.
6. **Switch model**: open Settings, see live list of local Ollama models,
   switch from `gemma4:e2b` to `qwen3.5:9b`, run the next action against
   the new model.

### 1.4 Key differentiators

- **Local by default** (Ollama). No cloud key required to use.
- **Native macOS** (Swift + AppKit + SwiftUI). No Electron.
- **PopClip-style ergonomics** but with first-class LLM action templates.
- **Open source** (license: `TBD`, MIT recommended).

### 1.5 Success metrics

- Crash-free sessions ≥ 99.5% over rolling 7-day window.
- ActionBar shown ≤ 250 ms after `mouseUp` in AX-supported apps.
- 7-day retention ≥ 30% on installed users (vanity, opt-in telemetry
  only — see §8).

### 1.6 Non-goals (v1)

- Mobile / iPad parity.
- Multi-account / team sync.
- Plugin marketplace (post-v1).
- Image generation (text in / text out only for v1; image-in payload is
  passed through `OllamaClient.chat` but UI is text-only).
- Voice input / TTS output.

---

## 2. System Architecture

### 2.1 High-level components

```
┌─────────────────────────────────────────────────────────────┐
│                          AppDelegate                         │
│   - status item, menu, accessibility request, settings win   │
└──────────┬──────────────────────────────────┬───────────────┘
           │                                  │
           ▼                                  ▼
   ┌──────────────────┐               ┌──────────────────┐
   │ SelectionMonitor │               │ PopupController  │
   │ (NSEvent global) │ ── payload ─▶ │ (orchestrator)   │
   └──────────────────┘               └──────┬───────────┘
                                             │
                         ┌───────────────────┼───────────────────┐
                         ▼                   ▼                   ▼
                ┌────────────────┐  ┌────────────────┐  ┌────────────────┐
                │ ActionBarPanel │  │ ResponsePanel  │  │ LLMTaskRunner  │
                │  + SwiftUI     │  │  + SwiftUI     │  └───────┬────────┘
                └────────────────┘  └────────────────┘          │
                         ▲                   ▲                  ▼
                         └───── shared ──────┘          ┌────────────────┐
                         KeyableNonActivatingPanel      │  LLMClient(s)  │
                         (NSPanel subclass: ESC)        │(Ollama, Gemini)│
                                                        └───────┬────────┘
                                                                ▼
                                                        ┌────────────────┐
                                                        │SSEStreamParser │
                                                        └────────────────┘
```

### 2.2 Module list

| Module | Path | Responsibility |
|---|---|---|
| `TunaPopApp` | `Sources/TunaPop/TunaPopApp.swift` | `App` entry. Hosts `AppDelegate`. Empty `Settings { EmptyView() }` scene with `.appSettings` command group replaced. |
| `AppDelegate` | same file | Activation policy, status item, settings window, `PopupController` ownership. |
| `SelectionMonitor` | `Sources/TunaPop/SelectionMonitor.swift` | Global mouse monitor → drag/double-click triggers → `SelectionExtractor` → callback. |
| `SelectionExtractor` | `Sources/TunaPop/SelectionExtractor.swift` | AX `kAXSelectedTextAttribute`. Pasteboard fallback guarded by `IOHIDCheckAccess`. |
| `SelectionPayload` | `Sources/TunaPop/SelectionPayload.swift` | `.text(String) \| .image(NSImage)` enum + image PNG base64. |
| `Accessibility` | `Sources/TunaPop/Accessibility.swift` | `AXIsProcessTrustedWithOptions` request / check. |
| `Action` | `Sources/TunaPop/Action.swift` | `id`, `label`, `prompt`, `systemImage`. `defaults`. |
| `ActionBarPosition` | `Sources/TunaPop/ActionBarPosition.swift` | 8-direction enum + clamp-to-visibleFrame origin. |
| `ActionBarPanel` | `Sources/TunaPop/ActionBarPanel.swift` | NSPanel wrapper + SwiftUI hosting, hover callback, frame exposure. |
| `ActionBarView` | `Sources/TunaPop/ActionBarView.swift` | SwiftUI icons row, `.onHover`. |
| `TooltipImageButton` | `Sources/TunaPop/TooltipImageButton.swift` | `NSViewRepresentable` `NSButton` with `toolTip` + `NSTrackingArea`. |
| `KeyableNonActivatingPanel` | `Sources/TunaPop/KeyableNonActivatingPanel.swift` | `NSPanel` subclass: `canBecomeKey = true`, `cancelOperation` → `onEscapePressed`. |
| `ResponsePanel` | `Sources/TunaPop/ResponsePanel.swift` | NSPanel wrapper, anchor mode, hover/pin, fade animation, `.frame`. |
| `ResponseView` | `Sources/TunaPop/ResponseView.swift` | SwiftUI body for the four `ResponseState` cases. Copy + pin buttons. |
| `ResponseState` | `Sources/TunaPop/ResponseState.swift` | `idle \| loading \| success(String) \| failure(String)`. |
| `PopupController` | `Sources/TunaPop/PopupController.swift` | Orchestrator. Owns both panels, delegates LLM tasks to `LLMTaskRunner`, coordinates ESC + hover-out + outside-click + pin. `NSWindowDelegate`. |
| `LLMTaskRunner` | `Sources/TunaPop/LLMTaskRunner.swift` | Coordinates LLM API calls, handles text response streaming, updates the ResponsePanel state, and handles client errors. |
| `LLMClient` | `Sources/TunaPop/LLMClient.swift` | Unified protocol for LLM API providers (`OllamaClient`, `GeminiClient`, `OpenAIClient`, `AnthropicClient`). |
| `SSEStreamParser` | `Sources/TunaPop/SSEStreamParser.swift` | Utility class to handle server-sent events (SSE) chunk streaming and line reconstruction. |
| `AppSettings` | `Sources/TunaPop/AppSettings.swift` | `@Published` settings backed by `UserDefaults`. |
| `SettingsView` | `Sources/TunaPop/SettingsView.swift` | Hosted in `NSWindow` from AppDelegate. Renders user configurations, bound to `SettingsViewModel`. |
| `SettingsViewModel` | `Sources/TunaPop/SettingsViewModel.swift` | Decouples business logic from `SettingsView`. Manages provider logic, model list loading, and keychain API token bindings. |

### 2.3 Data flow

```
NSEvent mouseUp / dblclick
        │
        ▼
SelectionMonitor.triggerSelection()
        │  (await 120 ms)
        ▼
SelectionExtractor.currentSelection()
   ├─ AX trusted? → AX text → SelectionPayload
   ├─ Input Monitoring trusted? → pasteboard fallback → SelectionPayload
   └─ neither → nil
        │
        ▼ (non-nil)
PopupController.show(payload, anchor)
        │
        ▼
ActionBarPanel.show(actions, anchor, position)
        │
        ▼ (user clicks icon)
PopupController.handleAction(action)
        │
        ▼
ResponsePanel.show + .update(.loading)
        │
        ▼
LLMTaskRunner.run(action, payload, settings)
   ├─ LLMClientFactory.makeClient(settings.provider)
   ├─ Client.send(prompt, payload) → Stream of Chunks
   ├─ SSEStreamParser reconstructs SSE text chunks
   └─ responsePanel.update(.success(accumulatedText)) / .failure(message)
        │
        ▼ (user dismisses)
PopupController.dismiss()
   └─ cancel LLMTaskRunner task, dismiss bars, clear state
```

### 2.4 Lifecycle states

- **Idle**: no panels visible. Selection monitor armed.
- **ActionBarVisible**: action bar up; no response yet.
- **Loading**: response panel up; LLM call in flight. **Dismiss
  suppressed** on outside click + hover-out.
- **ShowingResponse**: response panel rendering `.success` /
  `.failure`. Dismiss enabled on outside click + ESC + hover-out.
- **Pinned**: pin true. Hover-out and outside-click suppressed. ESC
  still dismisses.

Invariants:

- `currentTask` MUST be cancelled before re-entering `Loading`.
- `hideTimer` MUST be cancelled when entering `Loading` or `Pinned`.
- `lastPayload` MUST be cleared in `dismiss()`.
- Event monitors / `NSWindowDelegate` MUST be torn down on `dismiss()`.

### 2.5 Threading model

- All AppKit / SwiftUI mutation paths are `@MainActor`.
- Network call goes through `URLSession.shared.data(for:)` on a
  Task. The Task is constructed `@MainActor` and only mutates
  `responsePanel` after `await`. Concurrency-safe Sendable boundaries
  use `@Sendable` closures or value-typed payload copies.
- No `DispatchQueue.global` use anywhere in the app's own code.

### 2.6 Dependency injection

- `AppSettings` is the single configuration object. Constructed in
  `AppDelegate`. Passed to `PopupController.init` and `SettingsView`.
- `LLMTaskRunner` is constructed inside `PopupController` and triggers client executions dynamically.
- No global singletons except `NSApp` / `NSPasteboard.general`.

---

## 3. Functional Requirements

### 3.1 Selection capture

- **Drag**: leftMouseDown → leftMouseDragged distance > 6 px → leftMouseUp
  → 120 ms delay → extractor.
- **Double-click**: leftMouseDown with `clickCount == 2` → 120 ms delay
  → extractor. If extractor returns nil, no ActionBar.
- **Triple-click**: `TBD`. Not required for v1.
- **Selection must be non-blank** after trimming whitespace + newlines.

### 3.2 Action invocation

- v1 actions are hard-coded in `Action.defaults`:
  - `설명` → `Explain this selection clearly and concisely.`
  - `요약` → `Summarize this selection in three bullets.`
  - `번역` → `Translate this selection into Korean. Keep meaning and tone.`
- Clicking an icon MUST keep the ActionBar visible. ActionBar dismisses
  only on outside click, ESC, hover-out (with timer), or new selection.
- ActionBar MUST stay above the ResponsePanel in z-order via
  `actionBarPanel.bringToFront()` after `responsePanel.show`.

### 3.3 LLM call

- POST `endpoint + /api/chat`.
- `stream: false` (v1).
- `messages: [{role: user, content: "{prompt}\n\nSelection:\n{text}"}]`
  for text payloads.
- `messages: [{role: user, content: "{prompt}", images: ["{base64}"]}]`
  for image payloads.
- Optional `Authorization: Bearer {token}` if token non-empty.
- Response: `decode(OllamaChatResponse).message.content`.
- Timeout: `URLSession` default. `TBD` whether to enforce 30 s.

### 3.4 Response display

- ResponsePanel renders one of:
  - `.idle` — empty view.
  - `.loading` — `ProgressView` + `"…"`.
  - `.success(text)` — `ScrollView` with `Text(text).textSelection(.enabled)`,
    `minHeight: 60, maxHeight: 280`.
  - `.failure(message)` — red text.
- Copy button copies `lastResponse` to `NSPasteboard.general`, shows
  `checkmark.circle.fill` for 1.5 s.
- Pin button toggles `isPinned`. While pinned, hover-out timer never
  fires and outside-click is suppressed.

### 3.5 Settings (v1)

| Field | Storage | UI |
|---|---|---|
| `endpoint` | UserDefaults `endpoint` | text field |
| `model` | UserDefaults `model` | text field (live picker → Phase 5) |
| `apiToken` | Keychain (→ Phase 6) / UserDefaults v1 | secure field |
| `defaultPrompt` | UserDefaults `defaultPrompt` | multi-line |
| `actionBarPosition` | UserDefaults `actionBarPosition` | hidden v1 (picker → Phase 5) |
| custom actions | `TBD` (→ Phase 7) | editor (→ Phase 7) |

### 3.6 Onboarding (`→ Phase 8`)

- First launch detection.
- Welcome window with three steps: Accessibility, Input Monitoring,
  Model setup.
- "Test this now" button that triggers a synthetic selection demo.

### 3.7 Menu bar

- Status icon: SF Symbol `sparkles`, template, accessibilityDescription
  `"tunaPop"`.
- Items:
  - **Show Test Popup** (`t`) — spawn ActionBar at mouse with dummy
    text.
  - **Enable / Disable Selection Monitor** (`m`) — toggle the global
    NSEvent monitor.
  - **Settings...** — open the dedicated settings window.
  - **Check Accessibility** (`a`) — re-prompt AX.
  - **Quit** (`q`).

### 3.8 Error / empty states

- Ollama unreachable → `.failure("Could not connect to Ollama at <endpoint>")`.
- Model not found → `.failure("Model '<name>' not found. Pull it with `ollama pull <name>`")`.
- 401 / token invalid → `.failure("Authentication failed")`.
- Empty response → `.failure("Model returned no text")`.
- Permission missing → no ActionBar; status menu shows a red dot.
  (`→ Phase 6`)

---

## 4. Non-functional Requirements

### 4.1 Performance budgets

| Metric | Target | Reason |
|---|---|---|
| Cold launch (mainline → status item visible) | < 300 ms | feels instant |
| ActionBar render (mouseUp → panel orderFront) | < 250 ms | excluding the 120 ms extractor delay |
| ResponsePanel render (icon click → loading visible) | < 50 ms | excluding LLM |
| LLM call (Ollama local, 7B Q4, ~50 token reply) | < 2 s p50, < 6 s p95 | model-dependent |
| Idle memory | < 80 MB | accessory app |
| CPU idle | < 1% | event monitors are cheap |

### 4.2 Stability

- Crash-free session rate ≥ 99.5%.
- All known `SIGSEGV` paths (CGEvent.post without Input Monitoring;
  AXUIElement calls without AX) gated by permission checks.
- `URLError(.cancelled)` and `CancellationError` MUST be silent.

### 4.3 Privacy

- No third-party telemetry by default.
- Selection text leaves the device only when the user has configured a
  non-localhost endpoint. v1 default endpoint is
  `http://localhost:11434` (loopback).
- API token, when set, is stored in Keychain (`→ Phase 6`).

### 4.4 Security

- Bundle is sandboxed `TBD` — distribution path needs to choose between
  Hardened Runtime + outside-MAS or Sandbox + MAS. v1 recommendation:
  Hardened Runtime + notarization, no sandbox, outside-MAS, signed
  Developer ID.
- Privacy descriptions in `Info.plist`:
  - `NSAppleEventsUsageDescription` (for AX events)
  - `NSAccessibilityUsageDescription`
  - `NSInputMonitoringUsageDescription` (`→ Phase 6`)

### 4.5 Accessibility (of tunaPop's own UI)

- All icon-only buttons MUST have `accessibilityDescription` set to
  the Korean label.
- VoiceOver should announce ActionBar items as "설명 버튼" etc.
- Color contrast: `.ultraThinMaterial` is acceptable for sighted use
  but `TBD` whether a high-contrast theme is required.

### 4.6 Internationalization

- v1 ships **ko + en** localizable strings (`→ Phase 9`).
- Default action prompts in `Action.defaults` are English. UI labels
  are Korean. Tooltip uses Korean label.
- String catalog: `Localizable.xcstrings` (Xcode 15+ format).

---

## 5. Privacy & Permissions

### 5.1 Permission matrix

| Permission | Why | API | Without it |
|---|---|---|---|
| Accessibility | `AXUIElementCopyAttributeValue` for `kAXFocusedUIElementAttribute` + `kAXSelectedTextAttribute` | `AXIsProcessTrustedWithOptions` | No selection capture at all |
| Input Monitoring | `CGEvent.post(.cghidEventTap)` for the Cmd+C fallback | `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` | Pasteboard fallback skipped; AX-only apps work, others don't |
| Apple Events | reserved (`→ Phase 11` if AppleScript fallback added) | `NSAppleEventsUsageDescription` Info.plist | n/a v1 |
| Screen Recording | none in v1 | n/a | n/a |

### 5.2 Request flow

- On first launch, `Accessibility.requestIfNeeded()` runs at
  `applicationDidFinishLaunching`. Modal system prompt shown by macOS.
- Input Monitoring is NOT auto-requested. Status menu has a "Grant
  Input Monitoring..." item (`→ Phase 6`) that calls
  `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)`.
- Settings window's Permissions tab shows live status of both
  permissions with "Open System Settings" links.

### 5.3 Privacy manifest (`PrivacyInfo.xcprivacy`) (`→ Phase 12`)

- `NSPrivacyTracking` = false.
- `NSPrivacyTrackingDomains` = empty.
- `NSPrivacyAccessedAPITypes` lists required reason API usage (UserDefaults).

### 5.4 Data flow

- Selection text → local `OllamaClient` → `endpoint` (default
  `http://localhost:11434`).
- If the user sets a remote endpoint, selection text leaves the device.
  Settings UI MUST display a warning when endpoint is non-localhost
  (`→ Phase 6`).
- No telemetry by default. Opt-in diagnostic mode writes verbose logs
  to `~/Library/Logs/tunaPop/` (`→ Phase 10`).

---

## 6. Error Handling & Resilience

### 6.1 Network

| Failure | Detection | UI |
|---|---|---|
| Cannot resolve host | `URLError.cannotFindHost` | `.failure("Could not connect to Ollama at <endpoint>")` |
| Connection refused | `URLError.cannotConnectToHost` | same as above |
| Timeout | `URLError.timedOut` | `.failure("Ollama timed out")` |
| 404 model | HTTP 404 body contains `"model not found"` | `.failure("Model '<name>' not found")` |
| 401 / 403 | HTTP 401/403 | `.failure("Authentication failed")` |
| 5xx | HTTP 500–599 | `.failure(body excerpt)` |
| Empty body | content empty | `.failure("Model returned no text")` |

`URLError(.cancelled)` and `CancellationError` MUST be silent.

### 6.2 Permission revoked at runtime

- AX permission revoked: `AXIsProcessTrusted()` returns false next call.
  `SelectionExtractor.currentSelection()` returns nil. ActionBar simply
  stops appearing. Status menu's "Selection monitor" state should
  reflect this (`→ Phase 6`).
- Input Monitoring revoked: `IOHIDCheckAccess` returns non-granted.
  Pasteboard fallback skipped (no crash).

### 6.3 Crash recovery

- v1 has no persistent in-memory state to recover. Settings are in
  UserDefaults. The app simply restarts.

### 6.4 Resource cleanup

- `SelectionMonitor.stop()` removes the NSEvent monitor.
- `PopupController.dismiss()` cancels the LLM Task, cancels hideTimer,
  dismisses both panels (response with fade), clears `lastPayload`
  and `lastResponse`.
- `ResponsePanel.dismiss[Animated]` resets `alphaValue = 1.0` so a
  subsequent `show` is opaque.

---

## 7. Testing Strategy

### 7.1 Unit tests (`→ Phase 13`)

- `ActionBarPosition.origin(forAnchor:barSize:)` — 8 directions × edge
  clamping.
- `Action.defaults` — id stability.
- `AppSettings` round-trip through UserDefaults.
- `OllamaClient.chat` against a stubbed `URLSession` (URLProtocol).
- `ResponseState` equality.

### 7.2 Integration tests (`→ Phase 13`)

- Launch the app in a UI test target. Invoke `Show Test Popup`. Click
  each action. Stub `OllamaClient` to return a canned response. Verify
  `ResponsePanel` text matches.

### 7.3 UI snapshot tests (`→ Phase 13`)

- `ActionBarView` with 3 / 4 / 5 actions.
- `ResponseView` for `.loading`, `.success`, `.failure`, pinned, unpinned.

### 7.4 Manual test matrix (run before every release)

| Scenario | Pass criteria |
|---|---|
| Drag-select in TextEdit | ActionBar appears within 250 ms |
| Drag-select in Safari main body | same |
| Drag-select in Firefox | only with Input Monitoring granted |
| Drag-select in iTerm2 | only with Input Monitoring granted |
| Double-click a word | ActionBar appears if AX returns text |
| Double-click empty space | NO crash, NO ActionBar |
| Click action → see loading → see response | < 2 s for short prompts |
| Click another action mid-response | new loading, no "canceled" text |
| Outside click during loading | panels stay |
| Outside click after response | panels fade out |
| ESC during loading | panels fade out, task cancelled |
| Hover both panels for 5 s | panels stay |
| Move mouse away for 1 s | panels fade out (unless pinned) |
| Pin → outside click | panels stay |
| Pin → ESC | panels fade out |
| Copy button | clipboard contains response |
| Settings opens | window shown, no twin |
| Permissions revoked mid-session | no crash, ActionBar stops appearing |

### 7.5 CI test runs

- GitHub Actions matrix: macOS 14, 15, 26 (`→ Phase 14`).
- `swift build` + `swift test` on each.
- SwiftLint + SwiftFormat (`→ Phase 14`).

---

## 8. Telemetry & Observability

### 8.1 Logging

- All diagnostic logs go through `NSLog` with prefix `tunaPop` (current
  state).
- Migrate to `os_log` with subsystem `app.tunapop` and per-area
  categories: `selection`, `popup`, `network`, `permissions`
  (`→ Phase 10`).
- Two log levels by default: `.info` (lifecycle) and `.error`.
  `.debug` only when diagnostic mode is on.

### 8.2 Diagnostic mode

- Settings → Advanced → "Verbose logging" toggle (`→ Phase 10`).
- When on, writes to `~/Library/Logs/tunaPop/tunaPop.log` with rotation.

### 8.3 Crash reports

- Apple's CrashReporter only (no Sentry / Bugsnag in v1).
- An "Open Crash Logs" menu item that opens `~/Library/Logs/DiagnosticReports`
  filtered to `tunaPop*` (`→ Phase 10`).

---

## 9. Build, Deploy, Distribute

### 9.1 Code signing

- Developer ID Application certificate.
- Hardened Runtime entitlements:
  - `com.apple.security.cs.allow-jit` — NOT required.
  - `com.apple.security.automation.apple-events` — `TBD` (only if
    AppleScript fallback ever added).
- No App Sandbox in v1 (would conflict with global event monitoring).

### 9.2 Notarization

- `xcrun notarytool submit ... --wait`.
- Staple ticket to the `.app` and `.dmg`.

### 9.3 Auto-update (`→ Phase 15`)

- Sparkle 2.x. EdDSA-signed appcast.
- Update channel hosted at `tunapop.app/appcast.xml` (`TBD` hostname).

### 9.4 Distribution

- v1: signed + notarized DMG from GitHub Releases.
- v1.x: same + Homebrew Cask (`→ Phase 15`).
- vNext: App Store (`TBD`; requires sandboxing rework).

### 9.5 Versioning

- Semver. `MAJOR.MINOR.PATCH`.
- `CFBundleShortVersionString` and `CFBundleVersion` (build) bumped
  in CI on tag (`→ Phase 14`).

---

## 10. CI / CD (`→ Phase 14`)

### 10.1 GitHub Actions

- `build.yml`: on push and PR, run `swift build` + `swift test` on
  macos-14 and macos-latest.
- `lint.yml`: SwiftLint + SwiftFormat dry-run.
- `release.yml`: on tag `v*`, build release config, sign, notarize,
  staple, attach DMG to release.

### 10.2 Lint / format

- SwiftLint with rules `TBD` — start with default + opt-in
  `force_unwrapping`.
- SwiftFormat with project config (no semicolons, 4-space, k&r braces).
- Pre-commit hook calls both.

### 10.3 Branch policy

- `main` is always green.
- Feature work on `feature/*` branches with PR review.

---

## 11. Documentation

### 11.1 User-facing

- `README.md` (English).
- `README_KO.md` (Korean).
- User guide hosted at `tunapop.app/docs` (`TBD`).

### 11.2 Developer-facing

- `docs/MASTER_SPEC.md` (this document).
- `docs/PLAN.md` — current phased plan summary.
- `docs/tasks/phase-N.md` — per-phase implementation specs (this is the
  unit Gemini works on).
- `HANDOFF.md` — short-lived session handoff doc.
- ADRs in `docs/adr/NNNN-title.md` (`→ Phase 13`).

---

## 12. LLM Integration

### 12.1 Current surface

- `POST /api/chat` non-streaming. `messages` list with one user message.

### 12.2 Streaming (`→ Phase 16`)

- `stream: true`. Append tokens to `lastResponse` and call
  `responsePanel.update(state: .success(running))` on each chunk.
- Cancel-safe: when the Task is cancelled, the URLSession data task is
  cancelled.

### 12.3 Model discovery (`→ Phase 5`)

- `GET /api/tags` on Settings open + on "Refresh" tap.
- Populate `model` field as a `Picker`. Free-text entry still allowed
  (for not-yet-pulled models).
- Cache the list for 60 s.

### 12.4 Multi-provider (`→ Phase 17`)

- Add `ProviderKind` enum: `ollama | openai | anthropic | gemini`.
- Abstract `LLMClient` protocol with a `chat(model:prompt:payload:)`.
- Settings tab "Providers" lets the user add accounts.

### 12.5 Prompt strategy

- Default actions use plain English instructions; the Korean response
  is requested in 번역 only.
- v1 does NOT use system prompts. `TBD` whether to add one
  ("You are a concise assistant for tunaPop").

### 12.6 Token / cost (`→ Phase 17`)

- Opt-in. Display token count on response when available.

---

## 13. Action System

### 13.1 Built-ins (v1)

- 설명, 요약, 번역 in `Action.defaults`.

### 13.2 Custom actions (`→ Phase 7`)

- Settings → Actions tab. Add / remove / reorder.
- Per-action fields: id (auto), label (Korean+English), prompt
  template, SF Symbol picker.
- Persist as JSON in UserDefaults under key `customActions`.

### 13.3 Prompt template variables (`→ Phase 7`)

- `{selection}` — selection text.
- `{language}` — system locale identifier.
- `{appBundleID}` — frontmost app's bundle identifier.

### 13.4 Plugin manifests (post-v1, `→ Phase 19`)

- YAML file in `~/Library/Application Support/tunaPop/plugins/`.
- Schema inspired by Xpop / PopClip but minimal: name, icon, prompt,
  enabled flag.

---

## 14. UI / UX

### 14.1 ActionBar

- Layout: horizontal pill, icons-only, 30×30 pt buttons, 2 pt spacing,
  `.padding(.horizontal: 4, .vertical: 3)`.
- Material: `.ultraThinMaterial`, corner radius 10, 0.5 pt stroke
  `Color.primary.opacity(0.08)`.
- Tooltip: native macOS via `NSButton.toolTip` + explicit
  `NSTrackingArea` with `.activeAlways`.
- Position: 8-direction enum, default `.topRight`, clamped to
  `NSScreen.main?.visibleFrame`.
- Hover: `.onHover` SwiftUI modifier reports back through
  `ActionBarPanel.setHoverHandler`.
- Z-order: `bringToFront()` called after every `ResponsePanel.show`.

### 14.2 ResponsePanel

- Width: 360 pt fixed.
- Height: content-driven, ScrollView `minHeight 60, maxHeight 280`.
- Material: `.ultraThinMaterial`, corner radius 12, 0.5 pt stroke.
- Header: `tunaPop` caption (secondary), spacer, pin button, copy button.
- Pin icon: `pin` / `pin.fill` (filled = pinned, accent color).
- Copy icon: `doc.on.doc` / `checkmark.circle.fill` (green for 1.5 s).
- States rendered:
  - `.idle` → empty body.
  - `.loading` → `ProgressView()` + `Text("…")`.
  - `.success(text)` → `ScrollView` with `Text(text).textSelection(.enabled)`.
  - `.failure(message)` → red `Text`.
- Anchor: `.top` grows downward (default), `.bottom` grows upward
  (when there is no room below).
- Drag-to-move: `isMovableByWindowBackground = true`.
- Auto-hide: 1.0 s after mouse leaves both panels (suppressed by pin and loading).
- Fade dismiss: 0.3 s ease-in-out alphaValue → 0, then `orderOut`.

### 14.3 Settings window

- Tabs (`→ Phase 5/6/7`):
  - **General**: endpoint, model picker, default prompt, API token field.
  - **Actions**: list editor for custom actions.
  - **Position**: 8-direction picker.
  - **Permissions**: status of AX + Input Monitoring + jump links.
  - **About**: version, license, links.
- Window: `NSWindow(title: "tunaPop Settings", styleMask: [.titled, .closable, .resizable])`. Owned by `AppDelegate`. `isReleasedWhenClosed = false`.

### 14.4 Menu bar

- See §3.7.

### 14.5 Onboarding (`→ Phase 8`)

- First-launch detection via `UserDefaults.standard.bool(forKey: "didCompleteOnboarding")`.
- 3-step modal:
  1. Permissions (AX + Input Monitoring with "Open System Settings" buttons).
  2. Model setup (auto-discovery + "Pull `gemma4:e2b`" button that runs `ollama pull` via `Process`).
  3. "Try it now" demo selection.
- "Skip" allowed; "Done" sets the flag.

---

## 15. Persistence

### 15.1 UserDefaults schema

| Key | Type | Default | Notes |
|---|---|---|---|
| `endpoint` | String | `http://localhost:11434` | |
| `model` | String | `""` | empty triggers discovery picker (`→ Phase 5`) |
| `apiToken` | String | `""` | Move to Keychain `→ Phase 6` |
| `defaultPrompt` | String | `Explain this selection clearly and concisely.` | |
| `actionBarPosition` | String (rawValue) | `topRight` | |
| `customActions` | Data (JSON) | `nil` | `→ Phase 7` |
| `didCompleteOnboarding` | Bool | `false` | `→ Phase 8` |
| `verboseLogging` | Bool | `false` | `→ Phase 10` |
| `lastUpdateCheck` | Date | nil | `→ Phase 15` |
| `SUEnableAutomaticChecks` | Bool | true | Sparkle automatic update checks toggle |
| `SULastCheckTime` | Date | nil | Sparkle last check date |
| `SUHasLaunchedBefore` | Bool | false | Sparkle launch detection |

### 15.2 Keychain (`→ Phase 6`)

- Service: `app.tunapop.token`.
- Account: provider name (`ollama`, `openai`, ...).

### 15.3 Migration

- v1.x → v1.y: settings additive only, no destructive rename.
- Major version: `AppSettings.migrate()` runs at init.

---

## 16. Concurrency & Memory

### 16.1 @MainActor

- All classes that touch AppKit / SwiftUI mutation are `@MainActor`:
  `AppDelegate`, `SelectionMonitor`, `SelectionExtractor`,
  `ActionBarPanel`, `ResponsePanel`, `PopupController`, `AppSettings`.

### 16.2 Sendable

- `SelectionPayload` is `@unchecked Sendable`. Image case uses
  `NSImage`; consumers must copy off the main actor only via pasteboard
  helpers — current code already does this.
- `Action` is `Sendable` (struct of value types).

### 16.3 Task cancellation

- One `currentTask` at a time in `PopupController`. Cancelled in
  `dismiss()`, `show()`, and at the top of `handleAction()`.
- `URLSession.shared.data(for:)` honors task cancellation.

### 16.4 Event monitors

- Phase 4 replaced global / local NSEvent monitors with:
  - SwiftUI `.onHover` for hover detection (no global mouseMoved
    monitor).
  - `KeyableNonActivatingPanel.cancelOperation` for ESC.
  - `NSWindowDelegate.windowDidResignKey` for outside-click dismissal.
- SelectionMonitor's global NSEvent monitor is the single global event
  hook in the app.

### 16.5 Memory

- NSPanel instances are retained by their wrapper class and never
  released. Reused across show/dismiss cycles. Content views rebuilt
  per show, which is cheap.

---

## 17. macOS Compatibility

- Min target: macOS 14 (Sonoma).
- Tested on Sonoma (14), Sequoia (15), Tahoe (26).
- Architectures: arm64 + x86_64 universal binary.

---

## 18. Internationalization (`→ Phase 9`)

- Move all user-facing strings to `Localizable.xcstrings`.
- Tooltip labels stay Korean per current decision; alternative: derive
  from user locale.
- Default action prompts: keep instruction in English (LLM is
  prompt-language agnostic) but request response in Korean for 번역.

---

## 19. Performance targets

See §4.1. Measurement instrumentation (`→ Phase 10`):

- `os_signpost` around: selection capture, ActionBar show, ResponsePanel
  show, LLM call.
- Manual measurement using Instruments for cold launch.

---

## 20. Roadmap

| # | Phase | Status | Doc |
|---|---|---|---|
| 1+2 | Action model + ActionBar | done | `docs/tasks/popclip-ux-phase-1-2.md` |
| 3 | ResponsePanel + outside-click + tooltip | done | `docs/tasks/popclip-ux-phase-3.md` |
| 4 | Xpop polish (ESC, hover-out, pin, move, fade) | done (Gemini refactor merged: `cancelOperation`, `windowDidResignKey`, SwiftUI `.onHover`) | `docs/tasks/popclip-ux-phase-4.md` |
| 4.1 | Double-click trigger + selection-only gating + IOHIDCheckAccess pasteboard guard | done | inline, this doc |
| 5 | Model discovery (`/api/tags`) + Picker UI + Position picker UI | next | TBD |
| 6 | Permissions polish: Input Monitoring request, status indicators, Keychain for tokens, remote-endpoint warning | planned | TBD |
| 7 | Custom action editor (Settings tab, JSON persistence, template vars) | planned | TBD |
| 8 | First-run onboarding | planned | TBD |
| 9 | Internationalization (xcstrings, en + ko) | planned | TBD |
| 10 | os_log migration, diagnostic mode, crash log access | planned | TBD |
| 11 | AppleScript fallback for AX-hostile apps | optional | TBD |
| 12 | Privacy manifest (`PrivacyInfo.xcprivacy`) | required for distribution | TBD |
| 13 | Test target (unit + UI + snapshot), ADRs | planned | TBD |
| 14 | CI: GitHub Actions build / test / lint / release | planned | TBD |
| 15 | Sparkle auto-update + Homebrew Cask | planned | TBD |
| 16 | Streaming chat | planned | TBD |
| 17 | Multi-provider (OpenAI / Anthropic / Gemini) + cost display | planned | TBD |
| 18 | High-contrast theme + VoiceOver pass | planned | TBD |
| 19 | Plugin manifests (`~/Library/Application Support/tunaPop/plugins/`) | post-v1 | TBD |

### 20.1 Definition of Done for v1 (App Store optional)

- All "done" rows above are stable.
- Phases 5–10 + 12 + 13 + 14 complete.
- Signed + notarized DMG hosted on GitHub Releases.
- Crash-free session rate ≥ 99.5% on internal dogfood for 7 days.

---

## 21. Open questions

- `TBD` License: MIT vs Apache 2.0.
- `TBD` Bundle ID: `app.tunapop` vs `com.<user>.tunapop`.
- `TBD` System prompt for the LLM call.
- `TBD` Whether to sandbox (gates App Store distribution).
- `TBD` Hover-out grace interval — 1.0 s feels right; needs user
  testing.
- `TBD` Whether 트리플클릭 should also trigger (line selection).
- `TBD` Whether to add a "follow-up" turn in ResponsePanel (chat).
- `TBD` Pricing model post-v1 (free + open-source vs freemium).

---

## Appendix A. Reference projects

- [DongqiShen/Xpop](https://github.com/DongqiShen/Xpop) — Swift,
  PopClip alternative. Source of the `cancelOperation` / `canBecomeKey`
  pattern and the hover-out timer concept.
- [tisfeng/Easydict](https://github.com/tisfeng/Easydict) — Swift +
  ObjC. Source of the AX → AppleScript → Cmd+C extraction strategy and
  Ollama integration prior art.
- [PopClip developer docs](https://www.popclip.app/dev/) — schema and
  UX expectations for extensions.

## Appendix B. macOS API caveats (collected from this codebase's bug
   history — bake these into every PR review)

- `AXUIElementCopyAttributeValue` calls require AX trust. Call without
  it ⇒ TCC may abort the process (`SIGSEGV` observed). Always gate
  with `Accessibility.isTrusted`.
- `CGEvent.post(tap: .cghidEventTap)` requires Input Monitoring. Call
  without it ⇒ process killed. Always gate with `IOHIDCheckAccess(
  kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted`.
- `URLSession.data(for:)` cancellation throws `URLError(.cancelled)`,
  NOT `CancellationError`. Catch both silently.
- `.nonactivatingPanel` panels do not receive `.keyDown` via local
  monitor unless `canBecomeKey` is overridden. Use the
  `KeyableNonActivatingPanel` subclass + `cancelOperation` for ESC.
- `Settings { ... }` SwiftUI scene auto-injects a `Settings…` menu
  item with `Cmd+,`. To remove it: `.commands { CommandGroup(replacing: .appSettings) {} }`.
- After dismissing an animated NSPanel (`alphaValue = 0`), reset to
  `1.0` before the next `orderFront`.
- `NSPanel` z-order is independent of activation. Calling
  `orderFrontRegardless` on a hidden panel makes it visible without
  activating the app, but it may sit below another existing key panel.
  Use `makeKeyAndOrderFront(nil)` or `bringToFront()` to enforce
  top-of-stack.

## Appendix C. macOS edge-case checklist (run before any new phase)

For each phase introducing a new UI surface or system integration, the
spec MUST address:

- [ ] Required permissions and the API used to check / request them.
- [ ] What happens when the user denies / revokes the permission at runtime.
- [ ] Key window vs main window expectations (`canBecomeKey`, `canBecomeMain`).
- [ ] Z-order interactions with other panels in this app.
- [ ] Animation anchor — does the panel grow up or down from a fixed edge.
- [ ] Mouse / key event routing path. Specifically: which panel is
      expected to be key at every step, who receives `cancelOperation`,
      who receives `windowDidResignKey`.
- [ ] Cancellation: `CancellationError` and `URLError(.cancelled)` both
      silent.
- [ ] Resource cleanup on `dismiss()`.
- [ ] Migration impact on `UserDefaults` schema (§15.1).
