import Foundation

@MainActor
final class LLMTaskRunner {
    private let settings: AppSettings
    private let responsePanel: ResponsePanel
    private var currentTask: Task<Void, Never>?

    init(settings: AppSettings, responsePanel: ResponsePanel) {
        self.settings = settings
        self.responsePanel = responsePanel
    }

    func cancel() {
        if currentTask != nil {
            Log.network.info("LLMTaskRunner cancel() called: cancelling active task")
        }
        currentTask?.cancel()
        currentTask = nil
    }

    func isRunning() -> Bool {
        currentTask != nil
    }

    func run(
        prompt: String,
        payload: SelectionPayload,
        includeSelectionContext: Bool,
        systemPrompt: String?,
        onDone: @escaping (String) -> Void
    ) {
        cancel()

        responsePanel.update(state: .loading)

        let model = settings.model
        let payloadCopy = payload

        currentTask = Task { @MainActor [weak self] in
            do {
                guard let self else { return }
                let client = LLMClientFactory.make(for: self.settings)
                let stream = client.chatStream(
                    model: model,
                    prompt: prompt,
                    payload: payloadCopy,
                    includeSelectionContext: includeSelectionContext,
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
                        let finalResult = result.content.isEmpty ? accumulated : result.content
                        let metadata = ResponseMetadata(
                            model: result.model,
                            totalTokens: result.promptTokens + result.completionTokens
                        )
                        self.responsePanel.update(state: .success(finalResult, metadata))
                        onDone(finalResult)
                        self.currentTask = nil
                        return
                    }
                }
            } catch is CancellationError {
                Log.network.info("LLMTaskRunner currentTask cancelled (CancellationError)")
            } catch let urlError as URLError where urlError.code == .cancelled {
                Log.network.info("LLMTaskRunner currentTask cancelled (URLError.cancelled)")
            } catch {
                Log.network.error("LLMTaskRunner currentTask error: \(error.localizedDescription)")
                self?.responsePanel.update(state: .failure(error.localizedDescription))
            }
            self?.currentTask = nil
        }
    }
}
