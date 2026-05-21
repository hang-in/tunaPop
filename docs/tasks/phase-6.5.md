# Phase 6.5 — UX polish (auto-enable, Markdown rendering, icons, word/sentence prompt)

## Phase

Small UX-driven follow-up between Phase 6 and Phase 7 (Custom action
editor). Four items in one PR:

1. **Auto-enable Selection Monitor on launch** — remove the manual menu
   toggle step every session.
2. **Markdown rendering in ResponsePanel** — Ollama replies often include
   bold, italic, inline code, line breaks; render them natively.
3. **Icon refresh** — 설명 / 요약 / 번역 icons updated to a more
   intuitive set so users don't have to memorize what each glyph means.
4. **Word vs sentence detection for 번역** — when the selection looks
   like a single word (≤2 whitespace tokens AND ≤20 characters), switch
   the prompt to a dictionary-style explanation (Korean meaning, part of
   speech, short example). Sentence translations keep the existing
   prompt.

Custom action editing (per-action prompt customization in Settings)
remains Phase 7.

## References

- `docs/MASTER_SPEC.md` §13 (Action System), §14.2 (ResponsePanel),
  §3.7 (Menu bar)
- `docs/MASTER_SPEC.md` Appendix B (macOS API caveats), Appendix C
  (per-phase checklist)

## Focus

Make the default experience match what the user actually does in
practice: drag a word, get a useful explanation; drag a sentence, get
a translation; see formatted output. Stop forcing the user to enable
the selection monitor every launch.

Files to modify:
- `Sources/TunaPop/TunaPopApp.swift` — auto-enable selection monitor
- `Sources/TunaPop/ResponseView.swift` — Markdown rendering for `.success`
- `Sources/TunaPop/Action.swift` — icon updates
- `Sources/TunaPop/PopupController.swift` — word/sentence prompt resolution

Files NOT to modify:
- `Sources/TunaPop/AppSettings.swift`
- `Sources/TunaPop/SettingsView.swift`
- `Sources/TunaPop/Accessibility.swift`
- `Sources/TunaPop/InputMonitoring.swift`
- `Sources/TunaPop/KeychainHelper.swift`
- `Sources/TunaPop/SelectionExtractor.swift`
- `Sources/TunaPop/SelectionMonitor.swift`
- `Sources/TunaPop/SelectionPayload.swift`
- `Sources/TunaPop/OllamaClient.swift`
- `Sources/TunaPop/ResponsePanel.swift`
- `Sources/TunaPop/ResponseState.swift`
- `Sources/TunaPop/ActionBarPanel.swift`
- `Sources/TunaPop/ActionBarView.swift`
- `Sources/TunaPop/ActionBarPosition.swift`
- `Sources/TunaPop/KeyableNonActivatingPanel.swift`
- `Sources/TunaPop/TooltipImageButton.swift`

## Constraints

- macOS 14+, Swift 5.9+, SwiftUI + AppKit. No new third-party deps.
- `@MainActor` everywhere AppKit/SwiftUI mutates.
- `swift build` MUST succeed with zero new warnings.
- Korean strings stay as written below; do not invent new copy.
- Comments minimal. No emoji.
- Keep the Phase 6 Cleanup diagnostic NSLog in `SelectionMonitor.swift`
  (mouseDown clickCount log + triggerSelection log) — they will be
  removed in a later cleanup PR after user verification.

---

## Required changes

### 1. Auto-enable Selection Monitor (`TunaPopApp.swift`)

In `AppDelegate.applicationDidFinishLaunching(_:)`, after
`configureStatusItem()` and `Accessibility.requestIfNeeded()` (and the
existing AX launch log line), call the existing toggle method to flip
state and start the monitor:

```swift
toggleSelectionMonitoring()
```

`toggleSelectionMonitoring()` already:
- toggles `isSelectionMonitoringEnabled`
- starts the monitor
- updates the menu item title to "Disable Selection Monitor"
- sets `selectionMonitoringItem?.state = .on`

That's exactly the behavior we want. Do NOT inline duplicate logic;
call the existing method.

Acceptable side effect: if `Accessibility.isTrusted == false`, the
monitor still starts but its callback returns nil. No crash, no
ActionBar. The user can grant permission and the monitor begins
working without a restart.

### 2. Markdown rendering in `ResponseView`

Replace the `.success(let text, let metadata)` case's `Text(text)` with
a Markdown-rendered `Text(AttributedString)`.

Add a helper at the bottom of the struct:

```swift
private func markdownAttributed(_ raw: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace
    )
    if let attributed = try? AttributedString(markdown: raw, options: options) {
        return attributed
    }
    return AttributedString(raw)
}
```

`interpretedSyntax: .inlineOnlyPreservingWhitespace` renders inline
formatting (`**bold**`, `*italic*`, `` `code` ``, links) while keeping
line breaks visible and leaving block constructs (headings, fenced
code blocks, lists) as plain text. This is the safest default for
macOS 14+ without pulling in a Markdown library.

Then in the body:

```swift
case .success(let text, let metadata):
    VStack(alignment: .leading, spacing: 6) {
        ScrollView {
            Text(markdownAttributed(text))
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

`.textSelection(.enabled)` MUST be preserved so the user can still
select and copy parts of the formatted output via the system menu.

The copy button in the header continues to copy the RAW response
(`lastResponse`, not the rendered AttributedString). That behavior is
owned by `PopupController.copyResponse` — do not change it.

### 3. Icon updates in `Action.defaults`

Change three `systemImage` values:

| Action | Before | After |
|---|---|---|
| `explain` | `text.alignleft` | `text.bubble` |
| `summarize` | `list.bullet` | `list.bullet.rectangle` |
| `translate` | `globe` | `character.bubble` |

The labels (`설명` / `요약` / `번역`) and prompts stay unchanged.
`Action.defaults` is the single source of truth — no other file should
need editing for the icon change.

Confirm all three SF Symbols exist in the macOS 14 SF Symbols catalog.
If any is missing, fall back to:
- `text.bubble` → `bubble.left`
- `list.bullet.rectangle` → `list.bullet`
- `character.bubble` → `text.book.closed`

Use the primary choice unless the build emits an "unknown SF Symbol"
warning at compile time.

### 4. Word vs sentence prompt resolution (`PopupController.swift`)

When the user clicks 번역 (the action whose `id == "translate"`) and
the selection looks like a single word (or very short phrase), use a
dictionary-style prompt instead of the standard translation prompt.

In `handleAction(_:)`, replace the existing

```swift
let prompt = action.prompt
```

with

```swift
let prompt = resolvePrompt(for: action, payload: payload)
```

Add two private helpers anywhere in the type:

```swift
private func resolvePrompt(for action: Action, payload: SelectionPayload) -> String {
    if action.id == "translate", case .text(let text) = payload, isShortWord(text) {
        return "다음 선택된 단어를 한국어 사전 형식으로 풀어 주세요. 의미, 품사, 짧은 예문 한 줄을 포함하세요."
    }
    return action.prompt
}

private func isShortWord(_ raw: String) -> Bool {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count > 20 { return false }
    let tokens = trimmed.split(whereSeparator: { $0.isWhitespace })
    return tokens.count <= 2
}
```

Notes:
- The selection text itself is NOT inserted into the prompt body.
  `OllamaClient.chat` already appends `"\n\nSelection:\n\(text)"`
  automatically when `payload == .text(...)`. Avoid duplicating the
  text in the prompt.
- For image payloads we never enter the short-word branch.
- The threshold (≤2 tokens AND ≤20 chars) is intentional. A 25-char
  hyphenated phrase or a 3-word phrase counts as a sentence.

## Acceptance Criteria

1. `swift build` succeeds with zero new warnings.
2. **Launch behavior**: starting `swift run TunaPop` results in the
   Selection Monitor automatically enabled — the menu item reads
   "Disable Selection Monitor" with the check state on, immediately
   after launch. A drag-select in TextEdit triggers the ActionBar
   without any prior menu interaction.
3. **Markdown rendering**: trigger a 설명 action against a prompt that
   returns Markdown text (e.g. text containing `**bold**` or
   `` `code` ``). The bold portion renders in bold; inline code uses
   a monospace style; line breaks are preserved. Block-level Markdown
   (`# Heading`, fenced code blocks, bulleted lists) renders as plain
   text — this is acceptable for v1.
4. **Copy still copies the raw text**: clicking the copy button puts
   the original unformatted Markdown string on the clipboard, NOT the
   rendered AttributedString. Verify by pasting into a plain text
   editor.
5. **Icons**: the ActionBar now shows `text.bubble`,
   `list.bullet.rectangle`, `character.bubble`. Tooltips remain
   설명 / 요약 / 번역.
6. **Word-mode translate**: selecting a single English word (e.g.
   `serendipity`) and clicking 번역 produces a dictionary-style
   response (meaning, part of speech, example), not a one-line
   translation.
7. **Sentence-mode translate**: selecting a sentence (≥3 tokens or
   >20 chars) and clicking 번역 produces a standard translation.
8. **Edge case**: a 2-word selection like `Hello world` (11 chars, 2
   tokens) → word mode. A 20-char selection like
   `Lorem ipsum dolor a.` (20 chars, 4 tokens) → sentence mode
   (token count overrides).
9. **No regression**: pin / fade / outside-click dismiss /
   hover-out / Keychain token / non-localhost warning / iTerm2 cmd+c
   all continue to work as in Phase 6 Cleanup.
10. **AX-disabled case**: launching with AX permission revoked does
    NOT crash. The auto-enabled monitor's callback returns nil and
    no ActionBar appears. The status bar icon shows the orange
    tint per Phase 6.
11. `Action` struct shape is unchanged. Only the `defaults` array's
    `systemImage` values change.

## macOS edge-case checklist (Appendix C)

- [ ] Permissions: no new permission introduced.
- [ ] Permission revoked at runtime: covered by AC #10.
- [ ] Key window: no change.
- [ ] Z-order: no change.
- [ ] Animation anchor: no change.
- [ ] Mouse / key event routing: no change. Auto-enable just calls the
      existing `toggleSelectionMonitoring()` method.
- [ ] Cancellation: no change.
- [ ] Resource cleanup: no new monitors / timers / observers.
- [ ] `UserDefaults` schema: no change.

## Out of Scope

- Settings UI for per-action prompt editing (Phase 7).
- Adding / removing / reordering custom actions (Phase 7).
- Streaming chat (Phase 16).
- Persisting "Selection Monitor enabled" preference (the current
  behavior is always-on; if users want to disable it, the menu toggle
  still exists).
- Full block-level Markdown rendering (headings, lists, fenced code).
  v1 ships inline-only.
- Removing the SelectionMonitor diagnostic NSLogs (separate cleanup
  PR after user confirms double-click works).
