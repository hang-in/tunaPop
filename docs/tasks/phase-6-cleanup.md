# Phase 6 Cleanup — Permissions UX + double-click regression + warning layout

## Phase

Phase 6 cleanup. The implementation merged in Phase 6 passes the build
but user verification revealed four behavioral issues that need
investigation and minimal fix. This is NOT a feature PR.

## References

- `docs/MASTER_SPEC.md` Appendix B (macOS API caveats) + Appendix C
  (per-phase checklist)
- `docs/tasks/phase-6.md` (the just-merged spec)
- `docs/tasks/popclip-ux-phase-4.md` (Phase 4 acceptance — double-click
  must trigger an ActionBar)

## Verification items (run code-audit + minimal fix each)

For each item: identify file + lines, mark `OK` / `FIX` / `MANUAL`,
and apply the smallest possible patch when `FIX`. Report each item's
verdict in the final summary.

### Item A — "Grant Input Monitoring..." menu click does nothing

**Symptom**: clicking the menu bar item triggers no visible change.
The macOS system dialog does not appear.

**Hypothesis**: `IOHIDRequestAccess` only shows the dialog on the
FIRST call. If the user previously answered (allowed or denied), the
function returns the cached decision without re-prompting. There is
currently no fallback to System Settings for that case.

**Required fix**:

1. In `Sources/TunaPop/InputMonitoring.swift`, KEEP the existing
   `request()` function. It still serves the first-time case.

2. In `Sources/TunaPop/TunaPopApp.swift`, change `grantInputMonitoring`
   so that when `InputMonitoring.request()` returns `false` AND
   `InputMonitoring.isTrusted` is still false, it opens System
   Settings to the Input Monitoring panel:

   ```swift
   @objc private func grantInputMonitoring() {
       let granted = InputMonitoring.request()
       if !granted && !InputMonitoring.isTrusted {
           if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
               NSWorkspace.shared.open(url)
           }
       }
       updateStatusItemAppearance()
   }
   ```

3. Same fallback in `SettingsView.swift`'s Input Monitoring row's
   "권한 요청" button action. Replace the current
   `action: { InputMonitoring.request() }` with a helper that
   requests and falls back to System Settings:

   ```swift
   private func requestInputMonitoringOrOpenSettings() {
       let granted = InputMonitoring.request()
       if !granted && !InputMonitoring.isTrusted {
           openSystemSettings(.inputMonitoring)
       }
   }
   ```

   The button uses `action: requestInputMonitoringOrOpenSettings`.

The existing `openSystemSettings(.inputMonitoring)` helper already
exists with the correct URL — reuse it. Do not duplicate the URL
string.

### Item B — Non-localhost warning appears as red text instead of orange row

**Symptom**: user reports a red caption when entering a non-localhost
endpoint. The Phase 6 code uses `.orange` for the warning row but
`.red` for the `fetchError` caption. The likely cause is the
`fetchModels()` call fails on the non-local endpoint and the
`fetchError` (red) renders below the form, while the orange warning
row may also render but is being overlooked or visually conflated.

**Required fix**:

1. Audit `SettingsView.swift` — does the orange warning row actually
   render when `settings.endpoint = "http://example.com:11434"`? Trace
   `isLocalEndpoint(...)` for that input. Add a `let _ = isLocalEndpoint(settings.endpoint)`
   debug NSLog at function entry to log the decision once, then
   remove the log before reporting (do NOT ship the log).

2. If the row does render but is visually swallowed by the same-color
   exclamation icon, increase contrast by changing the Text
   `.foregroundStyle(.orange)` to `.foregroundStyle(.primary)` so the
   text uses the default text color and only the leading icon is
   orange. Keep the icon orange.

3. To prevent fetchError noise from competing with the warning when
   the endpoint is intentionally non-local, suppress the `fetchError`
   surface when `isLocalEndpoint(settings.endpoint) == false`. The
   warning row is then the only banner the user sees for that case:

   ```swift
   Section {
       if let error = fetchError, isLocalEndpoint(settings.endpoint) {
           Text(error)
               .font(.caption)
               .foregroundStyle(.red)
       }
   }
   ```

   The model fetch can still fail silently for remote endpoints in
   this PR. Surfacing remote-endpoint failures is Phase 8b territory.

### Item C — Double-click leaves the cursor or icon "stuck"

**Symptom**: user reports that after double-clicking, the ActionBar
does not appear and the cursor stays as the I-beam (text-insertion)
cursor, or some "input icon" lingers. The drag path still works.

**Hypothesis 1 (most likely)**: double-click in
`SelectionMonitor.handle(...)` calls `triggerSelection()` directly
inside the `.leftMouseDown` arm. But the global NSEvent monitor for
`.leftMouseDown` fires for EVERY left-click, including the second
mouse-down of a double-click. The first click sets `dragStart` and
`didDrag = false`. The second click ALSO sets `dragStart` (new
location) and `didDrag = false`. The `triggerSelection()` is called
on the second click because `clickCount == 2`. This is fine.

The actual failure must be in `SelectionExtractor.currentSelection()`
returning nil for double-click selections (AX may not have populated
the selection by the time the 120 ms delay fires).

**Hypothesis 2**: a stale `dragStart` from the first click of a
double-click sequence interacts with the second click's `triggerSelection`,
causing the bar to fire BEFORE the OS has committed the selection.

**Required investigation**:

1. Add temporary `NSLog` in `SelectionMonitor.swift`:
   ```swift
   case .leftMouseDown:
       NSLog("tunaPop SelectionMonitor: mouseDown clickCount=\(clickCount) loc=\(location)")
       dragStart = location
       didDrag = false
       if clickCount >= 2 {
           triggerSelection()
       }
   ```
   and in `triggerSelection`:
   ```swift
   NSLog("tunaPop SelectionMonitor: triggerSelection at \(point)")
   ```

2. Run the app, double-click a word in TextEdit, observe `/tmp/tunapop.log`
   (or wherever NSLog ends up — Console.app filtered by process).
   Report the log lines for one double-click event.

3. Based on log evidence, apply ONE of these fixes:
   - **If `triggerSelection` fires but `extractor -> nil`**: increase
     the post-down delay for double-click to 200 ms (give AX more
     time to commit the word selection). Implement this by adding a
     `delayMillis: Int` parameter to `triggerSelection(delayMillis:)`,
     defaulting to 120 for drag and passing 200 for double-click.
   - **If `triggerSelection` does not fire at all on double-click**:
     check whether `clickCount` reading from NSEvent inside the
     monitor closure is reliably 2. If not, fall back to tracking
     timing: record `lastMouseDownTime`; if a second mouseDown
     arrives within 0.4 s and at a similar location (within 6 px),
     treat as double-click.

4. After fix, remove the NSLog lines from production. KEEP the
   `"started (axTrusted=...)"` startup log and the
   `"AX returned no text; pasteboard fallback disabled"` log.

### Item D — Permission "isTrusted" returns true while user says "never set"

**Symptom**: Both Accessibility and Input Monitoring rows display
the green check immediately on launch even though the user states
they have not granted these in this session.

**Hypothesis**: macOS caches permission decisions per binary path.
`swift run TunaPop` uses the same `.build/arm64-apple-macosx/debug/TunaPop`
path every time. If the user granted AX or IM at any point in a
previous session, the decision is still in effect. The user may not
remember granting it.

**Required audit**:

1. Verify by reading from the OS — there is no code defect. Add a
   one-time NSLog at app startup that prints the result of both
   `Accessibility.isTrusted` and `InputMonitoring.isTrusted`. This
   is enough evidence for the user to cross-check System Settings →
   Privacy & Security → Accessibility / Input Monitoring → TunaPop
   list entries.

2. Place this NSLog inside
   `AppDelegate.applicationDidFinishLaunching(_:)` after the existing
   `Accessibility.requestIfNeeded()` call:
   ```swift
   NSLog("tunaPop permissions at launch: AX=\(Accessibility.isTrusted) InputMonitoring=\(InputMonitoring.isTrusted)")
   ```

3. Do NOT change the `isTrusted` logic. The functions call Apple
   APIs directly. If those APIs return `true`, the system genuinely
   considers the permission granted.

4. If the user later confirms System Settings shows TunaPop as NOT
   in the list, then there IS a defect — but this PR should not
   speculate; it should ship the diagnostic log so the user can
   verify and the next PR can act.

## Constraints

- macOS 14+, Swift 5.9+, SwiftUI + AppKit. No new third-party deps.
- `@MainActor` everywhere AppKit/SwiftUI mutates.
- `swift build` MUST stay green with zero new warnings.
- Total LOC delta ≤ 80 (excluding the diagnostic logs in Item C /
  Item D — those count but are minimal).
- Do NOT re-enable the pasteboard selection fallback.
- Do NOT introduce new NSPanel `canBecomeKey = true` paths — the
  panels remain non-key (system shortcuts pass through).

## Acceptance Criteria

1. `swift build` succeeds with zero new warnings.
2. Each verification item (A, B, C, D) reports its verdict in the
   final summary with file + lines.
3. **Item A**: clicking "Grant Input Monitoring..." with no prior
   answer → macOS dialog appears. With a prior answer → System
   Settings opens to the Input Monitoring panel. Same for the
   Settings row's "권한 요청" button.
4. **Item B**: with `endpoint = "http://example.com:11434"` the
   warning row is visibly orange (icon orange, text default), and
   `fetchError` is suppressed for non-local endpoints. Toggling back
   to `http://localhost:11434` hides the warning and restores
   `fetchError` visibility.
5. **Item C**: double-click in TextEdit or Safari shows the ActionBar
   for the selected word within ~250 ms of mouseUp. The cursor does
   not visually "stick" — it returns to default after the dismiss.
   Diagnostic NSLog removed from production paths before final
   commit.
6. **Item D**: a one-line launch log records both permission states.
   The launch log persists. No `isTrusted` logic change.
7. No regression in: drag selection → ActionBar, action click →
   ResponsePanel + metadata caption, ESC-not-handling (intentional),
   outside-click dismissal, hover-out timer, pin toggle, fade
   animation, iTerm2 cmd+c.

## macOS edge-case checklist (Appendix C)

- [ ] Permissions: this PR ADDS the System Settings fallback URL
      `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`.
      Verify it opens the correct panel on macOS 14, 15, 26.
- [ ] Permission revoked at runtime: the existing 5-second / 2-second
      timers keep status in sync. No change.
- [ ] Key window: no change (panels remain non-key).
- [ ] Z-order: no change.
- [ ] Animation anchor: no change.
- [ ] Mouse / key event routing: no change.
- [ ] Cancellation: no change.
- [ ] Resource cleanup: no new monitors / timers / observers.
- [ ] UserDefaults schema: no change.

## Out of Scope

- Showing a system notification when permission is granted.
- Polling System Settings to auto-close the privacy URL after user
  grants permission.
- Cosmetic redesign of the warning row.
- Refactoring `SelectionMonitor` to use NSAccessibility notifications
  for selection change events.
- Triple-click support.
- Phase 7 (custom action editor).
