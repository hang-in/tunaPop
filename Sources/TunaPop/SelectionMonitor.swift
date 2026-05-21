import AppKit
import Foundation

@MainActor
final class SelectionMonitor {
    private var monitors: [Any] = []
    private var dragStart: CGPoint?
    private var didDrag = false
    private let onSelection: (SelectionPayload, CGPoint) -> Void
    private var triggerTask: Task<Void, Never>?

    init(onSelection: @escaping (SelectionPayload, CGPoint) -> Void) {
        self.onSelection = onSelection
    }

    func start() {
        stop()

        let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            let type = event.type
            let location = event.locationInWindow
            let clickCount = event.clickCount
            Task { @MainActor in
                self?.handle(type: type, location: location, clickCount: clickCount)
            }
        }) {
            monitors.append(monitor)
            Log.selection.info("SelectionMonitor started (axTrusted=\(Accessibility.isTrusted))")
        } else {
            Log.selection.error("addGlobalMonitorForEvents returned nil")
        }
    }

    func stop() {
        triggerTask?.cancel()
        triggerTask = nil
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }

        monitors.removeAll()
        dragStart = nil
        didDrag = false
    }

    private func handle(type: NSEvent.EventType, location: CGPoint, clickCount: Int) {
        switch type {
        case .leftMouseDown:
            if Log.isVerbose { Log.selection.debug("mouseDown clickCount=\(clickCount)") }
            triggerTask?.cancel()
            triggerTask = nil
            dragStart = location
            didDrag = false
            if clickCount >= 2 {
                triggerSelection(delayMillis: 200)
            }
        case .leftMouseDragged:
            guard let dragStart else { return }
            let distance = hypot(location.x - dragStart.x, location.y - dragStart.y)
            if distance > 6 {
                didDrag = true
            }
        case .leftMouseUp:
            guard didDrag else { return }
            triggerSelection(delayMillis: 120)
        default:
            break
        }
    }

    private func triggerSelection(delayMillis: Int) {
        triggerTask?.cancel()
        let point = NSEvent.mouseLocation
        let initialApp = NSWorkspace.shared.frontmostApplication
        if Log.isVerbose { Log.selection.debug("triggerSelection delay=\(delayMillis)") }
        triggerTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(delayMillis))
                guard !Task.isCancelled else { return }
                
                let currentApp = NSWorkspace.shared.frontmostApplication
                if initialApp?.processIdentifier != currentApp?.processIdentifier {
                    if Log.isVerbose { Log.selection.debug("frontmost application changed during delay") }
                    return
                }
                
                guard let payload = await SelectionExtractor.currentSelection() else { return }
                guard !Task.isCancelled else { return }
                
                onSelection(payload, point)
            } catch {
                // Sleep cancelled
            }
        }
    }
}
