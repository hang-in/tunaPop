import Foundation

struct OllamaClient: LLMClient {
    var provider: AgentProvider { .ollama }
    var endpoint: String
    var token: String

    func chat(
        model: String,
        prompt: String,
        payload: SelectionPayload,
        includeSelectionContext: Bool = true,
        systemPrompt: String? = nil
    ) async throws -> LLMChatResult {
        guard let baseURL = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw LLMClientError.invalidEndpoint
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

        let body = OllamaChatRequest(model: model, messages: messages, stream: false)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed"
            throw LLMClientError.requestFailed(message)
        }

        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        return LLMChatResult(
            content: decoded.message.content,
            model: decoded.model ?? model,
            promptTokens: decoded.promptEvalCount ?? 0,
            completionTokens: decoded.evalCount ?? 0
        )
    }

    func chatStream(
        model: String,
        prompt: String,
        payload: SelectionPayload,
        includeSelectionContext: Bool = true,
        systemPrompt: String? = nil
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let baseURL = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                        throw LLMClientError.invalidEndpoint
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
                        throw LLMClientError.requestFailed("Streaming request failed")
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
                            let result = LLMChatResult(
                                content: accumulated,
                                model: finalModel,
                                promptTokens: finalPromptEvalCount,
                                completionTokens: finalEvalCount
                            )
                            continuation.yield(.done(result))
                            continuation.finish()
                            return
                        }
                    }
                    let result = LLMChatResult(
                        content: accumulated,
                        model: finalModel,
                        promptTokens: finalPromptEvalCount,
                        completionTokens: finalEvalCount
                    )
                    continuation.yield(.done(result))
                    continuation.finish()
                } catch is CancellationError {
                    Log.network.info("Ollama stream cancelled (CancellationError)")
                    continuation.finish()
                } catch let urlError as URLError where urlError.code == .cancelled {
                    Log.network.info("Ollama stream cancelled (URLError.cancelled)")
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

    func listModels() async throws -> [String] {
        guard let baseURL = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw LLMClientError.invalidEndpoint
        }

        let url = baseURL.appending(path: "api/tags")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanToken.isEmpty {
            request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed"
            throw LLMClientError.requestFailed(message)
        }

        let responseObj = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return responseObj.models.map { $0.name }
    }
}

private struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
}

private struct OllamaMessage: Codable {
    let role: String
    let content: String
    let images: [String]?
}

private struct OllamaChatResponse: Decodable {
    let model: String?
    let message: OllamaMessage
    let promptEvalCount: Int?
    let evalCount: Int?

    private enum CodingKeys: String, CodingKey {
        case model
        case message
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }
}

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaTagEntry]
}

private struct OllamaTagEntry: Decodable {
    let name: String
}

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
