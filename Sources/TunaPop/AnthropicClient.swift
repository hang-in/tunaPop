import Foundation

struct AnthropicClient: LLMClient {
    var provider: AgentProvider { .anthropic }
    var endpoint: String
    var token: String

    func listModels() async throws -> [String] {
        return ["claude-opus-4-7", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]
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
                    guard let baseURL = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                        throw LLMClientError.invalidEndpoint
                    }

                    let url = baseURL.appending(path: "messages")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                    let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanToken.isEmpty {
                        request.setValue(cleanToken, forHTTPHeaderField: "x-api-key")
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

                    let body = AnthropicChatRequest(
                        model: model,
                        maxTokens: 4096,
                        system: systemPrompt,
                        messages: [AnthropicMessage(role: "user", content: userContent)],
                        stream: true
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMClientError.requestFailed("Invalid response")
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw LLMClientError.requestFailed("Streaming request failed with status \(httpResponse.statusCode)")
                    }

                    var promptTokens = 0
                    var completionTokens = 0
                    var accumulated = ""
                    var finalModel = model
                    var isFinished = false

                    let sseStream = SSEStreamParser.parse(bytes.lines)
                    for try await event in sseStream {
                        try Task.checkCancellation()
                        guard let data = event.data.data(using: .utf8) else { continue }
                        let eventName = event.name ?? ""

                        switch eventName {
                        case "message_start":
                            if let start = try? JSONDecoder().decode(AnthropicMessageStart.self, from: data) {
                                if let m = start.message.model {
                                    finalModel = m
                                }
                                if let input = start.message.usage?.inputTokens {
                                    promptTokens = input
                                }
                            }
                        case "content_block_delta":
                            if let delta = try? JSONDecoder().decode(AnthropicContentBlockDelta.self, from: data),
                               delta.delta.type == "text_delta",
                               let text = delta.delta.text, !text.isEmpty {
                                accumulated += text
                                continuation.yield(.chunk(text))
                            }
                        case "message_delta":
                            if let delta = try? JSONDecoder().decode(AnthropicMessageDelta.self, from: data),
                               let output = delta.usage?.outputTokens {
                                completionTokens = output
                            }
                        case "message_stop":
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
                        default:
                            break
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
                    Log.network.error("Anthropic stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private struct AnthropicChatRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [AnthropicMessage]
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case stream
    }
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
}

private struct AnthropicMessageStart: Decodable {
    struct Message: Decodable {
        let model: String?
        let usage: Usage?
    }
    struct Usage: Decodable {
        let inputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
        }
    }
    let message: Message
}

private struct AnthropicContentBlockDelta: Decodable {
    struct Delta: Decodable {
        let type: String
        let text: String?
    }
    let delta: Delta
}

private struct AnthropicMessageDelta: Decodable {
    struct Usage: Decodable {
        let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case outputTokens = "output_tokens"
        }
    }
    let usage: Usage?
}
