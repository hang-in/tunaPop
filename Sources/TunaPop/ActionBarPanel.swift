import AppKit
import SwiftUI

@MainActor
final class ActionBarPanel {
    private var panel: NSPanel?
    private let onAction: (Action) -> Void
    private(set) var isVisible: Bool = false
    private var onHover: ((Bool) -> Void)?

    var nsPanel: NSPanel? { panel }

    init(onAction: @escaping (Action) -> Void) {
        self.onAction = onAction
    }

    func setHoverHandler(_ handler: @escaping (Bool) -> Void) {
        self.onHover = handler
    }

    func show(actions: [Action], at anchor: CGPoint, position: ActionBarPosition) {
        let panel = ensurePanel()

        let hostingView = NSHostingView(
            rootView: ActionBarView(
                actions: actions,
                onAction: { [weak self] action in
                    self?.onAction(action)
                },
                onHoverStateChanged: { [weak self] hovering in
                    self?.onHover?(hovering)
                }
            )
        )

        var size = hostingView.fittingSize
        if size.width <= 0 || size.height <= 0 {
            size = CGSize(width: 100, height: 36)
        }
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView

        let origin = position.origin(forAnchor: anchor, barSize: size)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        if Log.isVerbose { Log.popup.debug("ActionBarPanel show size=\(size.width)x\(size.height) level=\(panel.level.rawValue)") }
        isVisible = true
    }

    func dismiss() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func bringToFront() {
        panel?.makeKeyAndOrderFront(nil)
    }

    func contains(point: CGPoint) -> Bool {
        panel?.frame.contains(point) ?? false
    }

    var frame: CGRect {
        panel?.frame ?? .zero
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyableNonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 36),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        self.panel = panel
        return panel
    }
}
