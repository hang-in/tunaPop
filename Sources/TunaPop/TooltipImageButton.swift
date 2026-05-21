import AppKit
import SwiftUI

struct TooltipImageButton: NSViewRepresentable {
    let systemImage: String
    let toolTip: String
    let action: () -> Void

    func makeNSView(context: Context) -> TooltipNSButton {
        let button = TooltipNSButton(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.imagePosition = .imageOnly
        button.title = ""
        button.target = context.coordinator
        button.action = #selector(Coordinator.invoke)
        button.toolTip = toolTip
        applyImage(to: button)
        return button
    }

    func updateNSView(_ nsView: TooltipNSButton, context: Context) {
        nsView.toolTip = toolTip
        context.coordinator.action = action
        applyImage(to: nsView)
    }

    private func applyImage(to button: NSButton) {
        let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        button.image = image
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func invoke() { action() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
}

final class TooltipNSButton: NSButton {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .inVisibleRect,
        ]
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil))
    }
}
