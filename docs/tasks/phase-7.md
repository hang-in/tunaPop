# Phase 7 — Custom Action Editor

## Phase

Phase 7 of the production master plan. Lets the user add, edit, remove,
and reorder their own actions in Settings, alongside the three built-in
actions (설명 / 요약 / 번역). Built-in actions remain immutable in v1.

## References

- `docs/MASTER_SPEC.md` §13 (Action System)
- `docs/MASTER_SPEC.md` §3.5 / §15.1 (Settings persistence)
- `docs/MASTER_SPEC.md` §14.3 (Settings window structure)
- `docs/MASTER_SPEC.md` Appendix B + C

## Focus

Let the user customize the action bar to match their personal
workflow — add a "Polite Korean rewrite" action with a custom prompt,
add a Tagalog translation action, hide nothing but extend everything.
Persistence is JSON in `UserDefaults`. Prompts may use template
variables `{selection}`, `{language}`, `{appBundleID}`. The Action
Bar shows built-ins first, then custom actions in the order the user
arranged.

Files to add:
- `Sources/TunaPop/CustomActionEditor.swift` — SwiftUI sheet for
  add / edit one action
- `Sources/TunaPop/SymbolGridPicker.swift` — 30-symbol curated grid

Files to modify:
- `Sources/TunaPop/Action.swift` — `Codable` conformance
- `Sources/TunaPop/AppSettings.swift` — `customActions` persisted
- `Sources/TunaPop/SettingsView.swift` — Actions section + list editor
- `Sources/TunaPop/OllamaClient.swift` — `includeSelectionContext`
  optional parameter
- `Sources/TunaPop/PopupController.swift` — merge built-in + custom
  actions; template variable substitution; chat call flag

Files NOT to modify:
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

## Constraints

- macOS 14+, Swift 5.9+, SwiftUI + AppKit. No new third-party deps.
- `@MainActor` everywhere AppKit/SwiftUI mutates.
- `swift build` MUST succeed with zero new warnings.
- Korean UI strings as written below; do not invent new copy.
- Comments minimal. No emoji.
- Built-in actions (설명 / 요약 / 번역) are NOT editable, NOT
  removable, NOT hideable in v1.
- Custom action IDs are UUIDs — never collide with built-in IDs
  (`"explain"`, `"summarize"`, `"translate"`).
- Backward compatibility: existing users with no custom actions
  continue to see exactly the three built-ins.

---

## Required types and changes

### 1. `Action.swift` — Codable conformance

Add `Codable` conformance. No field change.

```swift
struct Action: Identifiable, Equatable, Codable {
    let id: String
    let label: String
    let prompt: String
    let systemImage: String
}
```

`Action.defaults` array stays exactly as it is today (3 items, ids
`"explain"`, `"summarize"`, `"translate"`).

### 2. `AppSettings.swift` — persist `customActions`

Add a new `@Published` property:

```swift
@Published var customActions: [Action] {
    didSet { persistCustomActions() }
}

private static let customActionsKey = "customActions"

private func persistCustomActions() {
    if let data = try? JSONEncoder().encode(customActions) {
        UserDefaults.standard.set(data, forKey: Self.customActionsKey)
    }
}
```

In `init()`, BEFORE the final closing brace:

```swift
if let data = UserDefaults.standard.data(forKey: Self.customActionsKey),
   let decoded = try? JSONDecoder().decode([Action].self, from: data) {
    customActions = decoded
} else {
    customActions = []
}
```

`persistCustomActions()` is a private method. The `didSet` triggers
on every mutation, including reorder. The Settings UI mutates the
array via `Binding<[Action]>` from `@ObservedObject`.

### 3. `OllamaClient.swift` — `includeSelectionContext` flag

Add an optional parameter with default `true` for backward
compatibility. Only the `payload == .text(...)` branch reads the
flag; image payloads are unaffected.

```swift
func chat(
    model: String,
    prompt: String,
    payload: SelectionPayload,
    includeSelectionContext: Bool = true
) async throws -> OllamaChatResult {
    // ... existing setup ...

    let userMessage: OllamaMessage
    switch payload {
    case .text(let text):
        if includeSelectionContext {
            userMessage = OllamaMessage(
                role: "user",
                content: "\(prompt)\n\nSelection:\n\(text)",
                images: nil
            )
        } else {
            userMessage = OllamaMessage(
                role: "user",
                content: prompt,
                images: nil
            )
        }
    case .image:
        userMessage = OllamaMessage(
            role: "user",
            content: prompt,
            images: payload.imageBase64PNG.map { [$0] }
        )
    }

    // ... rest unchanged ...
}
```

Built-in callers and any caller that doesn't pass the parameter keep
the current behavior (auto-append Selection: <text>). Only callers
that explicitly substituted `{selection}` themselves should pass
`includeSelectionContext: false`.

### 4. `PopupController.swift` — merge actions + template substitution

#### 4a. Merge built-in + custom in `show(...)`

Replace the existing

```swift
actionBarPanel.show(
    actions: Action.defaults,
    at: anchor,
    position: settings.actionBarPosition
)
```

with

```swift
let allActions = Action.defaults + settings.customActions
actionBarPanel.show(
    actions: allActions,
    at: anchor,
    position: settings.actionBarPosition
)
```

#### 4b. Template substitution + chat flag

Extend `resolvePrompt(for:payload:)` to handle template variables.
Add a new helper `substituteTemplate(_:payload:)` and a new variable
that `handleAction` reads to decide whether the chat call should
auto-append `Selection:`.

```swift
private func resolvePrompt(for action: Action, payload: SelectionPayload) -> String {
    let base: String
    if action.id == "translate", case .text(let text) = payload, isShortWord(text) {
        base = "다음 선택된 단어를 한국어 사전 형식으로 풀어 주세요. 의미, 품사, 짧은 예문 한 줄을 포함하세요."
    } else {
        base = action.prompt
    }
    return substituteTemplate(base, payload: payload)
}

private func substituteTemplate(_ raw: String, payload: SelectionPayload) -> String {
    var result = raw
    if case .text(let text) = payload {
        result = result.replacingOccurrences(of: "{selection}", with: text)
    }
    let language = Locale.current.identifier
    result = result.replacingOccurrences(of: "{language}", with: language)
    let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    result = result.replacingOccurrences(of: "{appBundleID}", with: bundleID)
    return result
}
```

In `handleAction(_:)`, after `let prompt = resolvePrompt(for: action, payload: payload)`,
compute the flag:

```swift
let includeContext = !action.prompt.contains("{selection}")
```

Pass the flag into `OllamaClient.chat`:

```swift
let result = try await client.chat(
    model: model,
    prompt: prompt,
    payload: payloadCopy,
    includeSelectionContext: includeContext
)
```

Notes:
- The flag check looks at `action.prompt` (the raw, pre-substitution
  string) so the user's explicit `{selection}` placeholder is
  detected even after substitution.
- Built-in actions don't use placeholders → `includeContext = true`
  → original behavior preserved.
- Custom actions with `{selection}` get the selection text inlined
  exactly where the placeholder was, with no duplicate `Selection:`
  block appended.
- Custom actions without `{selection}` behave like built-ins.
- Word-mode translate prompt does not include `{selection}` either,
  so the existing "Selection: <text>" auto-append still works for
  it.

### 5. `SettingsView.swift` — Actions section

Add a new `Section("액션")` AFTER `Section("기본 동작")` and BEFORE
`Section("권한")`.

Layout:

```swift
Section("액션") {
    ForEach(Action.defaults) { action in
        builtInRow(action: action)
    }
    ForEach(settings.customActions) { action in
        customRow(action: action)
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

New `@State` in `SettingsView`:

```swift
@State private var isEditing = false
@State private var editingAction: Action = Action(id: "", label: "", prompt: "", systemImage: "text.bubble")
@State private var editingIndex: Int? = nil
```

`builtInRow(action:)`:

```swift
@ViewBuilder
private func builtInRow(action: Action) -> some View {
    HStack(spacing: 8) {
        Image(systemName: action.systemImage)
            .foregroundStyle(.secondary)
        Text(action.label)
        Spacer()
        Text("기본")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
```

`customRow(action:)`:

```swift
@ViewBuilder
private func customRow(action: Action) -> some View {
    HStack(spacing: 8) {
        Image(systemName: action.systemImage)
        Text(action.label)
        Spacer()
        Button("수정") {
            editingAction = action
            editingIndex = settings.customActions.firstIndex(where: { $0.id == action.id })
            isEditing = true
        }
        .buttonStyle(.borderless)
        Button {
            settings.customActions.removeAll(where: { $0.id == action.id })
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
    }
}
```

Reordering: for v1 use SwiftUI `.onMove(perform:)` inside the
`ForEach` for `settings.customActions`. Built-in actions cannot
be reordered. Implementation:

```swift
ForEach(settings.customActions) { action in
    customRow(action: action)
}
.onMove { fromOffsets, toOffset in
    settings.customActions.move(fromOffsets: fromOffsets, toOffset: toOffset)
}
```

(SwiftUI `Form` may or may not display the drag handle; if the
handle is missing on macOS 14, fall back to up/down arrow buttons
on each row. Pick whichever works.)

Sheet presentation:

```swift
.sheet(isPresented: $isEditing) {
    CustomActionEditor(
        action: $editingAction,
        onCommit: { committed in
            if let idx = editingIndex {
                settings.customActions[idx] = committed
            } else {
                settings.customActions.append(committed)
            }
            isEditing = false
            editingIndex = nil
        },
        onCancel: {
            isEditing = false
            editingIndex = nil
        }
    )
}
```

Helper:

```swift
private func newDraftAction() -> Action {
    Action(
        id: UUID().uuidString,
        label: "",
        prompt: "",
        systemImage: "text.bubble"
    )
}
```

The `editingIndex` distinguishes "new" (`nil`) from "edit" (Int).

### 6. `CustomActionEditor.swift` (new)

```swift
import SwiftUI

struct CustomActionEditor: View {
    @Binding var action: Action
    let onCommit: (Action) -> Void
    let onCancel: () -> Void

    @State private var label: String = ""
    @State private var prompt: String = ""
    @State private var systemImage: String = "text.bubble"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("액션 편집")
                .font(.headline)

            Form {
                TextField("이름", text: $label)
                    .textFieldStyle(.roundedBorder)
                TextField("프롬프트", text: $prompt, axis: .vertical)
                    .lineLimit(4...8)
                    .textFieldStyle(.roundedBorder)
                Text("프롬프트 변수: {selection}, {language}, {appBundleID}")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("아이콘")
                .font(.subheadline)
            SymbolGridPicker(selection: $systemImage)

            HStack {
                Spacer()
                Button("취소") { onCancel() }
                Button("저장") {
                    let result = Action(
                        id: action.id,
                        label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                        prompt: prompt,
                        systemImage: systemImage
                    )
                    onCommit(result)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480, height: 480)
        .onAppear {
            label = action.label
            prompt = action.prompt
            systemImage = action.systemImage
        }
    }
}
```

Notes:
- The editor takes a `Binding<Action>` only to seed initial state; it
  commits a fully constructed `Action` value via `onCommit`. This
  avoids partial-write issues if the user cancels.
- Save is disabled when label or prompt is empty after trimming.
- The "프롬프트 변수: ..." hint uses caption2 + secondary to stay
  unobtrusive.

### 7. `SymbolGridPicker.swift` (new)

A 30-symbol curated grid. Tap to select.

```swift
import SwiftUI

struct SymbolGridPicker: View {
    @Binding var selection: String

    static let curated: [String] = [
        "text.bubble", "list.bullet.rectangle", "character.bubble",
        "doc.text", "info.bubble", "lightbulb", "questionmark.circle",
        "highlighter", "pencil.tip.crop.circle", "doc.on.clipboard",
        "wand.and.stars", "sparkles", "globe", "translate",
        "character.book.closed", "text.book.closed",
        "magnifyingglass", "checkmark.circle", "exclamationmark.bubble",
        "quote.bubble", "bubble.left.and.bubble.right",
        "arrow.left.arrow.right.circle", "arrow.triangle.2.circlepath",
        "scissors", "doc.on.doc", "paintbrush", "wand.and.rays",
        "ellipsis.bubble", "rectangle.and.text.magnifyingglass",
        "fish"
    ]

    private let columns = Array(repeating: GridItem(.fixed(36), spacing: 6), count: 6)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Self.curated, id: \.self) { name in
                    Button {
                        selection = name
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 16))
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selection == name ? Color.accentColor.opacity(0.25) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        selection == name ? Color.accentColor : Color.primary.opacity(0.1),
                                        lineWidth: selection == name ? 1.5 : 0.5
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(name)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 200)
    }
}
```

If any symbol in `curated` is missing on macOS 14, the cell renders
empty but the picker remains functional. Verify the list before
shipping; remove any symbol that doesn't exist.

## Acceptance Criteria

1. `swift build` succeeds with zero new warnings.
2. Built-in 3 actions (설명 / 요약 / 번역) appear in Settings →
   "액션" section with the "기본" tag and NO edit / delete buttons.
3. Clicking "새 액션 추가" opens a sheet titled "액션 편집" with
   ️Label / Prompt / Icon picker. Save is disabled until both Label
   and Prompt have non-whitespace content.
4. After saving, the new custom action appears under the built-ins
   in Settings AND in the ActionBar on the next selection cycle.
5. The custom action's prompt is sent to `OllamaClient.chat` after
   `{selection}` / `{language}` / `{appBundleID}` substitution.
6. A custom action prompt `"Translate this: {selection}\nLanguage: {language}"`
   results in `includeSelectionContext: false` being passed to
   `OllamaClient.chat` — no duplicate `Selection: <text>` block in
   the LLM input.
7. A custom action prompt without `{selection}` (e.g. `"Make this
   formal."`) results in `includeSelectionContext: true` (default) →
   `Selection: <text>` is still auto-appended. Behavior matches
   built-ins.
8. Editing an existing custom action via "수정" pre-populates the
   sheet with current values and committing replaces the original
   in place (same id, same array position).
9. Deleting (trash icon) removes the action from the array
   immediately. The ActionBar for the next selection reflects the
   change.
10. Reordering: drag custom actions to reorder. Built-ins cannot
    be moved. After reorder, the ActionBar shows custom actions in
    the new order.
11. Persistence: kill and relaunch the app — custom actions and
    their order are preserved. Verified by inspecting
    `UserDefaults` key `"customActions"` containing a non-empty JSON
    blob.
12. The 30-symbol picker grid renders without console errors.
    Selecting a symbol updates the highlight ring and saves with
    the new icon.
13. UUID collision protection: a user-created action with id that
    matches a built-in id (`"explain"` etc.) is impossible — the
    editor always assigns a fresh `UUID().uuidString` for new
    actions.
14. The Phase 6.5 word/sentence translate gating still works: short
    selections through the built-in 번역 action still get the
    dictionary-style prompt.

## macOS edge-case checklist (Appendix C)

- [ ] Permissions: no new permissions.
- [ ] Permission revoked at runtime: no new path.
- [ ] Key window: no new floating panels. The editor opens as a
      modal sheet over the existing Settings NSWindow.
- [ ] Z-order: no change to floating panels.
- [ ] Animation anchor: no change.
- [ ] Mouse / key event routing: editor sheet uses standard SwiftUI
      sheet routing.
- [ ] Cancellation: cancel button discards changes; commit applies
      them. No async work in the editor.
- [ ] Resource cleanup: sheet dismissal handled by SwiftUI.
- [ ] UserDefaults schema: ADDS key `"customActions"` (Data, JSON
      array of `Action`). Update `docs/MASTER_SPEC.md` §15.1 in a
      follow-up.

## Out of Scope

- Editing built-in actions.
- Hiding built-in actions.
- Importing / exporting custom action sets as JSON files.
- YAML plugin format (post-v1, Phase 19).
- Live preview of the prompt with sample selection.
- Icon search across full SF Symbols catalog.
- Reordering built-in actions.
- Multi-language editor strings (Phase 9 internationalization).
- Removing the SelectionMonitor diagnostic NSLog (separate cleanup PR).
