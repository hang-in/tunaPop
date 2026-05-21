import AppKit
import SwiftUI

@MainActor
final class ResponsePanel {
    enum Anchor {
        case top
        case bottom
    }

    private var panel: NSPanel?
    private var hostingView: NSHostingView<ResponseView>?
    private var onCopy: () -> Void = {}
    private var onTogglePin: () -> Void = {}
    private(set) var isVisible: Bool = false
    private(set) var currentState: ResponseState = .idle
    private var anchor: Anchor = .top
    private var isPinned: Bool = false
    private var onHover: ((Bool) -> Void)?

    var nsPanel: NSPanel? { panel }

    init() {}

    func setHoverHandler(_ handler: @escaping (Bool) -> Void) {
        self.onHover = handler
    }

    var pinned: Bool { isPinned }

    func setCopyHandler(_ handler: @escaping () -> Void) {
        self.onCopy = handler
    }

    func setPinHandler(_ handler: @escaping () -> Void) {
        self.onTogglePin = handler
    }

    func setPinned(_ pinned: Bool) {
        self.isPinned = pinned
        update(state: currentState)
    }

    func show(at origin: CGPoint, anchor: Anchor = .top) {
        self.anchor = anchor
        let panel = ensurePanel()
        let host = ensureHostingView(initialState: .loading)
        currentState = .loading

        var size = host.fittingSize
        if size.width <= 0 { size.width = 360 }
        if size.height <= 0 { size.height = 80 }
        host.frame = NSRect(origin: .zero, size: size)

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        isVisible = true
    }

    func update(state: ResponseState) {
        guard let panel else { return }
        currentState = state
        let host = ensureHostingView(initialState: state)
        host.rootView = ResponseView(
            state: state,
            isPinned: isPinned,
            onCopy: { [weak self] in self?.onCopy() },
            onTogglePin: { [weak self] in self?.onTogglePin() },
            onHoverStateChanged: { [weak self] hovering in self?.onHover?(hovering) }
        )

        let oldFrame = panel.frame
        var newSize = host.fittingSize
        if newSize.width <= 0 { newSize.width = 360 }
        if newSize.height <= 0 { newSize.height = oldFrame.height }
        host.frame = NSRect(origin: .zero, size: newSize)

        let newOrigin: CGPoint
        switch anchor {
        case .top:
            newOrigin = CGPoint(x: oldFrame.minX, y: oldFrame.maxY - newSize.height)
        case .bottom:
            newOrigin = CGPoint(x: oldFrame.minX, y: oldFrame.minY)
        }
        panel.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel?.alphaValue = 1.0
        isVisible = false
        currentState = .idle
        isPinned = false
    }

    func dismissAnimated(completion: @escaping @MainActor () -> Void) {
        guard let panel, isVisible else {
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else {
                    completion()
                    return
                }
                self.panel?.orderOut(nil)
                self.panel?.alphaValue = 1.0
                self.isVisible = false
                self.currentState = .idle
                self.isPinned = false
                completion()
            }
        })
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
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 80),
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
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        self.panel = panel
        return panel
    }

    private func ensureHostingView(initialState: ResponseState) -> NSHostingView<ResponseView> {
        if let hostingView {
            return hostingView
        }
        let view = ResponseView(
            state: initialState,
            isPinned: isPinned,
            onCopy: { [weak self] in self?.onCopy() },
            onTogglePin: { [weak self] in self?.onTogglePin() },
            onHoverStateChanged: { [weak self] hovering in self?.onHover?(hovering) }
        )
        let host = NSHostingView(rootView: view)
        panel?.contentView = host
        self.hostingView = host
        return host
    }
}
