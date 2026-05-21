# PopClip UX Phase 3: ResponsePanel + Outside-click dismissal + Tooltip fix

## Phase

Phase 3 of the PopClip-style UX refactor. Phases 1 and 2 added the
icon-only ActionBar. This phase:

1. Replaces the legacy single-panel `FloatingPanelController` + `PopupView`
   with a small `ResponsePanel` anchored just below the `ActionBarPanel`.
2. Routes action button clicks directly to `OllamaClient` and displays the
   result in `ResponsePanel`.
3. Dismisses both panels on outside click (any click outside either panel)
   and on ESC.
4. Fixes the missing tooltip by switching the ActionBar buttons to a
   construction that supports `NSView.toolTip` reliably inside a
   `.nonactivatingPanel`.

## Focus

Add a small response surface that lives directly below the action bar and
shows the LLM result for the chosen action. Wire all click routing through
a new `PopupController` that owns both panels. Delete the old single-popup
flow once the new flow is in place.

Files to add:
- `Sources/TunaPop/ResponseState.swift`
- `Sources/TunaPop/ResponseView.swift`
- `Sources/TunaPop/ResponsePanel.swift`
- `Sources/TunaPop/PopupController.swift`
- `Sources/TunaPop/TooltipImageButton.swift`  (NSViewRepresentable wrapper)

Files to modify:
- `Sources/TunaPop/ActionBarView.swift`        (use TooltipImageButton)
- `Sources/TunaPop/ActionBarPanel.swift`       (expose `frame`)
- `Sources/TunaPop/TunaPopApp.swift`           (use PopupController, drop launch popup)

Files to delete:
- `Sources/TunaPop/FloatingPanelController.swift`
- `Sources/TunaPop/PopupView.swift`

Files NOT to modify in this phase:
- `Sources/TunaPop/OllamaClient.swift`        (read its signature; do not change)
- `Sources/TunaPop/SelectionMonitor.swift`
- `Sources/TunaPop/SelectionExtractor.swift`
- `Sources/TunaPop/SelectionPayload.swift`
- `Sources/TunaPop/AppSettings.swift`
- `Sources/TunaPop/SettingsView.swift`
- `Sources/TunaPop/Accessibility.swift`
- `Sources/TunaPop/Action.swift`
- `Sources/TunaPop/ActionBarPosition.swift`

## Constraints

- macOS, Swift 5.9+, SwiftUI + AppKit. No third-party deps.
- `@MainActor` on every type that touches AppKit/SwiftUI mutation.
- Match existing style (final classes, `@Published` settings via `UserDefaults`).
- Do not write comments unless explaining a non-obvious invariant.
- `swift build` must succeed with zero new warnings.
- Korean strings for tooltips already come from `Action.label`; do not invent UI copy.
- Keep `NSLog` use to the existing diagnostic style — minimal, prefixed with `tunaPop`.

## Required types

### `ResponseState` (new file)

```swift
enum ResponseState: Equatable {
    case idle
    case loading
    case success(String)
    case failure(String)
}
```

### `ResponseView` (new file)

SwiftUI view rendering a small response surface.

Layout:
- Root: `VStack(alignment: .leading, spacing: 8)`
- Header row: small title text ("tunaPop") on the left, spacer, copy button on the right.
  Copy button is icon-only (SF Symbol `doc.on.doc`), `.plain` style, becomes
  `checkmark.circle.fill` for 1.5 s after a successful copy, then resets.
- Body:
  - `.idle`: no body.
  - `.loading`: small `ProgressView()` plus `"…"` placeholder text.
  - `.success(let text)`: `ScrollView { Text(text).textSelection(.enabled) }`,
    body framed to `minHeight: 60, maxHeight: 280`.
  - `.failure(let message)`: `Text(message).foregroundStyle(.red)`.
- Container width fixed at **360**.
- Outer styling: `.padding(12)`, `.background(.ultraThinMaterial)`,
  `.clipShape(RoundedRectangle(cornerRadius: 12))`, subtle 0.5pt border
  `Color.primary.opacity(0.08)`.
- ESC key handling lives on the panel, not this view.

Required API:

```swift
struct ResponseView: View {
    let state: ResponseState
    let onCopy: () -> Void
}
```

The copy button calls `onCopy()`. The "copied" confirmation is owned by the
view via `@State` and resets after 1.5 s. The `onCopy` callback is what
actually mutates the pasteboard.

### `ResponsePanel` (new file)

```swift
@MainActor
final class ResponsePanel {
    private(set) var isVisible: Bool = false

    init()

    func show(at origin: CGPoint)
    func update(state: ResponseState)
    func dismiss()

    func contains(point: CGPoint) -> Bool
    var frame: CGRect { /* current panel frame or .zero */ }
}
```

Panel construction matches `ActionBarPanel`:
- `styleMask: [.nonactivatingPanel, .fullSizeContentView]`
- `backing: .buffered`, `defer: false`
- `isFloatingPanel = true`
- `level = .floating`
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`
- `hidesOnDeactivate = false`
- `titleVisibility = .hidden`, `titlebarAppearsTransparent = true`
- `backgroundColor = .clear`, `isOpaque = false`
- `hasShadow = true`, `isMovableByWindowBackground = false`
- Hide `closeButton` / `miniaturizeButton` / `zoomButton`.

`show(at origin:)`:
- Lazily build the panel.
- Build/refresh the hosting view with the current state (default `.loading`
  when first shown so the user sees feedback immediately).
- Use `hostingView.fittingSize` to determine the panel size. Width must
  match the 360 pt content; height is dictated by content (clamped by
  `ResponseView`'s internal maxHeight).
- `panel.setFrame(NSRect(origin: origin, size: size), display: true)`.
- `panel.orderFrontRegardless()`. Set `isVisible = true`.

`update(state:)`:
- Rebuild the root SwiftUI view with the new state.
- Recompute panel height from `hostingView.fittingSize` and adjust the
  panel's frame **keeping its origin's top edge stable** (since the panel
  appears below the action bar, growth must extend downward in macOS y-up
  coordinates — i.e. the panel's `maxY` stays fixed and `minY` decreases as
  the panel grows taller). Implementation: keep the previously-shown
  `topY = oldFrame.maxY`, recompute `newOrigin = CGPoint(x: oldFrame.minX, y: topY - newSize.height)`.

`dismiss()`:
- `panel?.orderOut(nil)`; set `isVisible = false`.
- Do not release the panel.

`contains(point:)` and `frame`:
- Return `panel?.frame.contains(point) ?? false` / `panel?.frame ?? .zero`.

### `ActionBarPanel` change

Expose the current frame (already wrapped internally):

```swift
var frame: CGRect { panel?.frame ?? .zero }
```

No other behavior changes.

### `TooltipImageButton` (new file)

`NSViewRepresentable` wrapping an `NSButton` that supports a real
`toolTip` (SwiftUI `.help` does not display reliably in a
`.nonactivatingPanel`).

```swift
import AppKit
import SwiftUI

struct TooltipImageButton: NSViewRepresentable {
    let systemImage: String
    let toolTip: String
    let action: () -> Void

    func makeNSView(context: Context) -> NSButton
    func updateNSView(_ nsView: NSButton, context: Context)

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func invoke() { action() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
}
```

Implementation requirements:
- `NSButton` with image set to
  `NSImage(systemSymbolName: systemImage, accessibilityDescription: toolTip)?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))`.
- `isBordered = false`, `bezelStyle = .regularSquare` (or `.shadowlessSquare`),
  `imagePosition = .imageOnly`.
- `frame = NSRect(x: 0, y: 0, width: 30, height: 30)` (fixed intrinsic size).
- `target = context.coordinator`, `action = #selector(Coordinator.invoke)`.
- `toolTip = toolTip` (this is the key fix — set on the NSButton itself).
- In `updateNSView`, refresh the tooltip and the coordinator's `action`
  closure.

### `ActionBarView` change

Replace the SwiftUI `Button` + `.help` with `TooltipImageButton`:

```swift
struct ActionBarView: View {
    let actions: [Action]
    let onAction: (Action) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(actions) { action in
                TooltipImageButton(
                    systemImage: action.systemImage,
                    toolTip: action.label
                ) {
                    onAction(action)
                }
                .frame(width: 30, height: 30)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}
```

### `PopupController` (new file — replaces `FloatingPanelController`)

```swift
@MainActor
final class PopupController {
    private let settings: AppSettings
    private let actionBarPanel: ActionBarPanel
    private let responsePanel: ResponsePanel
    private var lastPayload: SelectionPayload?
    private var lastAnchor: CGPoint = .zero
    private var currentTask: Task<Void, Never>?
    private var lastResponse: String = ""
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var keyEventMonitor: Any?

    init(settings: AppSettings) {
        self.settings = settings
        self.responsePanel = ResponsePanel()
        // We must wire `actionBarPanel.onAction` to `self.handleAction(_:)`,
        // but `self` is not yet available before `super.init` completes.
        // Use a captured weak closure that forwards once the controller exists:
        var actionHandler: ((Action) -> Void)?
        let bar = ActionBarPanel { action in actionHandler?(action) }
        self.actionBarPanel = bar
        actionHandler = { [weak self] action in
            Task { @MainActor in self?.handleAction(action) }
        }
    }

    func show(payload: SelectionPayload, at anchor: CGPoint) { /* ... */ }
    func dismiss() { /* ... */ }
}
```

Required behavior:

`show(payload:at:)`:
- Cancel `currentTask`.
- Save `lastPayload = payload`, `lastAnchor = anchor`, `lastResponse = ""`.
- Dismiss any visible `responsePanel`.
- `actionBarPanel.show(actions: Action.defaults, at: anchor, position: settings.actionBarPosition)`.
- Start event monitors (`startEventMonitors()`).

`dismiss()`:
- Cancel `currentTask`.
- `actionBarPanel.dismiss()`, `responsePanel.dismiss()`.
- `stopEventMonitors()`.
- Clear `lastPayload = nil`, `lastResponse = ""`.

`handleAction(_:)`:
- Guard `lastPayload`.
- Compute the response panel origin: directly below the action bar,
  left-aligned to the bar's `minX`. Vertical offset = 6 pt gap.
  Specifically (macOS y-up screen coordinates):
  ```swift
  let actionBarFrame = actionBarPanel.frame
  let gap: CGFloat = 6
  let initialResponseHeight: CGFloat = 80  // approximate; panel will re-layout
  let origin = CGPoint(
      x: actionBarFrame.minX,
      y: actionBarFrame.minY - initialResponseHeight - gap
  )
  ```
  After `responsePanel.show(at: origin)`, the panel's own `update(state:)`
  will adjust the height while preserving the same top edge (see
  ResponsePanel spec). So future state changes will not visually shift the
  panel's top relative to the action bar.
- `responsePanel.show(at: origin)` then `responsePanel.update(state: .loading)`.
- Start the LLM call:
  ```swift
  currentTask?.cancel()
  let prompt = action.prompt
  let payloadCopy = payload
  let endpoint = settings.endpoint
  let token = settings.apiToken
  let model = settings.model
  currentTask = Task { @MainActor in
      do {
          let client = OllamaClient(endpoint: endpoint, token: token)
          let text = try await client.chat(model: model, prompt: prompt, payload: payloadCopy)
          try Task.checkCancellation()
          self.lastResponse = text
          self.responsePanel.update(state: .success(text))
      } catch is CancellationError {
          // user dismissed or fired another action
      } catch {
          self.responsePanel.update(state: .failure(error.localizedDescription))
      }
  }
  ```
  Verify `OllamaClient.chat(model:prompt:payload:)` exists with that
  signature by reading `OllamaClient.swift`. If the actual signature differs,
  match it exactly — do not invent new methods on `OllamaClient`.

`onCopy()` (passed into `ResponseView`):
- Copy `self.lastResponse` to `NSPasteboard.general` as a string. No-op if empty.

Event monitors:

`startEventMonitors()`:
- Global (clicks in other apps):
  ```swift
  globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
      Task { @MainActor in self?.dismissIfOutside(NSEvent.mouseLocation) }
  }
  ```
- Local (clicks in our app):
  ```swift
  localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      guard let self else { return event }
      self.dismissIfOutside(NSEvent.mouseLocation)
      return event
  }
  ```
- Key events (ESC):
  ```swift
  keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 { // ESC
          Task { @MainActor in self?.dismiss() }
          return nil
      }
      return event
  }
  ```

`stopEventMonitors()`:
- For each non-nil monitor, `NSEvent.removeMonitor(monitor)`, then set to nil.

`dismissIfOutside(_ point:)`:
- If `actionBarPanel.contains(point: point)` or `responsePanel.contains(point: point)`,
  do nothing.
- Otherwise call `dismiss()`.

### `TunaPopApp` (`AppDelegate`) change

Replace the `panelController: FloatingPanelController?` and the separate
`actionBarPanel: ActionBarPanel?` properties with a single
`popupController: PopupController?`.

- In `applicationDidFinishLaunching`:
  ```swift
  let popupController = PopupController(settings: settings)
  self.popupController = popupController

  monitor = SelectionMonitor { [weak self] payload, point in
      Task { @MainActor in
          self?.popupController?.show(payload: payload, at: point)
      }
  }
  ```

- Remove `lastSelectionPayload`, `actionBarPanel`, `panelController`,
  `handleAction(_:)`, and the `showLaunchPopup()` body. The "Show Test
  Popup" menu item should be repurposed to invoke the action bar at the
  current mouse location with a dummy text selection:
  ```swift
  @objc private func showTestPopup() {
      popupController?.show(
          payload: .text("tunaPop test selection"),
          at: NSEvent.mouseLocation
      )
  }
  ```
  Keep the menu title `"Show Test Popup"` and the `t` key equivalent.

- Remove the unconditional launch popup. On launch, the app should not show
  any panel; the menu bar icon is sufficient indication.

- The Accessibility request still happens via `Accessibility.requestIfNeeded()`
  at launch — keep that line.

Final `applicationDidFinishLaunching` should look approximately like:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    let popupController = PopupController(settings: settings)
    self.popupController = popupController

    monitor = SelectionMonitor { [weak self] payload, point in
        Task { @MainActor in
            self?.popupController?.show(payload: payload, at: point)
        }
    }

    configureStatusItem()
    Accessibility.requestIfNeeded()
}
```

The status menu, settings window opening, accessibility check, selection
monitor toggle, and Quit items all stay unchanged.

## Deletions

After the new flow compiles and `swift build` passes:

- Delete `Sources/TunaPop/FloatingPanelController.swift`.
- Delete `Sources/TunaPop/PopupView.swift`.
- Remove all references to `FloatingPanelController` and `PopupView` from
  the rest of the source tree.

## Acceptance Criteria

1. `swift build` succeeds with zero new warnings.
2. New files exist:
   `ResponseState.swift`, `ResponseView.swift`, `ResponsePanel.swift`,
   `PopupController.swift`, `TooltipImageButton.swift`.
3. Deleted files no longer exist:
   `FloatingPanelController.swift`, `PopupView.swift`.
4. `TunaPopApp.swift` references neither the deleted types nor a
   `lastSelectionPayload` property; instead it owns one `popupController`.
5. Running `swift run TunaPop`, enabling the selection monitor, and
   drag-selecting text in an AX-supported app shows the icon-only
   ActionBar near the selection.
6. Hovering an ActionBar icon for ~1 s reveals a macOS-native tooltip
   showing the Korean label (설명 / 요약 / 번역).
7. Clicking an ActionBar icon:
   - The ActionBar **stays visible**.
   - A new ResponsePanel appears just below the ActionBar showing a
     loading state.
   - The LLM call completes and the ResponsePanel updates to show the
     response text. The panel grows downward (its top edge stays anchored
     under the ActionBar) instead of shifting position.
8. Clicking another ActionBar icon while a response is in flight cancels
   the previous request and starts a new one. The new response replaces
   the previous one in the same panel.
9. Clicking the response panel's copy icon copies the response text to
   `NSPasteboard.general`. The icon briefly shows a check, then resets.
10. Clicking **anywhere outside** both panels — including in another app —
    dismisses both panels.
11. Pressing **ESC** dismisses both panels.
12. The legacy launch popup no longer appears on launch.
13. `"Show Test Popup"` menu item still works; it now spawns the
    ActionBar at the current mouse location with a dummy text selection.

## Out of Scope (do NOT implement)

- Streaming chat (`stream: true`) — non-streaming is fine for v1.
- Per-action customization UI in Settings.
- Settings UI for `actionBarPosition` (still data model only).
- 8-direction picker UI.
- Image selection routing (image payloads still go through `OllamaClient.chat`
  unchanged; no special UI).
- Theming or color tokens.
