# Phase 16 — Streaming chat (Ollama /api/chat stream:true)

## Phase

Phase 16 of the production master plan. Replace the non-streaming
`chat(...)` round-trip with a streaming variant that incrementally
appends tokens to the ResponsePanel as Ollama produces them. Big
perceived UX improvement — user sees the answer growing instead of
waiting 1–6 s for the full response.

## References

- `docs/MASTER_SPEC.md` §4.1 (Performance budgets), §6 (Errors),
  §12.2 (Streaming)
- `docs/MASTER_SPEC.md` Appendix B / C

## Focus

Stream Ollama's `/api/chat` response (line-delimited JSON, each line a
JSON object with `done: false/true`). Append `message.content`
chunks to a growing buffer. Update `ResponsePanel` after each chunk
so the user sees progressive text. On the terminal `done: true`
event, attach metadata (`model`, `prompt_eval_count`, `eval_count`).
Cancel-safe: cancelling the Task cancels the URLSession data task and
no partial state leaks.

Files to modify:
- `Sources/TunaPop/OllamaClient.swift` — add `chatStream(...)` API
- `Sources/TunaPop/PopupController.swift` — consume the stream

Files NOT to modify:
- `Sources/TunaPop/ResponseState.swift` — `.success(text, metadata?)`
  is reused. `metadata == nil` is the streaming-in-progress signal.
- `Sources/TunaPop/ResponsePanel.swift`, `ResponseView.swift` — they
  already redraw on each `update(state:)`.
- everything else.

## Constraints

- macOS 14+, Swift 5.9+. No new third-party deps.
- `@MainActor` for every AppKit/SwiftUI mutation. The stream
  consumption Task runs `@MainActor` so each `responsePanel.update`
  is safe.
- `swift build` MUST succeed with zero new warnings.
- Backward compatibility: the existing `chat(...)` non-streaming
  method stays so future internal callers (or fallback paths) keep
  working. The new method is additive.
- Cancellation: cancelling the consumer Task MUST also cancel the
  URLSession. `URLSession.bytes(for:)` honors task cancellation
  natively.
- `URLError(.cancelled)` and `CancellationError` MUST be silent
  (existing rule).

## Required types

### `OllamaClient.swift` — `chatStream` and the stream event type

Add a new public enum:

```swift
enum OllamaStreamEvent {
    case chunk(String)
    case done(OllamaChatResult)
}
```

Add a new method on `OllamaClient`:

```swift
func chatStream(
    model: String,
    prompt: String,
    payload: SelectionPayload,
    includeSelectionContext: Bool = true,
    systemPrompt: String? = nil
) -> AsyncThrowingStream<OllamaStreamEvent, Error>
```

Implementation outline:

```swift
func chatStream(
    model: String,
    prompt: String,
    payload: SelectionPayload,
    includeSelectionContext: Bool = true,
    systemPrompt: String? = nil
) -> AsyncThrowingStream<OllamaStreamEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                guard let baseURL = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw OllamaError.invalidEndpoint
                }
                let url = baseURL.appending(path: "api/chat")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanToken.isEmpty {
                    request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
                }
                let userMessage: OllamaMessage
                switch payload {
                case .text(let text):
                    if includeSelectionContext {
                        userMessage = OllamaMessage(role: "user", content: "\(prompt)\n\nSelection:\n\(text)", images: nil)
                    } else {
                        userMessage = OllamaMessage(role: "user", content: prompt, images: nil)
                    }
                case .image:
                    userMessage = OllamaMessage(role: "user", content: prompt, images: payload.imageBase64PNG.map { [$0] })
                }
                var messages: [OllamaMessage] = []
                if let systemPrompt, !systemPrompt.isEmpty {
                    messages.append(OllamaMessage(role: "system", content: systemPrompt, images: nil))
                }
                messages.append(userMessage)
                let body = OllamaChatRequest(model: model, messages: messages, stream: true)
                request.httpBody = try JSONEncoder().encode(body)

                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    throw OllamaError.requestFailed("Streaming request failed")
                }

                var accumulated = ""
                var finalModel = model
                var finalEvalCount = 0
                var finalPromptEvalCount = 0

                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard !line.isEmpty,
                          let data = line.data(using: .utf8),
                          let event = try? JSONDecoder().decode(OllamaStreamLine.self, from: data) else {
                        continue
                    }
                    if !event.message.content.isEmpty {
                        accumulated += event.message.content
                        continuation.yield(.chunk(event.message.content))
                    }
                    if event.done {
                        finalModel = event.model ?? model
                        finalEvalCount = event.evalCount ?? 0
                        finalPromptEvalCount = event.promptEvalCount ?? 0
                        let result = OllamaChatResult(
                            content: accumulated,
                            model: finalModel,
                            evalCount: finalEvalCount,
                            promptEvalCount: finalPromptEvalCount
                        )
                        continuation.yield(.done(result))
                        continuation.finish()
                        return
                    }
                }
                // Stream closed without explicit done; emit best-effort done.
                let result = OllamaChatResult(
                    content: accumulated,
                    model: finalModel,
                    evalCount: finalEvalCount,
                    promptEvalCount: finalPromptEvalCount
                )
                continuation.yield(.done(result))
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch let urlError as URLError where urlError.code == .cancelled {
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}
```

Supporting private struct (add next to `OllamaChatResponse`):

```swift
private struct OllamaStreamLine: Decodable {
    let model: String?
    let message: OllamaMessage
    let done: Bool
    let promptEvalCount: Int?
    let evalCount: Int?

    private enum CodingKeys: String, CodingKey {
        case model
        case message
        case done
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }
}
```

Notes:
- `URLSession.bytes(for:)` returns an `(AsyncBytes, URLResponse)`
  tuple. The `.lines` async iterator splits on `\n` which is exactly
  how Ollama frames its streaming JSON.
- `AsyncThrowingStream.onTermination` cancels the inner Task when
  the consumer stops iterating (e.g. consumer Task cancelled).
- Empty-content events (some streams send a leading empty event with
  metadata) are skipped from `chunk(...)` but still update accumulated
  on `done: true`.
- The "best-effort done" trailing block covers servers that close the
  connection without an explicit `done: true` line. The consumer
  always gets a `.done(...)` event.

### `PopupController.swift` — consume the stream

Replace the existing chat call in `handleAction(_:)`:

```swift
currentTask = Task { @MainActor [weak self] in
    do {
        let client = OllamaClient(endpoint: endpoint, token: token)
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
            guard let self else { return }
            switch event {
            case .chunk(let piece):
                accumulated += piece
                self.responsePanel.update(state: .success(accumulated, nil))
            case .done(let result):
                self.lastResponse = result.content.isEmpty ? accumulated : result.content
                let metadata = ResponseMetadata(
                    model: result.model,
                    totalTokens: result.promptEvalCount + result.evalCount
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
```

Notes:
- The `for try await` loop drives the stream. Throws propagate to the
  catch.
- `metadata == nil` during chunking signals "still streaming" — the
  ResponseView's caption is hidden during this phase (existing
  `if let metadata` gate works as-is).
- `accumulated` is used as a fallback for `lastResponse` when the
  server's `done` event reports empty content (some servers do this).

## Acceptance Criteria

1. `swift build` succeeds with zero new warnings.
2. Drag-select text → click 설명 → ResponsePanel shows progressive
   text appearing token-by-token. No flicker. No stale text after
   completion.
3. The metadata caption (`model: ... · tokens: ...`) appears only
   AFTER the stream completes (the final `.done` event triggers
   `update(state: .success(text, metadata))`).
4. Click another action while a response is still streaming → the
   previous stream cancels immediately (no further token updates),
   the new stream's loading state appears, the new response
   streams.
5. Click outside while streaming → respects the existing loading
   guard (does NOT dismiss). After completion the outside-click
   dismiss resumes.
6. ESC during stream → cancels the stream cleanly; no "canceled"
   text leaks to the UI.
7. Network failure (Ollama not running) → `.failure(...)` state
   surfaces immediately, no partial accumulated text.
8. The existing non-streaming `OllamaClient.chat(...)` method is
   STILL present (no removal). It is no longer called from
   `PopupController.handleAction` but other consumers (e.g. future
   tests) can use it.
9. The Markdown rendering in `ResponseView` keeps working for the
   final response. Intermediate chunks may render with partial
   Markdown (e.g. open `**`) — this is acceptable.
10. Word/sentence mode translate still works via the standard
    `resolvePrompt` path.

## macOS edge-case checklist (Appendix C)

- [ ] Permissions: no new permissions.
- [ ] Permission revoked at runtime: no new path.
- [ ] Key window: no change.
- [ ] Z-order: no change.
- [ ] Animation anchor: no change (Markdown text grows; ResponsePanel
      already re-frames downward via its top-anchor logic).
- [ ] Mouse / key event routing: no change.
- [ ] Cancellation: dual-layered — Task cancellation cascades to the
      inner URLSession via `AsyncThrowingStream.onTermination`. Both
      `CancellationError` and `URLError(.cancelled)` silent.
- [ ] Resource cleanup: URLSession bytes connection closes when the
      Task ends (Task cancellation or natural completion).
- [ ] UserDefaults schema: no change.

## Out of Scope

- A "stop generating" button in the ResponsePanel — Phase 16.x
  follow-up. v1 cancellation goes through ESC / outside-click /
  next-action click.
- Streaming for image payloads — the current implementation streams
  the same way regardless of payload kind.
- Word-by-word animation (e.g. fade-in). The text simply appends.
- Per-chunk Markdown re-render optimization (if perf becomes an
  issue, throttle to N updates/sec).
- Removing the non-streaming `chat(...)` method.
- Telemetry on time-to-first-chunk.
