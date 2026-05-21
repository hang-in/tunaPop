import AppKit
import Foundation

@MainActor
final class SelectionMonitor {
    private var monitors: [Any] = []
    private var dragStart: CGPoint?
    private var didDrag = false
    private let onSelection: (SelectionPayload, CGPoint) -> Void

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
            NSLog("tunaPop SelectionMonitor: started (axTrusted=\(Accessibility.isTrusted))")
        } else {
            NSLog("tunaPop SelectionMonitor: addGlobalMonitorForEvents returned nil")
        }
    }

    func stop() {
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
            NSLog("tunaPop SelectionMonitor: mouseDown clickCount=\(clickCount) loc=\(location)")
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
        let point = NSEvent.mouseLocation
        NSLog("tunaPop SelectionMonitor: triggerSelection at \(point) delay=\(delayMillis)")
        Task {
            try? await Task.sleep(for: .milliseconds(delayMillis))
            guard let payload = await SelectionExtractor.currentSelection() else { return }
            onSelection(payload, point)
        }
    }
}
