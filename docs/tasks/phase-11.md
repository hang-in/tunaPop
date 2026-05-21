# Phase 11 — AppleScript fallback for AX-hostile apps

## Phase

Phase 11 of the production master plan. Adds an AppleScript-based
fallback so selection capture works in Firefox, iTerm2, and other
apps that don't expose `kAXSelectedTextAttribute` through the
Accessibility API.

## References

- `docs/MASTER_SPEC.md` §5 (Privacy & Permissions matrix)
- `docs/MASTER_SPEC.md` Appendix B (macOS API caveats — note the
  earlier `CGEvent.post` failures and pasteboard fallback decision)
- `docs/tasks/phase-6.md` — current AX-only behavior

## Focus

When AX returns no selected text, synthesize Cmd+C via
`NSAppleScript` (`System Events → keystroke "c" using {command down}`),
read the pasteboard, restore the original clipboard. This requires
**Apple Events automation permission** for "System Events", which is
a different TCC bucket than Accessibility / Input Monitoring.

Files to add:
- `Sources/TunaPop/AppleScriptCopySimulator.swift` — encapsulates
  the synthesize-Cmd+C-via-AppleScript step

Files to modify:
- `Sources/TunaPop/SelectionExtractor.swift` — re-enable a fallback,
  but route through `AppleScriptCopySimulator` instead of
  `CGEvent.post`

Files NOT to modify:
- Anything else.

## Constraints

- macOS 14+, Swift 5.9+. No new third-party deps.
- `@MainActor` everywhere AppKit/SwiftUI mutates.
- `swift build` MUST succeed with zero new warnings.
- Apple Events permission MUST be requested LAZILY — only when the
  user actually tries to select in an AX-hostile app. NEVER request
  on launch.
- The pasteboard MUST be restored to its previous contents after
  the synthesized copy. Even if AppleScript fails. Even on
  exception.
- No `CGEvent.post(...)`. The previous failed approach is dead.
- If AppleScript returns an error (permission denied, script failure,
  System Events not running), the function returns nil WITHOUT
  showing a UI dialog. The user already gets the macOS
  "tunaPop wants to control System Events" dialog from AppleScript
  itself the first time.

## Required types

### `AppleScriptCopySimulator.swift` (new)

```swift
import AppKit
import Foundation

@MainActor
enum AppleScriptCopySimulator {
    // Returns the text captured from the pasteboard after a synthesized
    // Cmd+C. Returns nil if AppleScript fails, permission is denied, or
    // the clipboard did not change.
    static func captureSelection() async -> String? {
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        let previousItems = pasteboard.pasteboardItems?.compactMap {
            $0.copy() as? NSPasteboardItem
        } ?? []

        defer {
            pasteboard.clearContents()
            pasteboard.writeObjects(previousItems)
        }

        guard runCopyScript() else { return nil }

        try? await Task.sleep(for: .milliseconds(160))

        guard pasteboard.changeCount != previousChangeCount else {
            return nil
        }

        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return nil
    }

    private static func runCopyScript() -> Bool {
        let source = """
        tell application "System Events"
            keystroke "c" using {command down}
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return false }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            NSLog("tunaPop AppleScriptCopySimulator error: \(errorInfo)")
            return false
        }
        _ = result
        return true
    }
}
```

Notes:
- Pasteboard restore uses `defer`, so even an early `return nil` or
  a thrown error restores the user's clipboard.
- `NSPasteboardItem.copy()` is a deep copy of the item; storing
  these instead of the raw item pointers keeps the previous
  clipboard intact even after `clearContents()`.
- The 160 ms sleep mirrors the previous pasteboard fallback delay —
  System Events needs that long to deliver the keystroke and for
  the frontmost app to populate the pasteboard.
- The first time this runs in a session, macOS shows the standard
  "tunaPop wants to control System Events" Automation dialog. The
  user grants once, decision persists per-bundle.

### `SelectionExtractor.swift` change

The current code:

```swift
if let text = accessibilitySelectedText(), !text.isBlank {
    return .text(text)
}
NSLog("tunaPop SelectionExtractor: AX returned no text; pasteboard fallback disabled for v1 stability (revisit in Phase 6b)")
return nil
```

Replace with:

```swift
if let text = accessibilitySelectedText(), !text.isBlank {
    return .text(text)
}

if let text = await AppleScriptCopySimulator.captureSelection(),
   !text.isBlank {
    return .text(text)
}

NSLog("tunaPop SelectionExtractor: AX + AppleScript both returned no text")
return nil
```

The AX-trusted gate at the top of `currentSelection()` stays — both
paths require AX permission (AppleScript is a separate TCC bucket
but the user always has both in practice; for v1 we don't add
extra checks).

Remove the existing `pasteboardSelection()` and `sendCopyShortcut()`
private functions from `SelectionExtractor.swift` — they are dead
code now (the `CGEvent.post` path is permanently retired). Also
remove the `import IOKit.hid` if no longer used in that file
(Phase 6 cleanup left it as the `InputMonitoring.swift` module).

`String.isBlank` extension stays.

## Acceptance Criteria

1. `swift build` succeeds with zero new warnings.
2. New file `AppleScriptCopySimulator.swift` exists with the API
   shape above.
3. `SelectionExtractor.swift` no longer contains `CGEvent.post`,
   `sendCopyShortcut`, or `pasteboardSelection`. The
   `currentSelection()` flow is: AX trusted → AX text → (if empty)
   AppleScript fallback → nil.
4. **Firefox**: drag-select text on a webpage. Within ~250 ms (AX
   path failure + 200 ms double-click delay + 160 ms AppleScript
   delay) the ActionBar appears. On first run, macOS shows the
   Automation permission dialog; after grant, subsequent selections
   work silently.
5. **iTerm2**: drag-select text. Same flow — ActionBar appears.
6. **Clipboard restoration**: before testing, copy `"BEFORE_TEST"`
   to the clipboard. Then drag-select in Firefox; after the
   ActionBar appears, paste in TextEdit — clipboard should still
   contain `"BEFORE_TEST"` (the synthesized copy is invisible to
   the user-facing clipboard).
7. **Permission denied path**: deny Automation permission for
   System Events (System Settings → Privacy & Security → Automation
   → tunaPop → System Events → off). Drag-select in Firefox: NO
   crash. ActionBar does not appear. Log shows
   `"AX + AppleScript both returned no text"`.
8. **No regression**: in AX-supported apps (Safari, TextEdit, Notes,
   Mail), selection capture still uses AX (no AppleScript dialog).
9. **No regression**: Phase 4–9 features (pin, fade, hover-out,
   loading guard, point-in-own-panels guard, system utility
   actions, response language, etc.) continue to work.
10. No `CGEvent.post(tap:)` anywhere in the codebase. Verify by
    `grep -r "CGEvent.post" Sources/`.

## macOS edge-case checklist (Appendix C)

- [ ] Permissions: ADDS Apple Events / System Events automation
      permission requirement. Requested lazily on first AX-hostile
      selection. NOT requested on launch.
- [ ] Permission revoked at runtime: AppleScript returns an error;
      `captureSelection()` returns nil; ActionBar does not appear;
      no crash.
- [ ] Key window: no new floating panels.
- [ ] Z-order: no change.
- [ ] Animation anchor: no change.
- [ ] Mouse / key event routing: no synthesized keystrokes via
      `CGEvent.post`. System Events handles the keystroke.
- [ ] Cancellation: AppleScript call is synchronous; the
      `Task.sleep` is cancellable but if cancelled, the `defer`
      still restores the clipboard.
- [ ] Resource cleanup: `defer` restores clipboard on all paths.
- [ ] UserDefaults schema: no change.

## Out of Scope

- Adding `NSAppleEventsUsageDescription` to `Info.plist` — the
  Swift Package build path does not produce a customized Info.plist
  in this PR. v1 distribution (Phase 14/15) introduces the proper
  `Info.plist` with the usage description. macOS will use a default
  description until then; the Automation dialog still works.
- A Settings UI row for Automation permission status (akin to the
  Accessibility row) — Phase 6b extension, not Phase 11.
- Selection extraction via AppleScript without the keystroke
  detour (some apps expose `selected text` via their scripting
  dictionary). Out of scope; AX-hostile apps generally don't
  expose this either.
- Removing diagnostic NSLogs added in Phase 6 / Phase 8 / Phase 9.
  Those remain until a dedicated logging cleanup PR (Phase 10).
