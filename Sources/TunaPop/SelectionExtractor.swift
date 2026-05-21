import AppKit
@preconcurrency import ApplicationServices
import IOKit.hid

enum SelectionExtractor {
    @MainActor
    static func currentSelection() async -> SelectionPayload? {
        guard Accessibility.isTrusted else {
            NSLog("tunaPop SelectionExtractor: AX not trusted, skipping all extraction paths")
            return nil
        }

        if let text = accessibilitySelectedText(), !text.isBlank {
            return .text(text)
        }

        NSLog("tunaPop SelectionExtractor: AX returned no text; pasteboard fallback disabled for v1 stability (revisit in Phase 6b)")
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

    @MainActor
    private static func pasteboardSelection() async -> SelectionPayload? {
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?.compactMap { $0.copy() as? NSPasteboardItem } ?? []
        let previousChangeCount = pasteboard.changeCount

        sendCopyShortcut()
        try? await Task.sleep(for: .milliseconds(160))

        defer {
            pasteboard.clearContents()
            pasteboard.writeObjects(previousItems)
        }

        guard pasteboard.changeCount != previousChangeCount else {
            return nil
        }

        if let text = pasteboard.string(forType: .string), !text.isBlank {
            return .text(text)
        }

        if let image = NSImage(pasteboard: pasteboard) {
            return .image(image)
        }

        return nil
    }

    @MainActor
    private static func sendCopyShortcut() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
