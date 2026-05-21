# Phase 8 — Settings UI cleanup + Agent dropdown + Response language

## Phase

Phase 8 of the production master plan. Six grouped UI/UX
improvements after Phase 7 ships:

1. Rename Settings "Ollama" section to "Agent" with a provider
   dropdown (v1: Ollama only; LM Studio / OpenAI / Anthropic /
   Gemini will be added in Phase 17).
2. Add **AI response language** setting (auto / English / 한국어 /
   日本語 / 中文). Default `auto` = follow system locale.
3. Inject a system message into every LLM call telling the model
   which language to reply in.
4. Drop the "기본 동작" section: `defaultPrompt` is no longer used
   (Phase 5 follow-up routed via `action.prompt`). Move the ActionBar
   position picker into its own section.
5. UI cleanup in the "액션" section:
   - Edit and delete buttons both icons (pencil + trash) for
     consistency.
   - `Divider()` between built-in and custom actions.
6. Section label alignment audit — confirm all section headers are
   left-aligned and copy is consistent.

## References

- `docs/MASTER_SPEC.md` §3.5 (Settings v1), §12 (LLM Integration),
  §14.3 (Settings tabs), §15.1 (UserDefaults schema)
- `docs/MASTER_SPEC.md` Appendix B / C

## Focus

Make Settings feel like a finished product: one section per concern,
consistent control style, language preference under user control,
provider field ready for multi-provider expansion.

Files to add:
- `Sources/TunaPop/AgentProvider.swift`
- `Sources/TunaPop/ResponseLanguage.swift`

Files to modify:
- `Sources/TunaPop/AppSettings.swift` — new fields
- `Sources/TunaPop/SettingsView.swift` — full section restructure
- `Sources/TunaPop/OllamaClient.swift` — optional `systemPrompt`
- `Sources/TunaPop/PopupController.swift` — build + pass system prompt

Files NOT to modify:
- `Sources/TunaPop/Action.swift`
- `Sources/TunaPop/ActionBarPanel.swift`
- `Sources/TunaPop/ActionBarView.swift`
- `Sources/TunaPop/ActionBarPosition.swift`
- `Sources/TunaPop/ResponsePanel.swift`
- `Sources/TunaPop/ResponseView.swift`
- `Sources/TunaPop/ResponseState.swift`
- `Sources/TunaPop/SelectionExtractor.swift`
- `Sources/TunaPop/SelectionMonitor.swift`
- `Sources/TunaPop/SelectionPayload.swift`
- `Sources/TunaPop/Accessibility.swift`
- `Sources/TunaPop/InputMonitoring.swift`
- `Sources/TunaPop/KeychainHelper.swift`
- `Sources/TunaPop/KeyableNonActivatingPanel.swift`
- `Sources/TunaPop/TooltipImageButton.swift`
- `Sources/TunaPop/TunaPopApp.swift`
- `Sources/TunaPop/CustomActionEditor.swift`
- `Sources/TunaPop/SymbolGridPicker.swift`

## Constraints

- macOS 14+, Swift 5.9+. No new third-party deps.
- `@MainActor` everywhere AppKit/SwiftUI mutates.
- `swift build` MUST succeed with zero new warnings.
- Korean UI strings only as written below. No emoji.
- Backward compatibility: existing `UserDefaults` keys
  (`endpoint`, `model`, `defaultPrompt`, `actionBarPosition`,
  `customActions`, Keychain `apiToken`) MUST continue to read
  correctly. New keys (`agentProvider`, `responseLanguage`) start
  with default values.
- `defaultPrompt` field on `AppSettings` stays (do not break the
  init signature), but its Settings UI row is removed.

---

## Required changes

### 1. `AgentProvider.swift` (new)

```swift
import Foundation

enum AgentProvider: String, CaseIterable, Codable, Identifiable {
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        }
    }
}
```

LM Studio / OpenAI / etc. land in Phase 17. The enum exists now so
the Settings UI uses a `Picker` that doesn't need refactoring later.

### 2. `ResponseLanguage.swift` (new)

```swift
import Foundation

enum ResponseLanguage: String, CaseIterable, Codable, Identifiable {
    case auto
    case english
    case korean
    case japanese
    case chinese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "시스템 따름"
        case .english: return "English"
        case .korean: return "한국어"
        case .japanese: return "日本語"
        case .chinese: return "中文"
        }
    }

    var systemPromptName: String? {
        switch self {
        case .auto:
            return ResponseLanguage.fromSystemLocale().systemPromptName
        case .english: return "English"
        case .korean: return "Korean"
        case .japanese: return "Japanese"
        case .chinese: return "Chinese"
        }
    }

    static func fromSystemLocale() -> ResponseLanguage {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        switch code {
        case "ko": return .korean
        case "ja": return .japanese
        case "zh": return .chinese
        case "en": return .english
        default: return .english
        }
    }
}
```

`systemPromptName` returns the language name in English so the LLM
prompt phrasing stays one-sentence simple. `.auto` resolves via
`fromSystemLocale()` so there is no infinite recursion (auto never
returns auto).

### 3. `AppSettings.swift` — new fields

Add two `@Published` properties next to the existing ones:

```swift
@Published var agentProvider: AgentProvider {
    didSet { UserDefaults.standard.set(agentProvider.rawValue, forKey: Self.agentProviderKey) }
}

@Published var responseLanguage: ResponseLanguage {
    didSet { UserDefaults.standard.set(responseLanguage.rawValue, forKey: Self.responseLanguageKey) }
}

private static let agentProviderKey = "agentProvider"
private static let responseLanguageKey = "responseLanguage"
```

In `init()` (before the closing brace):

```swift
let providerRaw = UserDefaults.standard.string(forKey: Self.agentProviderKey)
agentProvider = providerRaw.flatMap(AgentProvider.init(rawValue:)) ?? .ollama

let languageRaw = UserDefaults.standard.string(forKey: Self.responseLanguageKey)
responseLanguage = languageRaw.flatMap(ResponseLanguage.init(rawValue:)) ?? .auto
```

### 4. `OllamaClient.swift` — optional `systemPrompt`

Extend `chat(...)`:

```swift
func chat(
    model: String,
    prompt: String,
    payload: SelectionPayload,
    includeSelectionContext: Bool = true,
    systemPrompt: String? = nil
) async throws -> OllamaChatResult {
    // ... existing setup ...

    let userMessage: OllamaMessage
    switch payload {
    case .text(let text):
        if includeSelectionContext {
            userMessage = OllamaMessage(role: "user", content: "\(prompt)\n\nSelection:\n\(text)", images: nil)
        } else {
            userMessage = OllamaMessage(role: "user", content: prompt, images: nil)
        }
    case .image:
        userMessage = OllamaMessage(role: "user", content: prompt, images: payload.imageBase64PNG.map { [$0] })
    }

    var messages: [OllamaMessage] = []
    if let systemPrompt, !systemPrompt.isEmpty {
        messages.append(OllamaMessage(role: "system", content: systemPrompt, images: nil))
    }
    messages.append(userMessage)

    let body = OllamaChatRequest(model: model, messages: messages, stream: false)
    // ... rest unchanged ...
}
```

The system message is prepended only when `systemPrompt` is non-nil
and non-empty. Existing callers that omit the parameter keep
identical behavior.

### 5. `PopupController.swift` — build + pass system prompt

In `handleAction(_:)`, after computing `prompt` and `includeContext`,
build the system prompt:

```swift
let systemPrompt = buildSystemPrompt(settings.responseLanguage)
let result = try await client.chat(
    model: model,
    prompt: prompt,
    payload: payloadCopy,
    includeSelectionContext: includeContext,
    systemPrompt: systemPrompt
)
```

Add the helper anywhere on the type:

```swift
private func buildSystemPrompt(_ language: ResponseLanguage) -> String? {
    guard let name = language.systemPromptName else { return nil }
    return "Always reply in \(name). Use natural, concise wording. Do not add introductory or closing filler."
}
```

`systemPromptName` returning nil is theoretically impossible for the
defined cases, but the guard keeps callers robust.

### 6. `SettingsView.swift` — full section restructure

The Settings body becomes a sequence of these sections, in this
order:

```
Section("Agent")
Section("응답 언어")
Section("ActionBar")
Section("액션")
Section("권한")
Section { fetchError caption (existing, conditional) }
```

The previous `Section("기본 동작")` is REMOVED. Its `defaultPrompt`
TextField row is dropped. Its `ActionBarPosition` Picker is moved
into `Section("ActionBar")`.

#### Section("Agent")

```swift
Section("Agent") {
    Picker("Provider", selection: $settings.agentProvider) {
        ForEach(AgentProvider.allCases) { provider in
            Text(provider.displayName).tag(provider)
        }
    }
    TextField("Endpoint", text: $settings.endpoint)
        .textFieldStyle(.roundedBorder)
    if !isLocalEndpoint(settings.endpoint) {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("이 엔드포인트는 로컬이 아닙니다. 선택한 텍스트가 외부 네트워크로 전송됩니다.")
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
    HStack {
        Picker("Model", selection: modelSelection) { /* same content as today */ }
        Button { Task { await refreshModels() } } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .help("모델 목록 새로고침")
        .disabled(isFetching)
    }
    if showsCustomModelField {
        TextField("Custom model", text: $customModelEntry)
            .textFieldStyle(.roundedBorder)
            .onChange(of: customModelEntry) { _, newValue in
                settings.model = newValue
            }
    }
    SecureField("API token", text: $settings.apiToken)
        .textFieldStyle(.roundedBorder)
}
```

#### Section("응답 언어")

```swift
Section("응답 언어") {
    Picker("AI 응답 언어", selection: $settings.responseLanguage) {
        ForEach(ResponseLanguage.allCases) { language in
            Text(language.displayName).tag(language)
        }
    }
}
```

#### Section("ActionBar")

```swift
Section("ActionBar") {
    Picker("위치", selection: $settings.actionBarPosition) {
        Text("↖ Top Left").tag(ActionBarPosition.topLeft)
        Text("↑ Top").tag(ActionBarPosition.top)
        Text("↗ Top Right").tag(ActionBarPosition.topRight)
        Text("← Left").tag(ActionBarPosition.left)
        Text("→ Right").tag(ActionBarPosition.right)
        Text("↙ Bottom Left").tag(ActionBarPosition.bottomLeft)
        Text("↓ Bottom").tag(ActionBarPosition.bottom)
        Text("↘ Bottom Right").tag(ActionBarPosition.bottomRight)
    }
}
```

#### Section("액션") changes

Inside the section:

```swift
Section("액션") {
    ForEach(Action.defaults) { action in
        builtInRow(action: action)
    }
    Divider()
    ForEach(settings.customActions) { action in
        customRow(action: action)
    }
    .onMove { fromOffsets, toOffset in
        settings.customActions.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }
    Button {
        editingAction = newDraftAction()
        isEditing = true
    } label: {
        Label("새 액션 추가", systemImage: "plus.circle")
    }
    .buttonStyle(.borderless)
}
```

The `Divider()` between the built-in `ForEach` and the custom
`ForEach` is the explicit visual separator.

`customRow(action:)` — change the edit button from text to an icon
and keep the delete icon. Both buttons become icon-only with native
tooltips:

```swift
@ViewBuilder
private func customRow(action: Action) -> some View {
    HStack(spacing: 8) {
        Image(systemName: action.systemImage)
        Text(action.label)
        Spacer()
        Button {
            editingAction = action
            editingIndex = settings.customActions.firstIndex(where: { $0.id == action.id })
            isEditing = true
        } label: {
            Image(systemName: "pencil")
        }
        .buttonStyle(.borderless)
        .help("수정")
        Button {
            settings.customActions.removeAll(where: { $0.id == action.id })
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .help("삭제")
    }
}
```

`builtInRow(action:)` stays unchanged: icon + label + "기본" caption,
no edit/delete buttons.

#### Section("권한") and final error section

Unchanged.

## Acceptance Criteria

1. `swift build` succeeds with zero new warnings.
2. New files exist: `AgentProvider.swift`, `ResponseLanguage.swift`.
3. Settings sections appear in this order: Agent / 응답 언어 /
   ActionBar / 액션 / 권한 / (error caption).
4. "기본 동작" section is GONE. `defaultPrompt` is not displayed in
   the UI. `AppSettings.defaultPrompt` property still exists on
   the model (for binary compatibility) — confirm via grep.
5. **Agent section**: Provider Picker shows only "Ollama" (single
   option, no v1 lock). Endpoint / Model / API token field
   behavior identical to Phase 7.
6. **응답 언어 section**: Picker shows 5 entries:
   `시스템 따름`, `English`, `한국어`, `日本語`, `中文`.
7. **System prompt injection**: with `responseLanguage == .auto` on
   a macOS instance with system language Korean, the LLM call
   contains a system message `"Always reply in Korean. ..."`.
   Verify by capturing the JSON body in a `URLProtocol` stub or
   by inspecting the request via Console / Charles.
8. **Override**: setting `responseLanguage = .english` overrides
   the auto detection. The system message reads
   `"Always reply in English. ..."`.
9. **No regression**: drag → ActionBar → action → ResponsePanel
   with metadata caption works. The user's previously-set
   `defaultPrompt` value is preserved in `UserDefaults` even
   though there is no UI for it.
10. **Edit / delete UI parity**: in the custom action rows, both
    edit and delete are icon buttons (`pencil` and `trash`) with
    native tooltips. No text "수정" / "삭제" buttons.
11. **Divider**: a visible horizontal divider sits between the last
    built-in action and the first custom action in the "액션"
    section.
12. **Persistence**: changing `agentProvider` and `responseLanguage`
    survives a kill/relaunch.
13. **Multi-language phrasing**: with `responseLanguage = .japanese`
    on a single-word translate, the dictionary-style response
    arrives in Japanese (no Korean leak).

## macOS edge-case checklist (Appendix C)

- [ ] Permissions: no change.
- [ ] Permission revoked at runtime: no new path.
- [ ] Key window: no change.
- [ ] Z-order: no change.
- [ ] Animation anchor: no change.
- [ ] Mouse / key event routing: no change.
- [ ] Cancellation: `URLError(.cancelled)` + `CancellationError`
      silent (Phase 4 fix preserved).
- [ ] Resource cleanup: no new monitors / timers.
- [ ] UserDefaults schema: ADDS `agentProvider` (String) and
      `responseLanguage` (String). Update master spec §15.1 in a
      doc-only follow-up.

## Out of Scope

- LM Studio / OpenAI / Anthropic / Gemini providers — Phase 17.
- Built-in action editing / hiding / reset — Phase 9.
- System utility actions (copy/paste/etc.) — Phase 9.
- Per-action language override.
- Streaming chat — Phase 16.
- Removing `defaultPrompt` from `AppSettings` (would require
  schema migration; deferred).
- Removing the SelectionMonitor diagnostic NSLogs (separate cleanup
  PR).
- Settings tabbed UI (still a single Form).
