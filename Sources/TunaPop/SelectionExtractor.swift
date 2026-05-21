import AppKit
@preconcurrency import ApplicationServices

enum SelectionExtractor {
    @MainActor
    static func currentSelection() async -> SelectionPayload? {
        guard Accessibility.isTrusted else {
            Log.permissions.info("AX not trusted")
            return nil
        }

        if let text = accessibilitySelectedText(), !text.isBlank {
            return .text(text)
        }

        if Log.isVerbose { Log.selection.debug("AX returned no text; AppleScript fallback deferred to post-v1") }
        return nil
    }

    @MainActor
    private static func accessibilitySelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success else {
            return nil
        }

        guard let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }

        let focused = focusedValue as! AXUIElement
        var selectedTextValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectedTextValue
        ) == .success else {
            return nil
        }

        return selectedTextValue as? String
    }
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

