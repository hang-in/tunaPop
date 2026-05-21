# Phase 9 — Built-in editing + Hide + Reset + System utility actions

## Phase

Phase 9 of the production master plan. Two grouped concerns:

**A. Built-in action editing**
- Allow editing prompt / label / icon of the three built-in actions
  (설명 / 요약 / 번역).
- "Hide" toggle on each built-in (removes from ActionBar without
  deleting from the data model).
- "Reset" button to revert to factory defaults.

**B. System utility actions**
- A new action `kind`: `system` (no LLM call).
- Four built-in system actions: `복사` (copy), `붙여넣기` (paste),
  `웹 검색` (web search), `사전 조회` (look up).
- `CustomActionEditor` gains a category toggle: "AI 액션" vs
  "기본 기능". The form fields shown depend on the choice.

## References

- `docs/MASTER_SPEC.md` §13 (Action System) — extend §13.3 with
  template variables, add §13.4 system actions.
- `docs/MASTER_SPEC.md` §15.1 — schema for `builtinOverrides`,
  `hiddenBuiltinIds`.
- Appendix B (macOS API caveats).

## Focus

Make every action — built-in or custom, AI or system — uniformly
editable and hideable. Introduce a non-LLM action path so common
utilities (copy/paste/search/lookup) don't require Ollama.

Files to add:
- `Sources/TunaPop/ActionKind.swift` — enum `{ ai, system }`
- `Sources/TunaPop/SystemActionType.swift` — enum
  `{ copy, paste, webSearch, lookUp }`
- `Sources/TunaPop/SystemActionExecutor.swift` — runs the system
  utility actions

Files to modify:
- `Sources/TunaPop/Action.swift` — add `kind`, `systemType` fields
- `Sources/TunaPop/AppSettings.swift` — `builtinOverrides`,
  `hiddenBuiltinIds`
- `Sources/TunaPop/SettingsView.swift` — built-in row with edit/hide/reset
- `Sources/TunaPop/CustomActionEditor.swift` — category toggle +
  conditional fields
- `Sources/TunaPop/PopupController.swift` — merge built-in overrides,
  hide filter, dispatch on `kind`

Files NOT to modify:
- `Sources/TunaPop/AgentProvider.swift`
- `Sources/TunaPop/ResponseLanguage.swift`
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
- `Sources/TunaPop/SymbolGridPicker.swift`
- `Sources/TunaPop/OllamaClient.swift`

## Constraints

- macOS 14+, Swift 5.9+. No new third-party deps.
- `@MainActor` everywhere AppKit/SwiftUI mutates.
- `swift build` MUST succeed with zero new warnings.
- Korean UI strings per below; no emoji.
- Backward compatibility: existing `customActions` UserDefaults JSON
  MUST decode correctly even though `Action` gains two new fields
  (`kind`, `systemType`). Achieve this with **default values during
  decoding** (see required types below).
- Pasteboard fallback for `paste` MUST NOT use
  `CGEvent.post(.cghidEventTap)` (TCC kill risk). Use AX API
  `AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute, ...)`
  inside the existing AX-trusted gate.

---

## Required types

### `ActionKind.swift` (new)

```swift
import Foundation

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case ai
    case system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ai: return "AI 액션"
        case .system: return "기본 기능"
        }
    }
}
```

### `SystemActionType.swift` (new)

```swift
import Foundation

enum SystemActionType: String, Codable, CaseIterable, Identifiable {
    case copy
    case paste
    case webSearch
    case lookUp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .copy: return "복사"
        case .paste: return "붙여넣기"
        case .webSearch: return "웹 검색"
        case .lookUp: return "사전 조회"
        }
    }

    var defaultLabel: String { displayName }

    var defaultSystemImage: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .paste: return "doc.on.clipboard"
        case .webSearch: return "magnifyingglass"
        case .lookUp: return "character.book.closed"
        }
    }
}
```

### `Action.swift` change — two new fields, Codable backward compat

```swift
struct Action: Identifiable, Equatable, Codable {
    let id: String
    let label: String
    let prompt: String
    let systemImage: String
    let kind: ActionKind
    let systemType: SystemActionType?

    init(
        id: String,
        label: String,
        prompt: String,
        systemImage: String,
        kind: ActionKind = .ai,
        systemType: SystemActionType? = nil
    ) {
        self.id = id
        self.label = label
        self.prompt = prompt
        self.systemImage = systemImage
        self.kind = kind
        self.systemType = systemType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        prompt = try c.decode(String.self, forKey: .prompt)
        systemImage = try c.decode(String.self, forKey: .systemImage)
        kind = try c.decodeIfPresent(ActionKind.self, forKey: .kind) ?? .ai
        systemType = try c.decodeIfPresent(SystemActionType.self, forKey: .systemType)
    }
}
```

`Action.defaults` stays at 3 items (설명 / 요약 / 번역, all `.ai`).

### `Action.systemDefaults` — new static array

```swift
extension Action {
    static let systemDefaults: [Action] = [
        Action(
            id: "system.copy",
            label: SystemActionType.copy.defaultLabel,
            prompt: "",
            systemImage: SystemActionType.copy.defaultSystemImage,
            kind: .system,
            systemType: .copy
        ),
        Action(
            id: "system.paste",
            label: SystemActionType.paste.defaultLabel,
            prompt: "",
            systemImage: SystemActionType.paste.defaultSystemImage,
            kind: .system,
            systemType: .paste
        ),
        Action(
            id: "system.webSearch",
            label: SystemActionType.webSearch.defaultLabel,
            prompt: "",
            systemImage: SystemActionType.webSearch.defaultSystemImage,
            kind: .system,
            systemType: .webSearch
        ),
        Action(
            id: "system.lookUp",
            label: SystemActionType.lookUp.defaultLabel,
            prompt: "",
            systemImage: SystemActionType.lookUp.defaultSystemImage,
            kind: .system,
            systemType: .lookUp
        ),
    ]

    static var allBuiltins: [Action] { defaults + systemDefaults }
}
```

System actions are treated as built-in for purposes of override and hide.

### `AppSettings.swift` — two new persisted maps

```swift
@Published var builtinOverrides: [String: Action] {
    didSet { persistBuiltinOverrides() }
}

@Published var hiddenBuiltinIds: Set<String> {
    didSet { persistHiddenBuiltinIds() }
}

private static let builtinOverridesKey = "builtinOverrides"
private static let hiddenBuiltinIdsKey = "hiddenBuiltinIds"

private func persistBuiltinOverrides() {
    if let data = try? JSONEncoder().encode(builtinOverrides) {
        UserDefaults.standard.set(data, forKey: Self.builtinOverridesKey)
    }
}

private func persistHiddenBuiltinIds() {
    let array = Array(hiddenBuiltinIds)
    if let data = try? JSONEncoder().encode(array) {
        UserDefaults.standard.set(data, forKey: Self.hiddenBuiltinIdsKey)
    }
}
```

In `init()` (load both):

```swift
if let data = UserDefaults.standard.data(forKey: Self.builtinOverridesKey),
   let decoded = try? JSONDecoder().decode([String: Action].self, from: data) {
    builtinOverrides = decoded
} else {
    builtinOverrides = [:]
}

if let data = UserDefaults.standard.data(forKey: Self.hiddenBuiltinIdsKey),
   let decoded = try? JSONDecoder().decode([String].self, from: data) {
    hiddenBuiltinIds = Set(decoded)
} else {
    hiddenBuiltinIds = []
}
```

Add helpers on `AppSettings`:

```swift
func resolvedBuiltin(_ original: Action) -> Action {
    builtinOverrides[original.id] ?? original
}

func resetBuiltin(_ id: String) {
    builtinOverrides.removeValue(forKey: id)
    hiddenBuiltinIds.remove(id)
}

func isHidden(_ id: String) -> Bool {
    hiddenBuiltinIds.contains(id)
}
```

### `SystemActionExecutor.swift` (new)

```swift
import AppKit
@preconcurrency import ApplicationServices

@MainActor
enum SystemActionExecutor {
    static func run(_ type: SystemActionType, payload: SelectionPayload) {
        guard case .text(let text) = payload else { return }
        switch type {
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .paste:
            performPaste(text: NSPasteboard.general.string(forType: .string) ?? "")
        case .webSearch:
            openWebSearch(for: text)
        case .lookUp:
            openLookUp(for: text)
        }
    }

    // MARK: - Implementations

    private static func openWebSearch(for query: String) {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func openLookUp(for word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "dict://\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func performPaste(text: String) {
        guard Accessibility.isTrusted else { return }
        guard !text.isEmpty else { return }
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return
        }
        let focused = focusedValue as! AXUIElement
        AXUIElementSetAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
    }
}
```

`paste` uses AX `kAXSelectedTextAttribute` set — safe and gated by
`Accessibility.isTrusted`. Apps that don't expose the focused element
or refuse `kAXSelectedTextAttribute` simply no-op (no crash).

### `PopupController.swift` — merge, filter, dispatch

#### Merge + filter visible actions

In `show(payload:at:)`, replace the existing `let allActions = ...`
with:

```swift
let visibleBuiltins = Action.allBuiltins
    .filter { !settings.isHidden($0.id) }
    .map { settings.resolvedBuiltin($0) }
let allActions = visibleBuiltins + settings.customActions
```

#### Dispatch on `kind` in `handleAction`

At the very top of `handleAction(_:)`, BEFORE the existing
`guard let payload = lastPayload else { return }` block, branch on
`action.kind`:

```swift
private func handleAction(_ action: Action) {
    guard let payload = lastPayload else { return }
    cancelHideTimer()

    if action.kind == .system, let systemType = action.systemType {
        actionBarPanel.dismiss()
        SystemActionExecutor.run(systemType, payload: payload)
        dismiss()
        return
    }

    // ... existing AI path ...
}
```

System actions: dismiss the action bar, run the OS action, then
tear down. No ResponsePanel for `.copy` / `.paste`. For `.webSearch`
and `.lookUp`, `NSWorkspace.open` brings up the browser / Dictionary
app outside our process — we just dismiss.

(If later we want a small "복사 완료" toast, that's a Phase 9.x
follow-up — out of scope here.)

### `CustomActionEditor.swift` — category toggle + conditional fields

Add a category Picker at the top of the form:

```swift
@State private var kind: ActionKind = .ai
@State private var systemType: SystemActionType = .copy

// In body:
Picker("종류", selection: $kind) {
    ForEach(ActionKind.allCases) { k in
        Text(k.displayName).tag(k)
    }
}
.pickerStyle(.segmented)
```

When `kind == .ai`: show existing Label / Prompt / Icon picker rows.
When `kind == .system`: show:

```swift
Picker("기본 기능", selection: $systemType) {
    ForEach(SystemActionType.allCases) { t in
        Text(t.displayName).tag(t)
    }
}
TextField("이름", text: $label)
// Icon picker (SymbolGridPicker) still shown
// Prompt field hidden in system mode
```

The Save button is enabled when:
- `kind == .ai` AND label and prompt both non-empty
- `kind == .system` AND label is non-empty (prompt unused)

On commit, build the `Action`:

```swift
let result: Action
switch kind {
case .ai:
    result = Action(
        id: action.id,
        label: label.trimmingCharacters(in: .whitespacesAndNewlines),
        prompt: prompt,
        systemImage: systemImage,
        kind: .ai,
        systemType: nil
    )
case .system:
    result = Action(
        id: action.id,
        label: label.trimmingCharacters(in: .whitespacesAndNewlines),
        prompt: "",
        systemImage: systemImage,
        kind: .system,
        systemType: systemType
    )
}
onCommit(result)
```

`.onAppear` should seed `kind` / `systemType` from the incoming
`action` (for editing) so opening "수정" on a system action lands
in the right tab.

### `SettingsView.swift` — built-in row with edit / hide / reset

Replace the existing `builtInRow(action:)` and the static
`ForEach(Action.defaults)` with:

```swift
ForEach(Action.allBuiltins) { action in
    builtInRow(action: settings.resolvedBuiltin(action), originalId: action.id)
}
```

(There are now 7 built-ins: 3 AI + 4 system.)

`builtInRow` adds 수정 / 숨김 / 초기화 controls:

```swift
@ViewBuilder
private func builtInRow(action: Action, originalId: String) -> some View {
    let isHidden = settings.isHidden(originalId)
    let isOverridden = settings.builtinOverrides[originalId] != nil
    HStack(spacing: 8) {
        Image(systemName: action.systemImage)
            .foregroundStyle(isHidden ? .secondary : .primary)
        Text(action.label)
            .foregroundStyle(isHidden ? .secondary : .primary)
        Spacer()
        Text("기본")
            .font(.caption2)
            .foregroundStyle(.secondary)
        Button {
            editingAction = action
            editingIndex = nil
            editingBuiltinId = originalId
            isEditing = true
        } label: {
            Image(systemName: "pencil")
        }
        .buttonStyle(.borderless)
        .help("수정")
        Button {
            if isHidden {
                settings.hiddenBuiltinIds.remove(originalId)
            } else {
                settings.hiddenBuiltinIds.insert(originalId)
            }
        } label: {
            Image(systemName: isHidden ? "eye.slash" : "eye")
        }
        .buttonStyle(.borderless)
        .help(isHidden ? "숨김 해제" : "숨기기")
        Button {
            settings.resetBuiltin(originalId)
        } label: {
            Image(systemName: "arrow.uturn.backward")
        }
        .buttonStyle(.borderless)
        .help("초기화")
        .disabled(!isOverridden && !isHidden)
    }
}
```

Add a new `@State`:

```swift
@State private var editingBuiltinId: String? = nil
```

Sheet's `onCommit` handler:

```swift
onCommit: { committed in
    if let bid = editingBuiltinId {
        settings.builtinOverrides[bid] = committed
    } else if let idx = editingIndex {
        settings.customActions[idx] = committed
    } else {
        settings.customActions.append(committed)
    }
    isEditing = false
    editingIndex = nil
    editingBuiltinId = nil
}
onCancel: {
    isEditing = false
    editingIndex = nil
    editingBuiltinId = nil
}
```

The Divider() between built-ins and customs stays.

## Acceptance Criteria

1. `swift build` succeeds with zero new warnings.
2. New files exist: `ActionKind.swift`, `SystemActionType.swift`,
   `SystemActionExecutor.swift`.
3. Settings "액션" section shows 7 built-ins (3 AI + 4 system) above
   the Divider, then custom actions below, then "새 액션 추가".
4. **Built-in editing**: clicking 수정 on a built-in opens the editor
   pre-filled. Saving stores an override in
   `settings.builtinOverrides[id]`. The ActionBar reflects the
   changed icon / label / prompt on the next selection cycle.
5. **Hide / unhide**: clicking the eye icon toggles `hiddenBuiltinIds`.
   Hidden built-ins disappear from the ActionBar AND render with
   secondary color + slash eye in Settings.
6. **Reset**: clicking the arrow.uturn icon removes the override
   AND clears any hidden flag for that id. Disabled when nothing
   to reset.
7. **System action: copy** — clicking 복사 on the ActionBar puts
   the selected text on the clipboard. Verify by pasting into a
   text editor. No ResponsePanel appears.
8. **System action: paste** — selecting some text in TextEdit, then
   clicking 붙여넣기, replaces that selection with the current
   clipboard text. AX-supported apps only. AX-untrusted gracefully
   no-ops (no crash).
9. **System action: webSearch** — clicking 웹 검색 opens the default
   browser with
   `https://www.google.com/search?q=<urlencoded selection>`.
10. **System action: lookUp** — clicking 사전 조회 opens the macOS
    Dictionary app (`dict://<word>`).
11. **CustomActionEditor category**: opening the editor shows a
    segmented Picker with "AI 액션" / "기본 기능". Selecting "기본
    기능" hides the Prompt field and shows a SystemActionType
    Picker. Saving creates a user custom action with `kind: .system`.
12. **Editing a system custom action** opens the editor in
    "기본 기능" mode with the correct SystemActionType pre-selected.
13. **Backward compat**: an existing `UserDefaults customActions`
    JSON (written by Phase 7, no `kind` / `systemType` fields)
    decodes successfully with `kind: .ai`, `systemType: nil`.
14. **Persistence**: builtinOverrides and hiddenBuiltinIds survive
    a kill + relaunch.
15. **No regression**: Phase 8 features (Agent / 응답 언어 / fish
    icon / Markdown rendering / fade / pin / hover-out / loading-
    show-guard / point-in-own-panels guard) continue to work.

## macOS edge-case checklist (Appendix C)

- [ ] Permissions: `paste` requires AX. Already requested at launch.
      No new permissions.
- [ ] Permission revoked at runtime: paste no-ops, copy/webSearch/
      lookUp still work.
- [ ] Key window: no new floating panels.
- [ ] Z-order: no change.
- [ ] Animation anchor: no change.
- [ ] Mouse / key event routing: no `CGEvent.post`. No new monitors.
- [ ] Cancellation: AI path unchanged (silent on `URLError(.cancelled)`
      / `CancellationError`).
- [ ] Resource cleanup: SystemActionExecutor is stateless.
- [ ] UserDefaults schema: ADDS `builtinOverrides` (Data, JSON Dict)
      and `hiddenBuiltinIds` (Data, JSON [String]).

## Out of Scope

- Reordering of built-in actions (custom action reorder stays).
- "복사 완료" toast — Phase 9.x follow-up.
- Drag-and-drop reorder between built-ins and customs.
- Sandbox-compatible paste implementation.
- AppleScript fallback for paste in AX-hostile apps — Phase 11.
- Importing / exporting action sets — post-v1.
- Streaming chat — Phase 16.
- Multi-provider — Phase 17.
