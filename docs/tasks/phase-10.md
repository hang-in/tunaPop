# Phase 10 — Logging cleanup (NSLog → os_log)

## Phase

Phase 10 of the production master plan. The codebase accumulated ~29
diagnostic `NSLog(...)` calls during Phases 4–9 troubleshooting.
This phase replaces them with a unified `Logger` wrapper over
`os.Logger` (Apple's modern unified logging API), adds category
buckets, and gates verbose diagnostic logs behind a Settings toggle
so production runs are quiet.

## References

- `docs/MASTER_SPEC.md` §8 (Telemetry & Observability)
- `docs/MASTER_SPEC.md` Appendix B / C

## Focus

Stop polluting Console.app with always-on `NSLog` lines. Move to
`os.Logger` with subsystem `"app.tunapop"` and per-area categories.
A `verboseLogging` UserDefaults flag controls `.debug` output;
`.info` and `.error` always emit. Console.app filter
`subsystem:app.tunapop` shows everything tunaPop logs.

Files to add:
- `Sources/TunaPop/Logger.swift` — centralized os.Logger facade

Files to modify (every file currently calling `NSLog`):
- `Sources/TunaPop/SelectionMonitor.swift`
- `Sources/TunaPop/SelectionExtractor.swift`
- `Sources/TunaPop/PopupController.swift`
- `Sources/TunaPop/ResponsePanel.swift`
- `Sources/TunaPop/ActionBarPanel.swift`
- `Sources/TunaPop/TunaPopApp.swift`
- `Sources/TunaPop/AppSettings.swift` — add `verboseLogging`
- `Sources/TunaPop/SettingsView.swift` — add a "고급" Section with
  the verbose toggle

Files NOT to modify:
- everything else.

## Constraints

- macOS 14+, Swift 5.9+. No new third-party deps.
- `@MainActor` everywhere AppKit/SwiftUI mutates. `Logger` itself
  is plain `enum` with `static` members; `os.Logger` is thread-safe.
- `swift build` MUST succeed with zero new warnings.
- All `NSLog("tunaPop ...")` calls MUST be replaced. No mixed style
  (no `NSLog` alongside `Logger.x.info(...)` calls in the same file
  after the change).
- Category routing: `selection`, `popup`, `network`, `permissions`,
  `system`. See mapping below.
- Backward compat: existing `verboseLogging` value default is `false`
  (off). Existing users see fewer logs after upgrade.

---

## Required types

### `Logger.swift` (new)

```swift
import Foundation
import os

enum Log {
    private static let subsystem = "app.tunapop"

    static let selection = os.Logger(subsystem: subsystem, category: "selection")
    static let popup = os.Logger(subsystem: subsystem, category: "popup")
    static let network = os.Logger(subsystem: subsystem, category: "network")
    static let permissions = os.Logger(subsystem: subsystem, category: "permissions")
    static let system = os.Logger(subsystem: subsystem, category: "system")

    @MainActor
    static var isVerbose: Bool { Self.verboseFlag }

    @MainActor
    static func setVerbose(_ enabled: Bool) {
        Self.verboseFlag = enabled
    }

    @MainActor
    private static var verboseFlag: Bool = UserDefaults.standard.bool(forKey: "verboseLogging")
}
```

Notes:
- `os.Logger` automatically suppresses `.debug` in release builds and
  in Console.app's default filter. Verbose flag is an additional
  gate for our app's own `.debug` calls.
- We use `os.Logger` (uppercase O) — it's Apple's preferred modern
  API. Not `OSLog` (the older C-level API).

### Logging style

All call sites use direct `Log.<category>.<level>(...)`. Example:

```swift
Log.selection.debug("triggerSelection at \(point.x), \(point.y)")
Log.popup.info("dismiss called")
Log.network.error("Ollama request failed: \(message, privacy: .public)")
```

`os.Logger` uses interpolation literals; default privacy is `.private`
for arbitrary strings. For known-safe strings use `, privacy: .public`.
For potentially-user-text strings (e.g. selection text, response
content) DO NOT log them at all — those are private and should stay
out of any logger.

### `AppSettings.swift` — verbose toggle

Add a `@Published var verboseLogging: Bool` published property:

```swift
@Published var verboseLogging: Bool {
    didSet {
        UserDefaults.standard.set(verboseLogging, forKey: Self.verboseLoggingKey)
        Log.setVerbose(verboseLogging)
    }
}

private static let verboseLoggingKey = "verboseLogging"
```

In `init()`:

```swift
verboseLogging = UserDefaults.standard.bool(forKey: Self.verboseLoggingKey)
Log.setVerbose(verboseLogging)
```

### `SettingsView.swift` — 고급 section

Add a new `Section("고급")` BEFORE the version footer section:

```swift
Section("고급") {
    Toggle("진단 로그 표시", isOn: $settings.verboseLogging)
    Text("켜면 Console.app에서 subsystem:app.tunapop 으로 자세한 로그를 볼 수 있습니다.")
        .font(.caption2)
        .foregroundStyle(.secondary)
}
```

The toggle drives `AppSettings.verboseLogging`, which triggers
`Log.setVerbose(...)`. No restart needed.

### NSLog migration mapping

Replace each `NSLog("tunaPop <category>: ...")` with the
corresponding `Log.<category>.<level>(...)`. Suggested mapping by
category and level:

| Current `NSLog` content | New call |
|---|---|
| `SelectionMonitor: started ...` | `Log.selection.info("SelectionMonitor started (axTrusted=\(Accessibility.isTrusted))")` |
| `SelectionMonitor: addGlobalMonitorForEvents returned nil` | `Log.selection.error("addGlobalMonitorForEvents returned nil")` |
| `SelectionMonitor: mouseDown clickCount=...` | `Log.selection.debug("mouseDown clickCount=\(clickCount)")` |
| `SelectionMonitor: triggerSelection at ...` | `Log.selection.debug("triggerSelection delay=\(delayMillis)")` |
| `SelectionExtractor: AX not trusted ...` | `Log.permissions.info("AX not trusted")` |
| `SelectionExtractor: AX returned no text ...` | `Log.selection.debug("AX returned no text; no fallback in v1")` |
| `permissions at launch: AX=...` | `Log.permissions.info("at launch AX=\(Accessibility.isTrusted) IM=\(InputMonitoring.isTrusted)")` |
| `togglePin: before=... after=...` | `Log.popup.debug("togglePin before=\(beforePinned) after=\(responsePanel.pinned)")` |
| `hoverState: ...` | `Log.popup.debug("hoverState actionBar=\(...) response=\(...) pinned=\(...)")` |
| `hoverState: skip schedule (pinned)` | `Log.popup.debug("hoverState skip schedule pinned")` |
| `hoverState: skip schedule (loading)` | `Log.popup.debug("hoverState skip schedule loading")` |
| `hoverState: scheduling hide timer` | `Log.popup.debug("hoverState scheduling hide timer")` |
| `dismissIfOutside: point=... inAction=... inResponse=...` | `Log.popup.debug("dismissIfOutside inAction=\(inAction) inResponse=\(inResponse) pinned=\(responsePanel.pinned)")` |
| `dismissIfOutside: dismissing` | `Log.popup.debug("dismissIfOutside dismissing")` |
| `dismiss: called` | `Log.popup.debug("dismiss called")` |
| `show ignored: response still loading` | `Log.popup.debug("show ignored, still loading")` |
| `ResponsePanel.setPinned: ...` | `Log.popup.debug("ResponsePanel setPinned new=\(pinned) was=\(isPinned)")` |
| `ResponsePanel.dismiss called ...` | `Log.popup.debug("ResponsePanel dismiss called pinned=\(isPinned)")` |
| `ResponsePanel.dismissAnimated called ...` | `Log.popup.debug("ResponsePanel dismissAnimated called pinned=\(isPinned)")` |
| `ActionBarPanel: show origin=...` | `Log.popup.debug("ActionBarPanel show size=\(size.width)x\(size.height) level=\(panel.level.rawValue)")` |
| `selection callback: ignored ...` | `Log.selection.debug("selection callback ignored, point in own panel")` |
| `Selected text 좌표/내용` 로그 | **REMOVE** — never log user selection text |

Important transforms:
- DO NOT log raw selection text, response content, API tokens,
  endpoints. Anything user-typed or user-selected stays out of logs.
- The current `ActionBarPanel: show origin=(x, y)` log includes
  coordinates. Coordinates are not sensitive; keep them. Remove any
  log line that prints a user's text.
- `os.Logger.debug(...)` is automatically gated by `verboseFlag`
  AT CALL SITE: wrap with `if Log.isVerbose { Log.popup.debug(...) }`
  for any `debug` call that does string interpolation work, so the
  hot path (production) skips the interpolation entirely. For
  `.info` and `.error`, no guard.

Wrapping pattern:

```swift
if Log.isVerbose { Log.popup.debug("dismissIfOutside inAction=\(inAction)") }
```

This is verbose but avoids the perf cost of `os.Logger`'s
default-private string serialization during normal operation. The
wrap is mechanical — apply to every `.debug` call. Skip for
`.info`/`.error`.

## Acceptance Criteria

1. `swift build` succeeds with zero new warnings.
2. `Sources/TunaPop/Logger.swift` exists with the API shape above.
3. `grep -r "NSLog" Sources/` returns ZERO matches (or only `NSLog`
   inside the migration comment — preferably zero).
4. Launch the app with `verboseLogging = false` (default). Console.app
   filtered by `subsystem:app.tunapop` shows ONLY `.info` /
   `.error` lines (e.g. "SelectionMonitor started", "at launch
   AX=...").
5. Toggle the new "고급 → 진단 로그 표시" switch ON. Within ~1 sec,
   subsequent ActionBar / popup interactions emit `.debug` lines to
   Console.app.
6. Toggle the switch OFF. `.debug` lines stop emitting.
7. No log line contains:
   - selection text content
   - LLM response content
   - API tokens
   - full HTTP URLs with query parameters
8. `AppSettings.verboseLogging` is persisted across launches.
9. No regression: the app's UI behavior is unchanged. Logging is
   the only thing that changes.
10. `Log.isVerbose` and `Log.setVerbose(_:)` are `@MainActor`.

## macOS edge-case checklist (Appendix C)

- [ ] Permissions: no new permissions.
- [ ] Permission revoked at runtime: no new path.
- [ ] Key window: no change.
- [ ] Z-order: no change.
- [ ] Animation anchor: no change.
- [ ] Mouse / key event routing: no change.
- [ ] Cancellation: no change.
- [ ] Resource cleanup: `os.Logger` instances are static; no
      teardown.
- [ ] UserDefaults schema: ADDS `verboseLogging` (Bool, default
      false).

## Out of Scope

- File-based log rotation (`~/Library/Logs/tunaPop/`) — Phase 10.x
  follow-up if needed.
- Sending logs to a remote server (no telemetry by default per
  master spec).
- Removing the diagnostic logs entirely — they remain, but at
  `.debug` level gated by `verboseFlag`.
- `os.signpost` instrumentation for performance traces — separate
  perf phase.
- An "Open Console.app" menu item — UX polish later.
