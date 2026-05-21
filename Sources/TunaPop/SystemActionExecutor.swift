import AppKit
@preconcurrency import ApplicationServices

@MainActor
enum SystemActionExecutor {
    static func run(_ type: SystemActionType, payload: SelectionPayload) {
        guard case .text(let text) = payload else { return }
        switch type {
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .paste:
            performPaste(text: NSPasteboard.general.string(forType: .string) ?? "")
        case .webSearch:
            openWebSearch(for: text)
        case .lookUp:
            openLookUp(for: text)
        }
    }

    // MARK: - Implementations

    private static func openWebSearch(for query: String) {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func openLookUp(for word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "dict://\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func performPaste(text: String) {
        guard Accessibility.isTrusted else { return }
        guard !text.isEmpty else { return }
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return
        }
        let focused = focusedValue as! AXUIElement
        AXUIElementSetAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
    }
}
