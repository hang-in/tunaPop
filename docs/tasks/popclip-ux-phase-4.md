# PopClip UX Phase 4: Xpop-style polish (ESC, auto-hide, movable, pin, animation)

## Phase

Phase 4 of the PopClip-style UX refactor. Phases 1–3 produced a working
icon-only ActionBar + ResponsePanel pair anchored under the action bar with
outside-click dismissal. This phase ports five polish patterns from the
reference open-source project Xpop (`DongqiShen/Xpop`) so that our flow
matches PopClip-grade UX:

1. **ESC dismissal works** by turning the floating panels into key windows
   while keeping the app `.accessory` and the panel `.nonactivatingPanel`.
   This is done via an `NSPanel` subclass that overrides `canBecomeKey`.
2. **Auto-hide on hover-out** — once the mouse leaves both panels and stays
   out for 1.0 s, both panels dismiss. Loading state and pinned state
   override the timer.
3. **ResponsePanel is movable** — user can drag it to reposition.
4. **Pin option** — a pin button in the response header. While pinned, the
   panel ignores outside clicks and the hover-out timer.
5. **Fade-out animation** on dismiss (0.3 s ease in/out).

## Focus

Add a shared `KeyableNonActivatingPanel` (NSPanel subclass) so both panels
can become key, wire up the ESC dismissal through the existing local
keyDown monitor (which now functions because the panel is key), introduce
a mouseMoved-driven hide timer on `PopupController`, expose a pin toggle
on `ResponsePanel`, make `ResponsePanel` movable by background, and route
all dismissal through a fade-out animation helper.

Files to add:
- `Sources/TunaPop/KeyableNonActivatingPanel.swift`

Files to modify:
- `Sources/TunaPop/ActionBarPanel.swift`        (use the new panel base class)
- `Sources/TunaPop/ResponsePanel.swift`         (use the base class, add `isPinned`, `isMovableByWindowBackground = true`, dismiss animation)
- `Sources/TunaPop/ResponseView.swift`          (add pin/unpin button in header)
- `Sources/TunaPop/PopupController.swift`       (hideTimer, mouseMoved monitor, ESC behavior, pin-aware dismiss skipping, animation routing)

Files NOT to modify:
- `Sources/TunaPop/Action.swift`
- `Sources/TunaPop/ActionBarPosition.swift`
- `Sources/TunaPop/ActionBarView.swift`
- `Sources/TunaPop/AppSettings.swift`
- `Sources/TunaPop/SettingsView.swift`
- `Sources/TunaPop/Accessibility.swift`
- `Sources/TunaPop/SelectionExtractor.swift`
- `Sources/TunaPop/SelectionMonitor.swift`
- `Sources/TunaPop/SelectionPayload.swift`
- `Sources/TunaPop/OllamaClient.swift`
- `Sources/TunaPop/ResponseState.swift`
- `Sources/TunaPop/TooltipImageButton.swift`
- `Sources/TunaPop/TunaPopApp.swift`

## Constraints

- macOS, Swift 5.9+, SwiftUI + AppKit. No third-party deps.
- `@MainActor` on every type that touches AppKit/SwiftUI mutation.
- Match existing style (final classes, `@Published` settings via `UserDefaults`).
- Do not write comments unless explaining a non-obvious invariant.
- `swift build` must succeed with zero new warnings.
- All Korean UI strings already in place; do not invent new copy. For the
  pin button tooltip use `"고정"` / `"고정 해제"`.
- Match existing diagnostic style — minimal `NSLog`, prefix `tunaPop`.
- Keep the existing `URLError(.cancelled)` silent-catch path, the
  outside-click monitors, and the existing dismiss path through
  `PopupController.dismiss()`.

## Required types and changes

### `KeyableNonActivatingPanel` (new file)

```swift
import AppKit

final class KeyableNonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

Both `ActionBarPanel` and `ResponsePanel` must construct their `panel`
property as `KeyableNonActivatingPanel` instead of `NSPanel`. Every other
panel attribute stays exactly as today (`.nonactivatingPanel`, `.fullSizeContentView`,
floating level, transparent background, hidden traffic lights, etc.).

In each panel's `show(...)` path replace `orderFrontRegardless()` with
`makeKeyAndOrderFront(nil)`. The action bar's `bringToFront()` should
likewise call `makeKeyAndOrderFront(nil)` so it remains atop the response
panel after a new action is fired and so it stays key (so ESC still
works after a quick action switch).

Do NOT change the activation policy (`.accessory` stays). The macOS app
itself never activates; only the panel becomes key.

### `ResponsePanel` changes

- Construct `panel` as `KeyableNonActivatingPanel`.
- In `ensurePanel()`, set `panel.isMovableByWindowBackground = true`
  (replacing the existing `false`).
- Add `private var isPinned: Bool = false` and expose
  `var pinned: Bool { isPinned }` and `func setPinned(_ pinned: Bool)`.
  When `setPinned` is called, just store the value and force a
  `update(state: currentState)` re-render so the pin icon in the header
  reflects the change.
- Add `func dismissAnimated(completion: @escaping () -> Void)` that runs
  a 0.3 s fade-out via `NSAnimationContext` then calls
  `panel?.orderOut(nil)` and `completion()`. After fade,
  reset `panel?.alphaValue = 1.0` so the next show is fully opaque.
  Keep the original synchronous `dismiss()` for callers that want
  immediate teardown (e.g. cancel paths). When `dismiss()` runs, also
  reset `isPinned = false`.
- Wire the pin state into `ResponseView` via a `togglePinHandler`
  callback in addition to the existing copy handler. Add
  `func setPinHandler(_ handler: @escaping () -> Void)`. The
  `PopupController` will call `setPinHandler { [weak self] in self?.toggleResponsePinned() }`.
- The hosting view rebuild path in `update(state:)` must pass both the
  current `state` and the current `isPinned` flag into `ResponseView`.

### `ResponseView` changes

Add `let isPinned: Bool` and `let onTogglePin: () -> Void` to the struct.
In the header HStack, add a pin button just to the left of the copy
button:

```swift
Button {
    onTogglePin()
} label: {
    Image(systemName: isPinned ? "pin.fill" : "pin")
        .foregroundStyle(isPinned ? .accentColor : .secondary)
}
.buttonStyle(.plain)
.help(isPinned ? "고정 해제" : "고정")
```

### `ActionBarPanel` changes

- Construct `panel` as `KeyableNonActivatingPanel`.
- Replace `orderFrontRegardless()` with `makeKeyAndOrderFront(nil)` in
  both `show(...)` and `bringToFront()`.
- No movability change — the action bar is small and should not be
  draggable. Keep `isMovableByWindowBackground = false`.

### `PopupController` changes

Add the hover-out timer, ESC behavior, and pin-aware dismiss skipping.

New stored properties:
```swift
private var hideTimer: Timer?
private var mouseMovedMonitor: Any?
private let hoverGraceInterval: TimeInterval = 1.0
```

Behavior:

- **Start / stop the mouseMoved monitor alongside the existing event
  monitors.** Add to `startEventMonitors()`:
  ```swift
  mouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
      Task { @MainActor in self?.handleMouseMoved() }
  }
  ```
  Also add a local monitor for `.mouseMoved` so movement inside our own
  panels cancels the timer:
  ```swift
  NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
      self?.handleMouseMoved()
      return event
  }
  ```
  Store the local monitor in a new property `localMouseMovedMonitor: Any?`
  and remove it in `stopEventMonitors()` alongside the others.

- **`handleMouseMoved()`**:
  ```swift
  private func handleMouseMoved() {
      let point = NSEvent.mouseLocation
      let overActionBar = actionBarPanel.contains(point: point)
      let overResponse = responsePanel.contains(point: point)
      if overActionBar || overResponse {
          cancelHideTimer()
          return
      }
      if responsePanel.pinned { return }
      if case .loading = responsePanel.currentState { return }
      scheduleHideTimer()
  }

  private func scheduleHideTimer() {
      if hideTimer != nil { return }
      hideTimer = Timer.scheduledTimer(withTimeInterval: hoverGraceInterval, repeats: false) { [weak self] _ in
          Task { @MainActor in self?.dismiss() }
      }
  }

  private func cancelHideTimer() {
      hideTimer?.invalidate()
      hideTimer = nil
  }
  ```

- **`dismissIfOutside(_:)`** — extend the existing guard so a pinned
  response panel also blocks outside-click dismissal:
  ```swift
  private func dismissIfOutside(_ point: CGPoint) {
      if actionBarPanel.contains(point: point) || responsePanel.contains(point: point) { return }
      if responsePanel.pinned { return }
      if case .loading = responsePanel.currentState { return }
      dismiss()
  }
  ```

- **ESC dismissal**: keep the existing keyDown monitor. Now that the
  panels become key via `makeKeyAndOrderFront(nil)`, the local keyDown
  monitor will fire on ESC and the existing `dismiss()` path runs. No
  extra code needed beyond ensuring `keyEventMonitor` is started.

- **`dismiss()` uses fade animation**. Update `dismiss()` to call
  `responsePanel.dismissAnimated { }` and `actionBarPanel.dismiss()`
  (the action bar dismisses immediately — it's small enough that fade
  is not necessary). Cancel the hide timer, cancel the current task,
  reset state, stop event monitors. Order:
  1. Cancel `currentTask`.
  2. Cancel `hideTimer`.
  3. Stop event monitors.
  4. `actionBarPanel.dismiss()` (immediate).
  5. `responsePanel.dismissAnimated { }` (fade then orderOut).
  6. Clear `lastPayload`, `lastResponse`.

- **`toggleResponsePinned()`**:
  ```swift
  private func toggleResponsePinned() {
      responsePanel.setPinned(!responsePanel.pinned)
      if !responsePanel.pinned {
          handleMouseMoved()
      } else {
          cancelHideTimer()
      }
  }
  ```

- During `init`, after `responsePanel.setCopyHandler(...)`, also call:
  ```swift
  responsePanel.setPinHandler { [weak self] in
      self?.toggleResponsePinned()
  }
  ```

Whenever a new action is fired (`handleAction(_:)`), make sure to also
`cancelHideTimer()` at the top so a pending hide does not fire while a
new request is in flight.

## Acceptance Criteria

1. `swift build` succeeds with zero new warnings.
2. `KeyableNonActivatingPanel.swift` exists; both `ActionBarPanel` and
   `ResponsePanel` construct their internal panel as
   `KeyableNonActivatingPanel`.
3. Drag-selecting text shows the ActionBar exactly as before; clicking
   an icon still shows the ResponsePanel directly under the ActionBar
   (or above when there is no room below).
4. **ESC** while either panel is visible dismisses both panels with a
   fade animation (no app-activation flicker).
5. **Hover-out**: when the mouse stays outside both panels for 1.0 s,
   both panels dismiss with the fade animation.
   - Exception: during `.loading` state, hover-out does NOT dismiss.
   - Exception: when pinned, hover-out does NOT dismiss.
6. **Outside click**: dismisses both panels, EXCEPT when pinned or
   when loading (existing behavior preserved). Fade animation runs.
7. **Pin toggle**: the response header has a pin icon (`pin` / `pin.fill`).
   Clicking toggles `isPinned`. While pinned:
   - outside-click does not dismiss
   - hover-out timer does not fire
   - ESC still dismisses (acts as an explicit cancel)
8. **ResponsePanel is draggable**: user can grab the response panel's
   background and move it. ActionBar remains non-movable.
9. **Animation**: dismissal of the ResponsePanel uses a 0.3 s ease-in/out
   fade. ActionBar dismisses immediately.
10. After a dismissal cycle, a subsequent show is fully opaque (no
    leftover `alphaValue = 0` state).
11. Cancelled tasks remain silent — no "canceled" message ever surfaces
    in the response (existing `URLError(.cancelled)` catch must stay).
12. After clicking a new action while a response is in flight, the
    previous response is replaced with `.loading` and the new response
    arrives without a flash of stale text. No "canceled" appears.

## Out of Scope

- Settings UI for hover-out interval or pin default.
- Persisting pin state across sessions.
- Streaming responses.
- 8-direction position UI (still data model only).
- Per-action customization in Settings.
- Replacing the existing event monitor types (still `.leftMouseDown` /
  `.rightMouseDown` / `.keyDown` + the new `.mouseMoved`).
- Touching `SelectionExtractor`, `SelectionMonitor`, `OllamaClient`, or
  the status menu.
