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

    func isPointInOwnPanels(_ point: CGPoint) -> Bool {
        return actionBarPanel.contains(point: point) || responsePanel.contains(point: point)
    }

    func show(payload: SelectionPayload, at anchor: CGPoint) {
        if case .loading = responsePanel.currentState {
            if Log.isVerbose { Log.popup.debug("show ignored, still loading") }
            return
        }
        currentTask?.cancel()
        currentTask = nil
        cancelHideTimer()
        lastPayload = payload
        lastAnchor = anchor
        lastResponse = ""
        responsePanel.dismiss()

        let visibleBuiltins = Action.allBuiltins
            .filter { !settings.isHidden($0.id) }
            .map { settings.resolvedBuiltin($0) }
        let allActions = visibleBuiltins + settings.customActions
        actionBarPanel.show(
            actions: allActions,
            at: anchor,
            position: settings.actionBarPosition
        )

        startEventMonitors()
    }

    func dismiss() {
        if Log.isVerbose { Log.popup.debug("dismiss called") }
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

        if action.kind == .system, let systemType = action.systemType {
            actionBarPanel.dismiss()
            SystemActionExecutor.run(systemType, payload: payload)
            dismiss()
            return
        }

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
        let prompt = resolvePrompt(for: action, payload: payload)
        let payloadCopy = payload
        let model = settings.model
        let includeContext = !action.prompt.contains("{selection}")
        let systemPrompt = buildSystemPrompt(settings.responseLanguage)

        currentTask = Task { @MainActor [weak self] in
            do {
                guard let self else { return }
                let client = LLMClientFactory.make(for: self.settings)
                let stream = client.chatStream(
                    model: model,
                    prompt: prompt,
                    payload: payloadCopy,
                    includeSelectionContext: includeContext,
                    systemPrompt: systemPrompt
                )
                var accumulated = ""
                for try await event in stream {
                    try Task.checkCancellation()
                    switch event {
                    case .chunk(let piece):
                        accumulated += piece
                        self.responsePanel.update(state: .success(accumulated, nil))
                    case .done(let result):
                        self.lastResponse = result.content.isEmpty ? accumulated : result.content
                        let metadata = ResponseMetadata(
                            model: result.model,
                            totalTokens: result.promptTokens + result.completionTokens
                        )
                        self.responsePanel.update(state: .success(self.lastResponse, metadata))
                    }
                }
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
        let beforePinned = responsePanel.pinned
        responsePanel.setPinned(!beforePinned)
        if Log.isVerbose { Log.popup.debug("togglePin before=\(beforePinned) after=\(self.responsePanel.pinned)") }
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
        if Log.isVerbose { Log.popup.debug("hoverState actionBar=\(self.isHoveringActionBar) response=\(self.isHoveringResponsePanel) pinned=\(self.responsePanel.pinned)") }

        if isHoveringActionBar || isHoveringResponsePanel {
            cancelHideTimer()
        } else {
            if responsePanel.pinned {
                if Log.isVerbose { Log.popup.debug("hoverState skip schedule pinned") }
                return
            }
            if case .loading = responsePanel.currentState {
                if Log.isVerbose { Log.popup.debug("hoverState skip schedule loading") }
                return
            }
            if Log.isVerbose { Log.popup.debug("hoverState scheduling hide timer") }
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
        let inAction = actionBarPanel.contains(point: point)
        let inResponse = responsePanel.contains(point: point)
        if Log.isVerbose { Log.popup.debug("dismissIfOutside inAction=\(inAction) inResponse=\(inResponse) pinned=\(self.responsePanel.pinned)") }
        if inAction || inResponse {
            return
        }
        if responsePanel.pinned { return }
        if case .loading = responsePanel.currentState { return }
        if Log.isVerbose { Log.popup.debug("dismissIfOutside dismissing") }
        dismiss()
    }

    private func resolvePrompt(for action: Action, payload: SelectionPayload) -> String {
        let langName = settings.responseLanguage.systemPromptName ?? "Korean"
        let base: String
        switch action.id {
        case "translate":
            if case .text(let text) = payload, isShortWord(text) {
                base = "Explain the selected word in \(langName) dictionary format. Include meaning, part of speech, and one short example."
            } else {
                base = "Translate this selection into \(langName). Keep meaning and tone."
            }
        default:
            base = action.prompt
        }
        return substituteTemplate(base, payload: payload)
    }

    private func substituteTemplate(_ raw: String, payload: SelectionPayload) -> String {
        var result = raw
        if case .text(let text) = payload {
            result = result.replacingOccurrences(of: "{selection}", with: text)
        }
        let language = Locale.current.identifier
        result = result.replacingOccurrences(of: "{language}", with: language)
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        result = result.replacingOccurrences(of: "{appBundleID}", with: bundleID)
        return result
    }

    private func buildSystemPrompt(_ language: ResponseLanguage) -> String? {
        guard let name = language.systemPromptName else { return nil }
        return "Always reply in \(name). Use natural, concise wording. Do not add introductory or closing filler."
    }

    private func isShortWord(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 20 { return false }
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace })
        return tokens.count <= 2
    }
}
