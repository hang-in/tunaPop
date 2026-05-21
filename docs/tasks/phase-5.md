# Phase 5 — Settings UX: Model discovery + Position picker

## Phase

Phase 5 of the production master plan. Master spec §20 entry "Phase 5"
covers both Model discovery (live Ollama `/api/tags`) and Position
picker (8-direction `ActionBarPosition`) UI exposure. This sub-spec
ships them together because both touch `SettingsView` + `AppSettings`,
and packaging them as a single PR avoids merge conflicts.

## References

- `docs/MASTER_SPEC.md` (this PR's source of truth)
- Master spec §3.5 (Settings v1) — fields and storage
- Master spec §12.3 (Model discovery)
- Master spec §14.3 (Settings window structure)
- Master spec §14.1 (ActionBar position semantics)
- Master spec Appendix B — macOS edge cases
- Master spec Appendix C — per-phase checklist (REQUIRED for this PR)

## Focus

Expose the existing `AppSettings.actionBarPosition` field via a Settings
UI control (8-direction menu picker) and add a Model picker that lists
installed Ollama models from `GET /api/tags`. Keep the existing
free-text model input as a fallback when fetch fails.

Files to add:
- (none new — the existing files cover this)

Files to modify:
- `Sources/TunaPop/OllamaClient.swift` (add `listModels()` API)
- `Sources/TunaPop/SettingsView.swift` (restructure into sections, add Model picker, add Position picker)

Files NOT to modify in this phase:
- `Sources/TunaPop/TunaPopApp.swift` (Settings window opening already deduped via `settingsWindow == nil` guard)
- `Sources/TunaPop/AppSettings.swift` (both fields already exist: `model`, `actionBarPosition`)
- everything else under `Sources/TunaPop/`

## Constraints

- macOS 14+, Swift 5.9+, SwiftUI + AppKit. No third-party deps.
- `@MainActor` on every type that mutates AppKit/SwiftUI state.
- Use `URLSession.shared` for the fetch (do not reuse internal Ollama
  request types — `listModels()` only decodes the model name list).
- `swift build` MUST succeed with zero new warnings.
- Korean tooltip text in master spec §3.7 is unchanged.
- Free-text model entry MUST remain available when fetch fails — never
  block the user behind a broken picker.
- Picker MUST default to the currently persisted `settings.model`
  value if that name exists in the fetched list; otherwise show
  "Custom: <value>" as a synthetic entry so the user can still see
  what is set.

## Required APIs

### `OllamaClient.listModels`

Add a new method:

```swift
extension OllamaClient {
    func listModels() async throws -> [String]
}
```

Behavior:
- Build `URL(string: endpoint.trimmingCharacters(...).appending("/api/tags"))`.
  Reuse the existing `URL(string:)` + `.appending(path:)` pattern from
  `chat(...)`. If the URL cannot be built, throw `OllamaError.invalidEndpoint`.
- `GET`, no body. Set `Authorization: Bearer <token>` only when the
  trimmed token is non-empty (same rule as `chat`).
- Decode the response as:
  ```swift
  private struct OllamaTagsResponse: Decodable {
      let models: [OllamaTagEntry]
  }
  private struct OllamaTagEntry: Decodable {
      let name: String
  }
  ```
- Return `response.models.map(\.name)`.
- Map non-2xx to `OllamaError.requestFailed(body)`.
- Catch and rethrow `URLError(.cancelled)` and `CancellationError`
  unchanged (callers will silence them per Appendix B).

`URL(string:)` + `appending(path:)` is the same shape currently in
`chat(...)`; do not introduce new URL-building helpers.

### `SettingsView` restructure

Layout the view as `Form` with three `Section`s:

```
Section("Ollama") {
    TextField("Endpoint", text: $settings.endpoint)
    HStack {
        Picker("Model", selection: $modelSelection) { ... }
        Button { Task { await refreshModels() } } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .help("모델 목록 새로고침")
    }
    if showsCustomModelField {
        TextField("Custom model", text: $customModelEntry)
    }
    SecureField("API token", text: $settings.apiToken)
}

Section("기본 동작") {
    TextField("Default prompt", text: $settings.defaultPrompt, axis: .vertical)
        .lineLimit(3...5)
    Picker("ActionBar 위치", selection: $settings.actionBarPosition) {
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

Section {
    if let error = fetchError {
        Text(error)
            .font(.caption)
            .foregroundStyle(.red)
    }
}
```

Local state in the view:

```swift
@State private var fetchedModels: [String] = []
@State private var lastFetched: Date?
@State private var isFetching = false
@State private var fetchError: String?
@State private var customModelEntry: String = ""
```

Derived bindings:

- `modelSelection`: `Binding<String>` over `settings.model`. The picker
  contents are:
  - All names in `fetchedModels`
  - **Plus** an explicit entry for `settings.model` itself if that
    value is not in `fetchedModels` and is non-empty, displayed as
    `"Custom: \(settings.model)"`
  - **Plus** a final entry `"Custom..."` whose tag is the empty string
    `""`. Selecting this reveals the `TextField("Custom model")` and
    binds it to `settings.model` via `customModelEntry`.
- `showsCustomModelField`: `settings.model.isEmpty` OR `settings.model`
  not in `fetchedModels`.

### `refreshModels()` behavior

```swift
@MainActor
private func refreshModels() async {
    guard !isFetching else { return }
    isFetching = true
    fetchError = nil
    defer { isFetching = false }
    do {
        let client = OllamaClient(endpoint: settings.endpoint, token: settings.apiToken)
        fetchedModels = try await client.listModels()
        lastFetched = Date()
    } catch is CancellationError {
        // silent
    } catch let urlError as URLError where urlError.code == .cancelled {
        // silent
    } catch {
        fetchError = error.localizedDescription
    }
}
```

### Auto-refresh policy

Wire `refreshModels()` via `.task` on the root `Form`:

```swift
.task {
    if lastFetched == nil || Date().timeIntervalSince(lastFetched!) > 60 {
        await refreshModels()
    }
}
```

The 60-second freshness window matches master spec §12.3.

### Position picker semantics

`settings.actionBarPosition` is already persisted in `UserDefaults`.
The Picker binds directly. When the user changes the value:
- The next ActionBar `show(...)` reads the new value via
  `settings.actionBarPosition` (already wired in `PopupController.show`).
- No restart required; the existing flow already re-reads on every
  show.

## Acceptance Criteria

(All criteria are runtime, user-verifiable.)

1. `swift build` succeeds with zero new warnings.
2. Open Settings while Ollama is running and reachable:
   - Within ~1 s, the Model field becomes a Picker populated with the
     installed model names.
   - If `settings.model` was previously set to an installed model,
     that entry is the picker's current selection.
3. Open Settings while Ollama is **not** running:
   - The Picker shows only `Custom..." plus any synthetic "Custom: <prev>"
     entry.
   - A red caption appears in the bottom section: e.g. "Could not
     connect to Ollama at http://localhost:11434".
   - The user can still type into the Custom model field and the
     value is persisted.
4. Choose a different installed model from the picker. Open the
   ActionBar (Show Test Popup or drag selection) and trigger an
   action. The LLM call uses the newly selected model. Switching back
   to the prior model still works.
5. Click the refresh button (`arrow.clockwise`). The list re-fetches.
6. Close and re-open the Settings window within 60 s: NO new fetch.
   After 60 s the next open triggers a fetch.
7. ActionBar position: change the "ActionBar 위치" picker from
   `↗ Top Right` to `↙ Bottom Left`. Trigger a new drag-select. The
   ActionBar appears in the bottom-left of the selection anchor (not
   top-right).
8. All 8 positions reachable. Each tested manually with a drag in the
   center of the screen renders the bar in the expected quadrant.
9. Clamping: drag-select near the bottom of the screen with position
   set to `↘ Bottom Right`. The bar stays inside `NSScreen.main?.visibleFrame`
   (existing clamp logic in `ActionBarPosition.origin(...)`).
10. Cancellation: while the picker is fetching, close the Settings
    window. No "canceled" text appears anywhere; the next open
    re-fetches cleanly.
11. Settings window is single-instance: clicking the menu item while
    the window is already open brings it forward; does not spawn a
    duplicate. (This is already true via the existing `if settingsWindow == nil` guard — verify it still holds.)
12. `URLError(.cancelled)` and `CancellationError` are silently
    swallowed by `refreshModels()`. No user-facing message for either.

## macOS edge-case checklist (Appendix C)

- [ ] Permissions: this PR does NOT introduce any new permissions.
      `listModels` is plain HTTP. AX/Input Monitoring unchanged.
- [ ] Permission revoked at runtime: N/A.
- [ ] Key window: no new windows. The Settings window remains a
      standard titled NSWindow.
- [ ] Z-order: no new floating panels.
- [ ] Animation anchor: N/A (no new animated panel).
- [ ] Event routing: only `URLSession` traffic. No new global event
      monitors.
- [ ] Cancellation: both `CancellationError` and `URLError(.cancelled)`
      are silently caught in `refreshModels()`.
- [ ] Resource cleanup: `.task` modifier's lifecycle is owned by
      SwiftUI; no manual cleanup needed.
- [ ] `UserDefaults` schema (§15.1): no new keys. `model` and
      `actionBarPosition` already exist.

## Out of Scope

- Settings window tab navigation (multiple tabs). v1 keeps the
  single Form. Tab UI is Phase 7 (custom actions tab) territory.
- 3×3 visual grid picker for position (`TBD` later UX upgrade).
  Phase 5 ships menu-style picker only.
- Persisting `lastFetched` across launches.
- Pulling new models from inside Settings (`ollama pull`). That is
  Phase 8b.
- Updating Privacy descriptions in Info.plist (Phase 12).
- Keychain for `apiToken` (Phase 6a).
- Showing a warning when `endpoint` is non-localhost (Phase 6b).
