# PopClip UX Phase 1+2: ActionBar + Models

## Phase

Phase 1+2 of a multi-phase PopClip-style UX refactor. This task introduces a
small icon-only action bar that appears near a text selection. The response
panel and outside-click dismissal will be done in a later phase.

## Focus

Add a compact action bar (icons only, hover tooltip labels) that appears near
the user's mouse-up location after a drag-selection. Wire it up so clicking a
button currently routes to the existing `FloatingPanelController` popup, which
shows the AI response. The existing single-panel `PopupView` flow stays as the
temporary "response surface" until Phase 3 replaces it with a dedicated
`ResponsePanel`.

Files to add:
- `Sources/TunaPop/Action.swift`
- `Sources/TunaPop/ActionBarPosition.swift`
- `Sources/TunaPop/ActionBarPanel.swift`
- `Sources/TunaPop/ActionBarView.swift`

Files to modify:
- `Sources/TunaPop/AppSettings.swift`
- `Sources/TunaPop/TunaPopApp.swift`

Files NOT to modify in this phase:
- `Sources/TunaPop/FloatingPanelController.swift`
- `Sources/TunaPop/PopupView.swift`
- `Sources/TunaPop/OllamaClient.swift`
- `Sources/TunaPop/SelectionMonitor.swift`
- `Sources/TunaPop/SelectionExtractor.swift`
- `Sources/TunaPop/SelectionPayload.swift`

## Constraints

- Target: macOS, Swift 5.9+, SwiftUI + AppKit (existing project conventions).
- All AppKit/SwiftUI state must remain `@MainActor`.
- No third-party dependencies. Use only AppKit, SwiftUI, Foundation.
- Match existing style (final classes, `@MainActor` annotations,
  `@Published` settings persisted via `UserDefaults`).
- `swift build` must succeed with zero warnings introduced by new files.
- Do not log to stdout/stderr in production paths (NSLog OK for diagnostics
  but keep minimal).
- Korean strings (button tooltips) should be used as specified below; do not
  invent additional UI copy.
- The action bar uses **icons only**. Labels appear as native SwiftUI
  tooltips (use `.help(...)`) so they show after a hover delay.
- Comments: write none unless explaining a non-obvious invariant. Do not
  write multi-line docstring blocks.

## Required types

### `Action` (new file `Action.swift`)

```swift
struct Action: Identifiable, Equatable {
    let id: String
    let label: String      // shown only as tooltip
    let prompt: String
    let systemImage: String  // SF Symbol name
}

extension Action {
    static let defaults: [Action] = [
        Action(id: "explain",   label: "설명", prompt: "Explain this selection clearly and concisely.",            systemImage: "text.alignleft"),
        Action(id: "summarize", label: "요약", prompt: "Summarize this selection in three bullets.",                systemImage: "list.bullet"),
        Action(id: "translate", label: "번역", prompt: "Translate this selection into Korean. Keep meaning and tone.", systemImage: "globe"),
    ]
}
```

### `ActionBarPosition` (new file `ActionBarPosition.swift`)

```swift
enum ActionBarPosition: String, CaseIterable, Codable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight
}
```

Add a function that, given the selection anchor point (in screen coordinates,
macOS convention where y grows upward) and the action bar `size`, returns the
panel origin `CGPoint`:

```swift
func origin(forAnchor anchor: CGPoint, barSize: CGSize, offset: CGFloat = 12) -> CGPoint
```

Behavior (macOS screen coordinates, y-up):

- `.topRight`:     `(anchor.x + offset, anchor.y + offset)`
- `.top`:          `(anchor.x - barSize.width/2, anchor.y + offset)`
- `.topLeft`:      `(anchor.x - barSize.width - offset, anchor.y + offset)`
- `.right`:        `(anchor.x + offset, anchor.y - barSize.height/2)`
- `.left`:         `(anchor.x - barSize.width - offset, anchor.y - barSize.height/2)`
- `.bottomRight`:  `(anchor.x + offset, anchor.y - barSize.height - offset)`
- `.bottom`:       `(anchor.x - barSize.width/2, anchor.y - barSize.height - offset)`
- `.bottomLeft`:   `(anchor.x - barSize.width - offset, anchor.y - barSize.height - offset)`

After computing the origin, clamp to `NSScreen.main?.visibleFrame` minus a
12pt margin on each side so the bar never falls offscreen. If `NSScreen.main`
is nil, return the unclamped origin.

### `AppSettings` change

Add a new published property after `defaultPrompt`:

```swift
@Published var actionBarPosition: ActionBarPosition {
    didSet { UserDefaults.standard.set(actionBarPosition.rawValue, forKey: Self.actionBarPositionKey) }
}

private static let actionBarPositionKey = "actionBarPosition"
```

In `init()`:
```swift
let positionRaw = UserDefaults.standard.string(forKey: Self.actionBarPositionKey)
actionBarPosition = positionRaw.flatMap(ActionBarPosition.init(rawValue:)) ?? .topRight
```

Preserve the existing init order (other fields stay where they are). Do not
expose this field in SettingsView for v1.

### `ActionBarView` (new file `ActionBarView.swift`)

SwiftUI view, **icons only**, tooltips via `.help(action.label)`:

```swift
import SwiftUI

struct ActionBarView: View {
    let actions: [Action]
    let onAction: (Action) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(actions) { action in
                Button {
                    onAction(action)
                } label: {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(action.label)
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

The exact bar pixel size will depend on the count of `actions`. With 3 default
actions, the intrinsic content size should be approximately 100×36 pt. The
host panel below sizes itself to fit the SwiftUI content.

### `ActionBarPanel` (new file `ActionBarPanel.swift`)

```swift
@MainActor
final class ActionBarPanel {
    private var panel: NSPanel?
    private let onAction: (Action) -> Void
    private(set) var isVisible: Bool = false

    init(onAction: @escaping (Action) -> Void)

    func show(actions: [Action], at anchor: CGPoint, position: ActionBarPosition)
    func dismiss()
    func contains(point: CGPoint) -> Bool
}
```

Implementation requirements:

- Lazily create `panel: NSPanel` on first `show`.
- Panel style: `styleMask = [.nonactivatingPanel, .fullSizeContentView]`,
  `backing: .buffered`, `defer: false`.
- `panel.isFloatingPanel = true`
- `panel.level = .floating`
- `panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`
- `panel.hidesOnDeactivate = false`
- `panel.titleVisibility = .hidden`
- `panel.titlebarAppearsTransparent = true`
- `panel.backgroundColor = .clear`
- `panel.isOpaque = false`
- `panel.hasShadow = true`
- `panel.isMovableByWindowBackground = false`  // action bar should not be draggable
- Hide standard window buttons (`closeButton`, `miniaturizeButton`, `zoomButton`).
- Content view: `NSHostingView(rootView: ActionBarView(actions:, onAction:))`.

`show(actions:at:position:)`:
- (Re)build content view each call (cheap; supports settings changes).
- Compute panel size from `hostingView.fittingSize` (or set a sensible default if zero).
- Compute origin via `ActionBarPosition.origin(forAnchor:barSize:)`.
- `panel.setFrame(NSRect(origin: origin, size: size), display: true)`.
- `panel.orderFrontRegardless()`.
- Set `isVisible = true`.

`dismiss()`:
- `panel?.orderOut(nil)`; set `isVisible = false`.
- Do NOT release the panel; reuse on next `show`.

`contains(point:)`:
- Return `panel?.frame.contains(point) ?? false`.

### `TunaPopApp` (`AppDelegate`) changes

- Add a stored property `private var actionBarPanel: ActionBarPanel?`.
- In `applicationDidFinishLaunching`, construct the `ActionBarPanel`:
  ```swift
  let actionBarPanel = ActionBarPanel { [weak self] action in
      Task { @MainActor in
          self?.handleAction(action)
      }
  }
  self.actionBarPanel = actionBarPanel
  ```
- Modify the `SelectionMonitor` callback so it shows the action bar instead of
  the FloatingPanelController directly:
  ```swift
  monitor = SelectionMonitor { [weak self] payload, point in
      Task { @MainActor in
          self?.lastSelectionPayload = payload
          self?.actionBarPanel?.show(
              actions: Action.defaults,
              at: point,
              position: self?.settings.actionBarPosition ?? .topRight
          )
      }
  }
  ```
- Add a new property `private var lastSelectionPayload: SelectionPayload?` to
  remember the most recent selection so action buttons know what text to send.
- Add the action handler. For this phase, route to the existing
  `FloatingPanelController` to keep response display working:
  ```swift
  private func handleAction(_ action: Action) {
      guard let payload = lastSelectionPayload else { return }
      actionBarPanel?.dismiss()
      panelController?.show(
          payload: payload,
          at: NSEvent.mouseLocation,
          autoRun: false,
          initialResponse: ""
      )
      // Phase 3 will replace this with ResponsePanel + direct OllamaClient call.
      // For now we surface the existing popup so the user sees something.
  }
  ```

`FloatingPanelController.show(payload:at:autoRun:initialResponse:)` already
exists with that signature — do not change it.

Do not remove or rename `FloatingPanelController`, `PopupView`,
`showLaunchPopup`, the "Show Test Popup" menu, or any other existing
functionality. They remain reachable from the status menu.

## Acceptance Criteria

1. `swift build` succeeds with zero new warnings.
2. The new files exist at the paths listed above, with the public surface
   described.
3. Running `swift run TunaPop` and:
   - Enabling Selection Monitor from the status menu.
   - Drag-selecting text in another app.
   Causes a small icon-only bar (3 SF Symbol icons inside a rounded
   `.ultraThinMaterial` capsule) to appear near the mouse-up location, biased
   toward the upper-right (default `actionBarPosition = .topRight`).
4. Hovering over an icon for ~1 second surfaces a native macOS tooltip
   showing the Korean label (설명 / 요약 / 번역).
5. Clicking an action icon dismisses the action bar and shows the existing
   `FloatingPanelController` popup (existing behavior — no new response panel
   yet). The action's choice does not have to drive a different prompt in this
   phase; routing to the existing popup is enough.
6. `Action.defaults` is the single source of truth for the v1 action list.
7. `AppSettings.actionBarPosition` reads/writes `UserDefaults` and defaults
   to `.topRight` on first launch.
8. The action bar does NOT activate the app (`.nonactivatingPanel`).
9. The action bar's standard window buttons (close/minimize/zoom) are not
   visible.

## Out of Scope (do NOT implement)

- ResponsePanel (Phase 3).
- Outside-click dismissal of the action bar (Phase 5).
- Settings UI for `actionBarPosition` (Phase 6+).
- Streaming responses, per-action prompt routing, copy button on response —
  none of these in this phase.
- Removing or restructuring the existing single-panel `FloatingPanelController`
  / `PopupView` flow.
