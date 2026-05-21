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

        if Log.isVerbose { Log.selection.debug("AX returned no text; trying Clipboard Copy Fallback") }
        if let fallbackText = await copyToClipboardFallback(), !fallbackText.isBlank {
            Log.selection.info("Clipboard Copy Fallback success: \(fallbackText.count) chars")
            return .text(fallbackText)
        }

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
    private static func copyToClipboardFallback() async -> String? {
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        
        // Backup existing clipboard items
        var backupItems: [NSPasteboardItem] = []
        if let pbItems = pasteboard.pasteboardItems {
            for item in pbItems {
                let newItem = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        newItem.setData(data, forType: type)
                    }
                }
                backupItems.append(newItem)
            }
        }
        
        // Clear pasteboard before copy attempt to monitor change
        pasteboard.clearContents()
        
        // Simulate Cmd+C
        // Carbon virtual key code for 'C' is 8 (kVK_ANSI_C)
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let cDown = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true) else {
            // Restore backup if event creation failed
            if !backupItems.isEmpty {
                pasteboard.writeObjects(backupItems)
            }
            return nil
        }
        cDown.flags = .maskCommand
        
        guard let cUp = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false) else {
            if !backupItems.isEmpty {
                pasteboard.writeObjects(backupItems)
            }
            return nil
        }
        cUp.flags = .maskCommand
        
        cDown.post(tap: .cghidEventTap)
        cUp.post(tap: .cghidEventTap)
        
        // Wait for clipboard to update (up to 150ms)
        var resultText: String? = nil
        for _ in 0..<15 {
            if pasteboard.changeCount != previousChangeCount {
                if let text = pasteboard.string(forType: .string), !text.isBlank {
                    resultText = text
                }
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        
        // Restore backup
        pasteboard.clearContents()
        if !backupItems.isEmpty {
            pasteboard.writeObjects(backupItems)
        }
        
        return resultText
    }
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}


