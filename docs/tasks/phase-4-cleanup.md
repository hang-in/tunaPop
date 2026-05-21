# Phase 4 Cleanup — Self-audit + gap fix

## Phase

Phase 4 (`docs/tasks/popclip-ux-phase-4.md`) was implemented and the
build is green, but the acceptance criteria were not all manually
verified before merge. There were also two follow-up items shipped
inline (Phase 4.1): double-click trigger and `IOHIDCheckAccess`
pasteboard fallback guard.

This cleanup PR audits the current implementation against the original
acceptance list, then closes any gaps with the smallest possible
change. **No new features.** Goal is "Phase 4 done" with high
confidence.

## References

- `docs/MASTER_SPEC.md` Appendix B (macOS API caveats) + Appendix C
  (per-phase checklist)
- `docs/tasks/popclip-ux-phase-4.md` (original spec — authoritative
  for the 12 numbered acceptance criteria)

## Focus

For each of the 14 verification items below, the agent MUST:

1. Identify the exact file + function + lines that implement the item.
2. Read the code and determine whether the behavior described in the
   acceptance criterion is actually achieved.
3. Mark the item as one of:
   - **OK** — implementation matches criterion; no code change.
   - **FIX** — implementation has a gap; minimal patch applied.
   - **MANUAL** — the only way to verify is runtime UI interaction
     (e.g. fade animation playback). Code path is correct but a
     human must run the app to confirm.
4. For every **FIX** item, the patch MUST be minimal, MUST NOT
   introduce new features, MUST keep `swift build` green with zero new
   warnings, and MUST not regress any other audited item.

## Verification items

### From Phase 4 acceptance (12 items)

1. `swift build` succeeds with zero new warnings.
2. `KeyableNonActivatingPanel.swift` exists; both `ActionBarPanel` and
   `ResponsePanel` construct their internal panel as
   `KeyableNonActivatingPanel`.
3. Drag-selecting text shows the ActionBar exactly as before; clicking
   an icon still shows the ResponsePanel directly under the ActionBar
   (or above when there is no room below).
4. **ESC** while either panel is visible dismisses both panels with a
   fade animation (no app-activation flicker).
   - The implementation now uses `cancelOperation(_:)` on
     `KeyableNonActivatingPanel` (not `NSEvent.addLocalMonitor`). The
     agent MUST verify both `ActionBarPanel.nsPanel` and
     `ResponsePanel.nsPanel` have their `onEscapePressed` closure set,
     and that the closure is set in `PopupController.show` /
     `handleAction` paths so it survives panel reuse.
5. **Hover-out**: when the mouse stays outside both panels for 1.0 s,
   both panels dismiss with the fade animation.
   - Exception: during `.loading` state, hover-out does NOT dismiss.
   - Exception: when pinned, hover-out does NOT dismiss.
   - Implementation now uses SwiftUI `.onHover` in `ActionBarView` and
     `ResponseView`, plumbed via `setHoverHandler` callbacks to
     `PopupController.updateHoverState(overActionBar:overResponse:)`.
     The agent MUST trace the wiring end-to-end:
     `ActionBarView.onHover` → `ActionBarPanel.onHover` →
     `setHoverHandler` registered closure → `PopupController.updateHoverState`.
     Same for `ResponseView`.
6. **Outside click**: dismisses both panels, EXCEPT when pinned or
   when loading. Fade animation runs.
   - Implementation now uses `NSWindowDelegate.windowDidResignKey(_:)`
     instead of NSEvent monitors. The agent MUST verify:
     - both panels' `.delegate = self` is set inside `PopupController.show`
       / `handleAction` (NOT in init, because the panels are created
       lazily on first show).
     - `windowDidResignKey` checks `NSApp.keyWindow` and only dismisses
       when the new key window is neither of our two panels and the
       response is not pinned.
7. **Pin toggle**: the response header has a pin icon (`pin` / `pin.fill`).
   Clicking toggles `isPinned`. While pinned:
   - outside-click does not dismiss
   - hover-out timer does not fire
   - ESC still dismisses (acts as an explicit cancel)
8. **ResponsePanel is draggable**: user can grab the response panel's
   background and move it. ActionBar remains non-movable.
   - `ResponsePanel.ensurePanel` MUST set `isMovableByWindowBackground = true`.
   - `ActionBarPanel.ensurePanel` MUST set `isMovableByWindowBackground = false`.
9. **Animation**: dismissal of the ResponsePanel uses a 0.3 s ease-in/out
   fade. ActionBar dismisses immediately.
   - `ResponsePanel.dismissAnimated(completion:)` uses
     `NSAnimationContext.runAnimationGroup` with `duration = 0.3` and
     `CAMediaTimingFunction(name: .easeInEaseOut)`.
10. After a dismissal cycle, a subsequent show is fully opaque (no
    leftover `alphaValue = 0` state).
    - `ResponsePanel.dismissAnimated` completion sets
      `panel?.alphaValue = 1.0`. Also `ResponsePanel.dismiss()` (the
      synchronous path) does the same.
11. Cancelled tasks remain silent — no "canceled" message ever surfaces
    in the response.
    - `PopupController.handleAction` catches BOTH `CancellationError`
      AND `URLError(.cancelled)` with empty body (`return`).
12. After clicking a new action while a response is in flight, the
    previous response is replaced with `.loading` and the new response
    arrives without a flash of stale text. No "canceled" appears.
    - `handleAction` cancels `currentTask` AND `hideTimer` at the top
      before launching the new Task, and calls
      `responsePanel.update(state: .loading)` before awaiting.

### From Phase 4.1 (2 items)

13. **Double-click triggers selection-only ActionBar**. Code path:
    `SelectionMonitor.handle(type:location:clickCount:)` enters the
    `.leftMouseDown` arm and, when `clickCount >= 2`, calls
    `triggerSelection()`. `triggerSelection` calls
    `SelectionExtractor.currentSelection()`; if nil, no ActionBar is
    shown. The agent MUST confirm the helper is shared between drag
    and double-click paths so the gating logic cannot diverge.
14. **Empty-space double-click does NOT crash.** Code path:
    `SelectionExtractor.currentSelection()` MUST guard the pasteboard
    fallback behind `isInputMonitoringTrusted()` which calls
    `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted`.
    When not granted, the function returns nil instead of calling
    `pasteboardSelection()` (which would post a synthetic Cmd+C via
    `CGEvent.post(tap: .cghidEventTap)` and trigger TCC kill).

## Constraints

- macOS 14+, Swift 5.9+, SwiftUI + AppKit. No new third-party deps.
- No new public APIs unless required to close a gap. Prefer minimal
  in-place patches over refactors.
- `swift build` MUST stay green with zero new warnings.
- Do NOT introduce `NSEvent.addGlobal/LocalMonitorForEvents` calls in
  `PopupController` — Phase 4 deliberately removed them in favor of
  `cancelOperation` + `windowDidResignKey` + SwiftUI `.onHover`. Any
  fix MUST stay within that pattern.
- Do NOT change `SelectionMonitor`'s public callback shape. The
  callback is `(SelectionPayload, CGPoint) -> Void` and is consumed
  by `AppDelegate`.

## macOS edge-case checklist (Appendix C)

For any FIX you apply, explicitly answer the Appendix C checklist for
that fix:

- [ ] Permissions added/removed.
- [ ] Permission revoked at runtime behavior.
- [ ] Key window expectations (`canBecomeKey`, `cancelOperation`).
- [ ] Z-order interaction between the two panels.
- [ ] Animation anchor direction (top vs bottom).
- [ ] Mouse / key event routing: who is key, who receives
      `windowDidResignKey`.
- [ ] Cancellation: both `CancellationError` and `URLError(.cancelled)`
      silent.
- [ ] Resource cleanup on `dismiss()`.
- [ ] `UserDefaults` schema (§15.1).

## Acceptance Criteria

1. `swift build` succeeds with zero new warnings.
2. For each of the 14 items above, the report includes:
   - the file + lines that implement it,
   - the verdict (`OK` / `FIX` / `MANUAL`),
   - if `FIX`, a one-line description of the patch and why it was
     needed.
3. The total LOC delta in the PR is ≤ 80 (excluding generated /
   trivial whitespace). This is a cleanup PR, not a refactor.
4. The `PopupController` does NOT regain any `NSEvent.addLocalMonitor`
   or `NSEvent.addGlobalMonitor` call.
5. The list of `MANUAL` items is gathered into a short section at the
   bottom of the agent's report so the human reviewer knows exactly
   what scenarios to run before stamping Phase 4 complete.

## Out of Scope

- Any Phase 5 work (Model discovery, Position picker UI). That is
  `docs/tasks/phase-5.md`.
- Any Phase 6 work (permissions polish, Keychain).
- Refactoring `PopupController` into smaller types.
- Replacing `NSPanel` subclassing with `NSWindow`.
- Theming / colors / fonts.
- Animation curve tuning beyond the spec.
