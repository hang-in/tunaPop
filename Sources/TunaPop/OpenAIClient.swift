import Foundation

struct OpenAIClient: LLMClient {
    var provider: AgentProvider
    var endpoint: String
    var token: String

    private func resolvedBaseURL() -> URL? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        if normalized.hasSuffix("/v1") {
            return URL(string: normalized)
        }
        return URL(string: normalized + "/v1")
    }

    func listModels() async throws -> [String] {
        guard let baseURL = resolvedBaseURL() else {
            throw LLMClientError.invalidEndpoint
        }

        let url = baseURL.appending(path: "models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanToken.isEmpty {
            request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError.requestFailed("Invalid response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed"
            Log.network.error("OpenAI listModels failed with status \(httpResponse.statusCode): \(message)")
            throw LLMClientError.requestFailed(message)
        }

        let responseObj = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return responseObj.data.map { $0.id }
    }

    func chatStream(
        model: String,
        prompt: String,
        payload: SelectionPayload,
        includeSelectionContext: Bool,
        systemPrompt: String?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let baseURL = resolvedBaseURL() else {
                        throw LLMClientError.invalidEndpoint
                    }

                    let url = baseURL.appending(path: "chat/completions")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanToken.isEmpty {
                        request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
                    }

                    let userContent: String
                    switch payload {
                    case .text(let text):
                        if includeSelectionContext {
                            userContent = "\(prompt)\n\nSelection:\n\(text)"
                        } else {
                            userContent = prompt
                        }
                    case .image:
                        userContent = prompt
                    }

                    var messages: [OpenAIMessage] = []
                    if let systemPrompt, !systemPrompt.isEmpty {
                        messages.append(OpenAIMessage(role: "system", content: systemPrompt))
                    }
                    messages.append(OpenAIMessage(role: "user", content: userContent))

                    // include_usage in stream_options is only supported for OpenAI. Let's include it for LM Studio too, but some local servers might reject it.
                    // Usually LM Studio handles stream_options or ignores it. 
                    let streamOptions = OpenAIStreamOptions(includeUsage: true)
                    let body = OpenAIChatRequest(
                        model: model,
                        messages: messages,
                        stream: true,
                        streamOptions: streamOptions
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMClientError.requestFailed("Invalid response")
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw LLMClientError.requestFailed("Streaming request failed with status \(httpResponse.statusCode)")
                    }

                    var accumulated = ""
                    var finalModel = model
                    var isFinished = false
                    var promptTokens = 0
                    var completionTokens = 0

                    let sseStream = SSEStreamParser.parse(bytes.lines)
                    for try await event in sseStream {
                        try Task.checkCancellation()
                        if event.data == "[DONE]" {
                            if !isFinished {
                                let result = LLMChatResult(
                                    content: accumulated,
                                    model: finalModel,
                                    promptTokens: promptTokens,
                                    completionTokens: completionTokens
                                )
                                continuation.yield(.done(result))
                                isFinished = true
                            }
                            continuation.finish()
                            return
                        }

                        guard let data = event.data.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data) else {
                            continue
                        }

                        if let modelName = chunk.model {
                            finalModel = modelName
                        }

                        if let usage = chunk.usage {
                            promptTokens = usage.promptTokens
                            completionTokens = usage.completionTokens
                        }

                        if let choices = chunk.choices, !choices.isEmpty {
                            for choice in choices {
                                if let text = choice.delta.content, !text.isEmpty {
                                    accumulated += text
                                    continuation.yield(.chunk(text))
                                }
                                if choice.finishReason != nil {
                                    // finish reason present, but wait for DONE or usage if possible
                                }
                            }
                        }
                    }

                    if !isFinished {
                        let result = LLMChatResult(
                            content: accumulated,
                            model: finalModel,
                            promptTokens: promptTokens,
                            completionTokens: completionTokens
                        )
                        continuation.yield(.done(result))
                    }
                    continuation.finish()

                } catch is CancellationError {
                    continuation.finish()
                } catch let urlError as URLError where urlError.code == .cancelled {
                    continuation.finish()
                } catch {
                    Log.network.error("OpenAI stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private struct OpenAIModelsResponse: Decodable {
    let data: [OpenAIModelEntry]
}

private struct OpenAIModelEntry: Decodable {
    let id: String
}

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let stream: Bool
    let streamOptions: OpenAIStreamOptions?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case streamOptions = "stream_options"
    }
}

private struct OpenAIMessage: Encodable {
    let role: String
    let content: String
}

private struct OpenAIStreamOptions: Encodable {
    let includeUsage: Bool

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

private struct OpenAIStreamChunk: Decodable {
    let model: String?
    let choices: [OpenAIChoice]?
    let usage: OpenAIUsage?
}

private struct OpenAIChoice: Decodable {
    let delta: OpenAIDelta
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

private struct OpenAIDelta: Decodable {
    let content: String?
}

private struct OpenAIUsage: Decodable {
    let promptTokens: Int
    let completionTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
    }
}
