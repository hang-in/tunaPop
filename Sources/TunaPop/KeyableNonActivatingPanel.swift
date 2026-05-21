import AppKit

final class KeyableNonActivatingPanel: NSPanel {
    var isKeyWindowCapable: Bool = false
    override var canBecomeKey: Bool { isKeyWindowCapable }
    override var canBecomeMain: Bool { isKeyWindowCapable }
}
