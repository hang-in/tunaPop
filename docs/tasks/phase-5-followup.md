# Phase 5 Follow-up — Loading-hides-ActionBar + Response metadata status bar

## Phase

Follow-up to Phase 5. Two UX-driven changes the user requested after
running Phase 5 + Phase 4 cleanup manually:

1. **Hide ActionBar while a response is being generated**. This
   replaces Phase 4 acceptance #7 ("ActionBar stays visible — multiple
   actions allowed") with the simpler PopClip flow: one action per
   selection cycle. When the user clicks an icon, the ActionBar
   immediately disappears and only the ResponsePanel remains until the
   user dismisses (ESC / outside-click / hover-out / pin then dismiss).
2. **Show model name and token count under the response**. A small
   secondary caption at the bottom of `ResponseView` in `.success`
   state: `model: <name> · tokens: <eval+prompt>`.

## References

- `docs/MASTER_SPEC.md` Appendix B (macOS API caveats) + Appendix C
  (per-phase checklist)
- `docs/tasks/popclip-ux-phase-4.md` — note that acceptance #7 is
  deliberately superseded by this follow-up
- Ollama `/api/chat` non-streaming response includes `model`,
  `prompt_eval_count`, `eval_count`, `total_duration`.

## Focus

Make the ActionBar a single-shot UI element: it disappears on click.
Make the LLM call return enough metadata to display model + tokens
under the response. Plumb the metadata through `ResponseState` so
`ResponseView` renders it next to the response text.

Files to modify:
- `Sources/TunaPop/OllamaClient.swift` (extend chat return type with metadata)
- `Sources/TunaPop/ResponseState.swift` (add metadata to `.success` case)
- `Sources/TunaPop/ResponsePanel.swift` (forward metadata into the view)
- `Sources/TunaPop/ResponseView.swift` (render the status bar)
- `Sources/TunaPop/PopupController.swift` (dismiss ActionBar on action click, pass metadata)

Files NOT to modify:
- `Sources/TunaPop/Action.swift`
- `Sources/TunaPop/ActionBarPanel.swift` (no new behavior — just called via existing `dismiss()`)
- `Sources/TunaPop/ActionBarView.swift`
- `Sources/TunaPop/ActionBarPosition.swift`
- `Sources/TunaPop/AppSettings.swift`
- `Sources/TunaPop/SelectionExtractor.swift`
- `Sources/TunaPop/SelectionMonitor.swift`
- `Sources/TunaPop/SelectionPayload.swift`
- `Sources/TunaPop/SettingsView.swift`
- `Sources/TunaPop/Accessibility.swift`
- `Sources/TunaPop/KeyableNonActivatingPanel.swift`
- `Sources/TunaPop/TooltipImageButton.swift`
- `Sources/TunaPop/TunaPopApp.swift`

## Constraints

- macOS 14+, Swift 5.9+, SwiftUI + AppKit. No third-party deps.
- `@MainActor` everywhere AppKit/SwiftUI mutates.
- `swift build` MUST succeed with zero new warnings.
- Do NOT change `OllamaClient.chat` signature in a way that would
  require touching files outside the list above. Specifically: the
  signature change MUST stay in `(model:prompt:payload:)` parameters,
  only the return type changes.
- Do NOT re-introduce `NSEvent.addLocalMonitor` / `addGlobalMonitor`
  in `PopupController`. The Phase 4 `cancelOperation` +
  `windowDidResignKey` + SwiftUI `.onHover` model is the policy.

## Required changes

### 1. `OllamaClient.swift`

Add a public result struct and change `chat` to return it.

```swift
struct OllamaChatResult: Equatable, Sendable {
    let content: String
    let model: String
    let evalCount: Int
    let promptEvalCount: Int
}
```

Update `chat` signature:

```swift
func chat(model: String, prompt: String, payload: SelectionPayload) async throws -> OllamaChatResult
```

Update the private `OllamaChatResponse` decoder to include the
metadata fields:

```swift
private struct OllamaChatResponse: Decodable {
    let model: String?
    let message: OllamaMessage
    let promptEvalCount: Int?
    let evalCount: Int?

    private enum CodingKeys: String, CodingKey {
        case model
        case message
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }
}
```

In `chat(...)`, after decoding, construct the result:

```swift
let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
return OllamaChatResult(
    content: decoded.message.content,
    model: decoded.model ?? model,
    evalCount: decoded.evalCount ?? 0,
    promptEvalCount: decoded.promptEvalCount ?? 0
)
```

The `model ?? model` fallback uses the request's `model` argument when
the server omits it from the response (Ollama always includes it, but
the field is defensive).

`listModels(...)` stays unchanged.

### 2. `ResponseState.swift`

Replace the existing `.success(String)` with a struct-bearing case:

```swift
enum ResponseState: Equatable {
    case idle
    case loading
    case success(String, ResponseMetadata?)
    case failure(String)
}

struct ResponseMetadata: Equatable {
    let model: String
    let totalTokens: Int  // promptEvalCount + evalCount
}
```

The `.success` case carries the response text plus optional metadata.
`Optional` so future providers (or stubbed responses) without metadata
still type-check.

### 3. `ResponsePanel.swift`

No behavioral change — only the hosting view rebuild path now passes
the current state (already a `ResponseState`) which already carries
metadata. The view receives whichever metadata the latest `update(state:)`
call carries.

### 4. `ResponseView.swift`

Update the `.success` case body to render:

```swift
case .success(let text, let metadata):
    VStack(alignment: .leading, spacing: 6) {
        ScrollView {
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 60, maxHeight: 280)
        if let metadata {
            Text("model: \(metadata.model) · tokens: \(metadata.totalTokens)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
```

The metadata caption SHOULD use `font(.caption2)` and
`foregroundStyle(.secondary)` so it does not visually compete with the
response text.

### 5. `PopupController.swift`

#### 5a. Hide ActionBar on action click

In `handleAction(_:)`, BEFORE calling `responsePanel.show(...)`:

- Capture `actionBarPanel.frame` into a local constant (needed for the
  response anchor math).
- Then call `actionBarPanel.dismiss()`.
- Remove the trailing `actionBarPanel.bringToFront()` call — there is
  no longer an ActionBar to bring forward.

The response anchor math (`belowY`, `aboveY`, `resolvedY`, `anchorMode`,
`origin`) MUST use the captured frame, NOT a re-read after dismiss.

#### 5b. Pass metadata into `.success`

When the `chat(...)` Task completes successfully:

```swift
let result = try await client.chat(model: model, prompt: prompt, payload: payloadCopy)
try Task.checkCancellation()
guard let self else { return }
self.lastResponse = result.content
let metadata = ResponseMetadata(
    model: result.model,
    totalTokens: result.promptEvalCount + result.evalCount
)
self.responsePanel.update(state: .success(result.content, metadata))
```

Cancellation handling (`CancellationError` + `URLError(.cancelled)`)
stays silent, identical to today.

#### 5c. `windowDidResignKey` audit

This change removes the case where the user has the ActionBar AND a
ResponsePanel up at the same time. `windowDidResignKey` still
correctly handles dismissal: when the (single) visible panel loses
key, the existing logic dismisses it unless pinned or loading. No
change required to that method.

#### 5d. Outside-click during ActionBar-only state

When ActionBar is visible but no ResponsePanel yet (the very first
state right after a selection), the user might click outside before
picking an action. With ActionBar key + `windowDidResignKey`, that
click drops key from the ActionBar and dismisses. Good — keep existing
behavior. Confirm in the audit that the new `actionBarPanel.dismiss()`
inside `handleAction` does NOT also accidentally invoke
`windowDidResignKey → dismiss()` recursively. In practice
`actionBarPanel.dismiss()` calls `panel.orderOut(nil)` which triggers
`windowDidResignKey` asynchronously; by the time the dispatch fires,
`NSApp.keyWindow` is the responsePanel.nsPanel, so the guard `keyWindow != ... && keyWindow != ...` rejects it. Verify this
explicitly in the report.

## Acceptance Criteria

1. `swift build` succeeds with zero new warnings.
2. Drag-select → ActionBar appears.
3. Click an icon → ActionBar **immediately disappears**; ResponsePanel
   appears in its place (using the just-captured ActionBar frame as
   anchor reference).
4. While loading, the ResponsePanel shows the loading state and no
   other panel is visible. Outside-click during loading does NOT
   dismiss (existing behavior preserved).
5. When the response arrives:
   - Body shows the response text.
   - A small caption at the bottom-right of the body reads
     `"model: <name> · tokens: <int>"` where `<int>` is
     `promptEvalCount + evalCount`.
   - The caption uses `.caption2` font and `.secondary` foreground.
6. Outside-click after response → entire popup fades out (existing
   behavior).
7. ESC at any state → fade out (existing behavior).
8. Pin toggle → pin/pin.fill, outside-click and hover-out ignored,
   ESC still dismisses (existing behavior).
9. No "canceled" text ever surfaces (existing silent-cancel behavior
   preserved).
10. After dismissing, the next selection cycle shows a fresh
    ActionBar (NOT a previously cached one).
11. `OllamaChatResult` is `Sendable`. `ResponseMetadata` is `Equatable`.
12. The metadata caption is omitted when `metadata` is nil — no
    placeholder text.

## macOS edge-case checklist (Appendix C)

- [ ] Permissions: no change.
- [ ] Permission revoked at runtime: no new path.
- [ ] Key window: only one panel visible at a time after action click.
      Audit explicitly that `windowDidResignKey` does not spuriously
      fire when ActionBar is dismissed inside `handleAction`.
- [ ] Z-order: simplified — only one panel visible during loading and
      response. No more `bringToFront` need.
- [ ] Animation anchor: ResponsePanel anchor math unchanged. Capture
      ActionBar frame BEFORE dismissing it.
- [ ] Event routing: `cancelOperation` on ResponsePanel still receives
      ESC. ActionBar still receives `cancelOperation` until the user
      picks an action.
- [ ] Cancellation: both error types silent.
- [ ] Resource cleanup: dismiss path unchanged.
- [ ] UserDefaults schema: no change.

## Out of Scope

- Multi-provider abstraction (Phase 17).
- Streaming chat (Phase 16).
- Showing `total_duration` in the caption.
- Showing cost in dollars.
- Localizing the caption (it is "model:" / "tokens:" in English by
  design; i18n is Phase 9).
- Per-token cost coloring or warnings.
- Re-show-ActionBar-after-response UX. This follow-up explicitly
  commits to "one action per selection cycle".
