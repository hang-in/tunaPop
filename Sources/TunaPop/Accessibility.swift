@preconcurrency import ApplicationServices

enum Accessibility {
    static func requestIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }
}
