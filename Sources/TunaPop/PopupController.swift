import AppKit
import SwiftUI

@MainActor
final class PopupController {
    private let settings: AppSettings
    private let actionBarPanel: ActionBarPanel
    private let responsePanel: ResponsePanel
    private var lastPayload: SelectionPayload?
    private var lastAnchor: CGPoint = .zero
    private var currentTask: Task<Void, Never>?
    private var lastResponse: String = ""
    private var hideTimer: Timer?
    private let hoverGraceInterval: TimeInterval = 1.0

    private var isHoveringActionBar = false
    private var isHoveringResponsePanel = false

    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

    init(settings: AppSettings) {
        self.settings = settings
        self.responsePanel = ResponsePanel()

        var actionHandler: ((Action) -> Void)?
        let bar = ActionBarPanel { action in actionHandler?(action) }
        self.actionBarPanel = bar

        actionHandler = { [weak self] action in
            Task { @MainActor in self?.handleAction(action) }
        }

        responsePanel.setCopyHandler { [weak self] in
            self?.copyResponse()
        }
        responsePanel.setPinHandler { [weak self] in
            self?.toggleResponsePinned()
        }

        actionBarPanel.setHoverHandler { [weak self] hovering in
            self?.updateHoverState(overActionBar: hovering)
        }
        responsePanel.setHoverHandler { [weak self] hovering in
            self?.updateHoverState(overResponse: hovering)
        }
    }

    func show(payload: SelectionPayload, at anchor: CGPoint) {
        currentTask?.cancel()
        currentTask = nil
        cancelHideTimer()
        lastPayload = payload
        lastAnchor = anchor
        lastResponse = ""
        responsePanel.dismiss()

        actionBarPanel.show(
            actions: Action.defaults,
            at: anchor,
            position: settings.actionBarPosition
        )

        startEventMonitors()
    }

    func dismiss() {
        currentTask?.cancel()
        currentTask = nil
        cancelHideTimer()
        stopEventMonitors()
        isHoveringActionBar = false
        isHoveringResponsePanel = false
        actionBarPanel.dismiss()
        responsePanel.dismissAnimated { }
        lastPayload = nil
        lastResponse = ""
    }

    private func handleAction(_ action: Action) {
        guard let payload = lastPayload else { return }
        cancelHideTimer()

        let actionBarFrame = actionBarPanel.frame
        actionBarPanel.dismiss()

        let gap: CGFloat = 6
        let initialResponseHeight: CGFloat = 80
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        let belowY = actionBarFrame.minY - initialResponseHeight - gap
        let aboveY = actionBarFrame.maxY + gap
        let placeBelow = belowY >= visibleFrame.minY + 8
        let resolvedY = placeBelow ? belowY : aboveY
        let anchorMode: ResponsePanel.Anchor = placeBelow ? .top : .bottom
        let origin = CGPoint(x: actionBarFrame.minX, y: resolvedY)

        responsePanel.show(at: origin, anchor: anchorMode)
        responsePanel.update(state: .loading)

        currentTask?.cancel()
        let prompt = action.prompt
        let payloadCopy = payload
        let endpoint = settings.endpoint
        let token = settings.apiToken
        let model = settings.model

        currentTask = Task { @MainActor [weak self] in
            do {
                let client = OllamaClient(endpoint: endpoint, token: token)
                let result = try await client.chat(model: model, prompt: prompt, payload: payloadCopy)
                try Task.checkCancellation()
                guard let self else { return }
                self.lastResponse = result.content
                let metadata = ResponseMetadata(
                    model: result.model,
                    totalTokens: result.promptEvalCount + result.evalCount
                )
                self.responsePanel.update(state: .success(result.content, metadata))
            } catch is CancellationError {
                return
            } catch let urlError as URLError where urlError.code == .cancelled {
                return
            } catch {
                self?.responsePanel.update(state: .failure(error.localizedDescription))
            }
        }
    }

    private func copyResponse() {
        guard !lastResponse.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lastResponse, forType: .string)
    }

    private func toggleResponsePinned() {
        responsePanel.setPinned(!responsePanel.pinned)
        if !responsePanel.pinned {
            updateHoverState()
        } else {
            cancelHideTimer()
        }
    }

    private func updateHoverState(overActionBar: Bool? = nil, overResponse: Bool? = nil) {
        if let overActionBar {
            self.isHoveringActionBar = overActionBar
        }
        if let overResponse {
            self.isHoveringResponsePanel = overResponse
        }

        if isHoveringActionBar || isHoveringResponsePanel {
            cancelHideTimer()
        } else {
            if responsePanel.pinned { return }
            if case .loading = responsePanel.currentState { return }
            scheduleHideTimer()
        }
    }

    private func scheduleHideTimer() {
        if hideTimer != nil { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: hoverGraceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    private func cancelHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private func startEventMonitors() {
        stopEventMonitors()

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor in self?.dismissIfOutside(location) }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            self.dismissIfOutside(NSEvent.mouseLocation)
            return event
        }
    }

    private func stopEventMonitors() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }

    private func dismissIfOutside(_ point: CGPoint) {
        if actionBarPanel.contains(point: point) || responsePanel.contains(point: point) {
            return
        }
        if responsePanel.pinned { return }
        if case .loading = responsePanel.currentState { return }
        dismiss()
    }
}
