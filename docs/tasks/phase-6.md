# Phase 6 — Permissions polish + Keychain

## Phase

Phase 6 of the production master plan. Combines two related concerns
because they share `SettingsView`:

- **6a** — Migrate `apiToken` from `UserDefaults` to Keychain.
- **6b** — Input Monitoring request UI, runtime permission status,
  menu-bar permission indicator, Settings Permissions section,
  non-localhost endpoint warning.

## References

- `docs/MASTER_SPEC.md` §4.3 / §4.4 (Privacy + Security)
- `docs/MASTER_SPEC.md` §5 (Privacy & Permissions matrix + request flow)
- `docs/MASTER_SPEC.md` §15.2 (Keychain schema)
- `docs/MASTER_SPEC.md` §3.7 (Menu bar items)
- `docs/MASTER_SPEC.md` §14.3 (Settings tabs — at minimum the "권한" section)
- `docs/MASTER_SPEC.md` Appendix B (macOS API caveats — Input Monitoring
  TCC kill on `CGEvent.post(.cghidEventTap)` without permission)
- `docs/MASTER_SPEC.md` Appendix C (per-phase checklist)

## Focus

Make the app's token storage safe enough to ship (Keychain), give
the user a clear path to grant Input Monitoring, surface the live
state of both permissions in two places (menu bar + Settings), and
warn before the user accidentally sends selection text to a remote
endpoint.

Files to add:
- `Sources/TunaPop/KeychainHelper.swift`
- `Sources/TunaPop/InputMonitoring.swift`

Files to modify:
- `Sources/TunaPop/AppSettings.swift` (token storage swap)
- `Sources/TunaPop/SettingsView.swift` (Permissions section, endpoint warning)
- `Sources/TunaPop/TunaPopApp.swift` (status icon tint, "Grant Input Monitoring..." menu item)

Files NOT to modify:
- `Sources/TunaPop/Accessibility.swift` (already implements AX check; do not duplicate)
- `Sources/TunaPop/SelectionExtractor.swift` (pasteboard fallback intentionally disabled in v1; do not re-enable here)
- `Sources/TunaPop/SelectionMonitor.swift`
- `Sources/TunaPop/SelectionPayload.swift`
- `Sources/TunaPop/Action.swift`
- `Sources/TunaPop/ActionBarPosition.swift`
- `Sources/TunaPop/ActionBarPanel.swift`
- `Sources/TunaPop/ActionBarView.swift`
- `Sources/TunaPop/ResponsePanel.swift`
- `Sources/TunaPop/ResponseView.swift`
- `Sources/TunaPop/ResponseState.swift`
- `Sources/TunaPop/PopupController.swift`
- `Sources/TunaPop/OllamaClient.swift`
- `Sources/TunaPop/TooltipImageButton.swift`
- `Sources/TunaPop/KeyableNonActivatingPanel.swift`

## Constraints

- macOS 14+, Swift 5.9+, SwiftUI + AppKit. No third-party deps.
- `@MainActor` on every type that mutates AppKit / SwiftUI state.
- `swift build` MUST succeed with zero new warnings.
- Korean UI strings as specified below; do not invent additional copy.
- Use only system frameworks: `Foundation`, `Security` (for Keychain),
  `IOKit.hid` (for Input Monitoring check / request).
- Do not introduce `NSAppleScript` or other broad permission usages.
- Comments minimal. No emoji.

---

## Part A — Keychain migration (6a)

### `KeychainHelper.swift` (new)

```swift
import Foundation
import Security

enum KeychainHelper {
    static let service = "app.tunapop.token"

    static func set(_ value: String, forAccount account: String) throws
    static func get(forAccount account: String) -> String?
    static func remove(forAccount account: String) throws

    enum Failure: Error {
        case unhandled(OSStatus)
    }
}
```

Implementation requirements:

- Use `kSecClassGenericPassword`.
- Attribute keys: `kSecClass`, `kSecAttrService`, `kSecAttrAccount`,
  `kSecValueData`.
- `set(_:forAccount:)` MUST:
  1. Encode `value.data(using: .utf8)`. If empty string, call
     `remove(forAccount:)` and return.
  2. First call `SecItemUpdate` with attributes
     `[kSecClass, kSecAttrService, kSecAttrAccount]` and update
     dictionary `[kSecValueData: data]`.
  3. If `SecItemUpdate` returns `errSecItemNotFound`, fall back to
     `SecItemAdd`.
  4. Any other non-`errSecSuccess` status MUST throw
     `Failure.unhandled(status)`.
- `get(forAccount:)` MUST:
  1. Build query with `[kSecClass, kSecAttrService, kSecAttrAccount,
     kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]`.
  2. Call `SecItemCopyMatching`.
  3. On success, return `String(data: data, encoding: .utf8)`.
  4. On `errSecItemNotFound`, return nil.
  5. On any other error, return nil (do NOT throw — read failure is
     non-fatal at the UI layer).
- `remove(forAccount:)` MUST:
  1. Build query as in `get`.
  2. Call `SecItemDelete`.
  3. Treat `errSecItemNotFound` and `errSecSuccess` as success.
  4. Other statuses throw `Failure.unhandled`.

`KeychainHelper` is `enum` (no instance state). All methods static.
Not `@MainActor` — Keychain calls are thread-safe and may be invoked
from any actor.

### `AppSettings.swift` change

Goal: move `apiToken` from `UserDefaults` to Keychain. Migrate any
existing `UserDefaults` value once on first launch after upgrade.

Current code:

```swift
@Published var apiToken: String {
    didSet { UserDefaults.standard.set(apiToken, forKey: Self.apiTokenKey) }
}
private static let apiTokenKey = "apiToken"
// In init():
apiToken = UserDefaults.standard.string(forKey: Self.apiTokenKey) ?? ""
```

Change to:

```swift
@Published var apiToken: String {
    didSet {
        try? KeychainHelper.set(apiToken, forAccount: Self.tokenAccount)
    }
}
private static let tokenAccount = "ollama"
private static let legacyApiTokenKey = "apiToken"

// In init(), BEFORE assigning apiToken:
let migrated: String? = {
    if let legacy = UserDefaults.standard.string(forKey: Self.legacyApiTokenKey),
       !legacy.isEmpty {
        try? KeychainHelper.set(legacy, forAccount: Self.tokenAccount)
        UserDefaults.standard.removeObject(forKey: Self.legacyApiTokenKey)
        return legacy
    }
    return nil
}()
apiToken = migrated ?? KeychainHelper.get(forAccount: Self.tokenAccount) ?? ""
```

Rationale:
- One-time migration moves any pre-Phase-6 value out of UserDefaults
  into Keychain, then removes the UserDefaults entry.
- After migration, the source of truth is Keychain.
- `didSet` writes every change to Keychain. Empty string triggers
  `KeychainHelper.set` which delegates to `remove` per its spec.

`apiTokenKey` is renamed to `legacyApiTokenKey` to make its purpose
unambiguous.

---

## Part B — Permissions polish (6b)

### `InputMonitoring.swift` (new)

```swift
import IOKit.hid

enum InputMonitoring {
    static var isTrusted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    static func request() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
}
```

`isTrusted` is a synchronous, cheap check. `request()` shows the
system dialog the first time the app calls it; subsequent calls
return the cached decision (true/false) without re-prompting. Per
Apple docs, the user MUST go to System Settings → Privacy & Security
→ Input Monitoring to flip the decision after the first answer.

### `SettingsView.swift` changes

Add a `Section("권한")` after the existing `"기본 동작"` Section,
BEFORE the error display section. Inside, render two rows — one for
Accessibility, one for Input Monitoring — each showing a status
icon, the permission name, and an action button.

```swift
Section("권한") {
    permissionRow(
        label: "Accessibility",
        isTrusted: Accessibility.isTrusted,
        actionTitle: "시스템 설정 열기",
        action: { openSystemSettings(.accessibility) }
    )
    permissionRow(
        label: "Input Monitoring",
        isTrusted: InputMonitoring.isTrusted,
        actionTitle: "권한 요청",
        action: { InputMonitoring.request() }
    )
}
```

Helper view:

```swift
@ViewBuilder
private func permissionRow(
    label: String,
    isTrusted: Bool,
    actionTitle: String,
    action: @escaping () -> Void
) -> some View {
    HStack(spacing: 8) {
        Image(systemName: isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(isTrusted ? Color.green : Color.orange)
        Text(label)
        Spacer()
        Button(actionTitle, action: action)
            .buttonStyle(.borderless)
    }
}
```

Add a SwiftUI Timer-driven `@State` that re-reads `isTrusted` every
2 seconds while Settings is open, so toggling permission in System
Settings reflects in tunaPop's UI without re-opening:

```swift
@State private var permissionRefreshTick = Date()

// at the end of the Form .task block (chained):
.onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
    permissionRefreshTick = Date()
}
```

The `permissionRefreshTick` is used in the row's `isTrusted` reads
via `_ = permissionRefreshTick` inside the section to force re-eval.
Use a `let _ = permissionRefreshTick` pattern in the body if needed.

`openSystemSettings(.accessibility)`:

```swift
private enum PrivacyPanel: String {
    case accessibility = "Privacy_Accessibility"
    case inputMonitoring = "Privacy_ListenEvent"
}

private func openSystemSettings(_ panel: PrivacyPanel) {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(panel.rawValue)")
        ?? URL(string: "x-apple.systempreferences:com.apple.preference.security")!
    NSWorkspace.shared.open(url)
}
```

Use the same helper for both rows. For Input Monitoring, the
`"권한 요청"` button can fall back to opening System Settings if
`InputMonitoring.request()` returned false on a prior call — but
v1 keeps it simple: just call `request()`. The user can also open
System Settings via the Accessibility row's button which lands in the
same Privacy & Security panel.

### Non-localhost endpoint warning

Inside `Section("Ollama")`, AFTER the Endpoint `TextField`, add a
conditional warning row:

```swift
if !isLocalEndpoint(settings.endpoint) {
    HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
        Text("이 엔드포인트는 로컬이 아닙니다. 선택한 텍스트가 외부 네트워크로 전송됩니다.")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}
```

Helper:

```swift
private func isLocalEndpoint(_ raw: String) -> Bool {
    guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
          let host = url.host else {
        return true  // unparseable; do not nag the user with a false positive
    }
    let lower = host.lowercased()
    return lower == "localhost" || lower == "127.0.0.1" || lower == "::1"
}
```

Re-evaluated on every render as `settings.endpoint` changes.

### `TunaPopApp.swift` changes

Two changes:

1. **Status icon tint** — when either permission is missing, tint
   the status item button orange so the user sees a visible alert.
2. **"Grant Input Monitoring..." menu item** — between
   "Check Accessibility" and the separator.

#### Status icon tint

In `configureStatusItem()`, after setting the image, call a new
private helper:

```swift
private func updateStatusItemAppearance() {
    guard let button = statusItem?.button else { return }
    let needsPermissions = !Accessibility.isTrusted || !InputMonitoring.isTrusted
    button.contentTintColor = needsPermissions ? .systemOrange : nil
    button.toolTip = needsPermissions ? "tunaPop — 권한 필요" : "tunaPop"
}
```

Call this:
- At the end of `configureStatusItem()`.
- After `Accessibility.requestIfNeeded()`.
- Inside a `Timer.scheduledTimer(withTimeInterval: 5, repeats: true)`
  added in `applicationDidFinishLaunching` that fires
  `updateStatusItemAppearance()` (so external permission flips
  propagate). Store the timer in a new private property so it can
  be invalidated if needed (no current shutdown path needs it, but
  good hygiene).

#### Menu item

In `configureStatusItem()`, between "Check Accessibility" and the
`.separator()`:

```swift
menu.addItem(NSMenuItem(
    title: "Grant Input Monitoring...",
    action: #selector(grantInputMonitoring),
    keyEquivalent: ""
))
```

Handler:

```swift
@objc private func grantInputMonitoring() {
    let granted = InputMonitoring.request()
    NSLog("tunaPop InputMonitoring.request -> \(granted)")
    updateStatusItemAppearance()
}
```

Note: `InputMonitoring.request()` returns true if granted (or
previously granted). It returns false if the user has not yet
answered or has denied. v1 does not chain into System Settings on
denial; the Permissions section in Settings is the recovery path.

---

## Acceptance Criteria

1. `swift build` succeeds with zero new warnings.
2. New files exist: `KeychainHelper.swift`, `InputMonitoring.swift`.
3. **Migration**: first launch after upgrading reads any
   pre-existing UserDefaults `"apiToken"` value, writes it to
   Keychain (service `"app.tunapop.token"`, account `"ollama"`),
   and removes the UserDefaults entry. Subsequent launches read
   from Keychain only.
4. **Empty token round-trip**: setting `apiToken = ""` removes the
   Keychain entry. Setting a non-empty value re-creates it. No
   stale empty-string entries.
5. **Permissions section** appears in Settings between "기본 동작"
   and the error display. Two rows: Accessibility, Input Monitoring.
   Each row has the green check or orange triangle icon matching
   live status.
6. **Live permission status refresh**: while Settings is open, toggle
   Accessibility in System Settings. Within ~2 seconds tunaPop's
   permissions row icon changes to match.
7. **"시스템 설정 열기"** button on the Accessibility row opens
   System Settings to the Privacy → Accessibility panel.
8. **"권한 요청"** button on the Input Monitoring row triggers
   `IOHIDRequestAccess` and shows the macOS dialog the first time.
   After the user clicks "Open System Settings" in the macOS dialog,
   tunaPop appears in the Input Monitoring list.
9. **Non-localhost warning**: typing `http://example.com:11434` into
   the Endpoint field renders an orange warning row immediately.
   Typing `http://localhost:11434` or `http://127.0.0.1:11434`
   removes the warning.
10. **Menu bar tint**: when either permission is missing, the
    `sparkles` menu bar icon is tinted system orange and the tooltip
    reads `"tunaPop — 권한 필요"`. When both permissions are
    granted, the icon returns to its template tint and tooltip
    reads `"tunaPop"`.
11. **"Grant Input Monitoring..." menu item** is present between
    "Check Accessibility" and the separator. Clicking it triggers
    `IOHIDRequestAccess` and refreshes the status icon tint.
12. **No regression**: drag-select → ActionBar still appears. Action
    click → ActionBar dismisses + ResponsePanel shows with metadata
    caption (Phase 5 follow-up behavior preserved).
13. `KeychainHelper` and `InputMonitoring` enums have only static
    members; no instance state.
14. The keychain item is owned by the current user account (default
    `kSecAttrAccessibleWhenUnlocked`-equivalent; do NOT request
    `kSecAttrAccessibleAfterFirstUnlock` or `...AlwaysThisDeviceOnly`).
    If accessibility flag is omitted the system default applies,
    which is fine.

## macOS edge-case checklist (Appendix C)

- [ ] Permissions: this PR ADDS Input Monitoring usage path (only
      the check + request, not `CGEvent.post`). No new actual usage
      of `CGEvent.post`. SelectionExtractor's pasteboard fallback
      stays disabled.
- [ ] Permission revoked at runtime: handled by the 2-second timer
      in Settings and the 5-second timer in AppDelegate. Status icon
      and Settings row both refresh automatically.
- [ ] Key window: no new floating panels.
- [ ] Z-order: no new panels.
- [ ] Animation anchor: N/A.
- [ ] Event routing: `Timer.scheduledTimer` uses RunLoop default
      mode; runs on main thread. UI updates are MainActor-safe.
- [ ] Cancellation: not applicable (no async LLM work in this PR).
- [ ] Resource cleanup: store the AppDelegate's permission-status
      timer in a property; do not invalidate (process-lifetime).
      The Settings `.onReceive(Timer.publish(...).autoconnect())` is
      a SwiftUI publisher; SwiftUI cancels the subscription when the
      view disappears.
- [ ] UserDefaults schema: `apiToken` key is REMOVED on migration.
      Document this in master spec §15.1 in a follow-up.

## Out of Scope

- Multi-provider Keychain accounts (Phase 17). v1 uses a single
  account name `"ollama"`.
- Onboarding window that walks the user through both permissions
  (Phase 8a).
- AppleScript fallback selection extraction (Phase 11).
- Privacy manifest (`PrivacyInfo.xcprivacy`) updates (Phase 12).
- Re-enabling the pasteboard selection fallback (Phase 11 or beyond).
- Localizing the new strings to English (Phase 9).
- Removing `Accessibility.requestIfNeeded()` on launch — keep the
  initial AX prompt at startup as today.
