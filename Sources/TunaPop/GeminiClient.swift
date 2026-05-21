import Foundation

struct GeminiClient: LLMClient {
    var provider: AgentProvider { .gemini }
    var endpoint: String
    var token: String

    func listModels() async throws -> [String] {
        guard var components = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw LLMClientError.invalidEndpoint
        }
        
        components.path = (components.path as NSString).appendingPathComponent("models")
        components.queryItems = [
            URLQueryItem(name: "key", value: token.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
        
        guard let url = components.url else {
            throw LLMClientError.invalidEndpoint
        }

        // Log only path, no query token
        Log.network.info("Gemini listModels requested for path: \(url.path, privacy: .public)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError.requestFailed("Invalid response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed"
            Log.network.error("Gemini listModels failed with status \(httpResponse.statusCode) for path \(url.path, privacy: .public)")
            throw LLMClientError.requestFailed(message)
        }

        let responseObj = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
        let filtered = responseObj.models.filter { entry in
            entry.supportedGenerationMethods?.contains("generateContent") ?? false
        }
        return filtered.map { $0.name }
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
                    guard var components = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                        throw LLMClientError.invalidEndpoint
                    }
                    
                    let cleanModel = model.hasPrefix("models/") ? model : "models/\(model)"
                    components.path = (components.path as NSString).appendingPathComponent("\(cleanModel):streamGenerateContent")
                    components.queryItems = [
                        URLQueryItem(name: "alt", value: "sse"),
                        URLQueryItem(name: "key", value: token.trimmingCharacters(in: .whitespacesAndNewlines))
                    ]
                    
                    guard let url = components.url else {
                        throw LLMClientError.invalidEndpoint
                    }

                    // Log only path to avoid leaking key
                    if Log.isVerbose {
                        Log.network.debug("Gemini chatStream starting for path: \(url.path, privacy: .public)")
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

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

                    let contents = [
                        GeminiContent(
                            parts: [GeminiPart(text: userContent)],
                            role: "user"
                        )
                    ]
                    
                    let systemInstruction: GeminiSystemInstruction?
                    if let systemPrompt, !systemPrompt.isEmpty {
                        systemInstruction = GeminiSystemInstruction(parts: [GeminiPart(text: systemPrompt)])
                    } else {
                        systemInstruction = nil
                    }

                    let body = GeminiChatRequest(contents: contents, systemInstruction: systemInstruction)
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMClientError.requestFailed("Invalid response")
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw LLMClientError.requestFailed("Streaming request failed with status \(httpResponse.statusCode) on path \(url.path)")
                    }

                    var accumulated = ""
                    var promptTokens = 0
                    var completionTokens = 0
                    var isFinished = false

                    let sseStream = SSEStreamParser.parse(bytes.lines)
                    for try await event in sseStream {
                        try Task.checkCancellation()
                        guard let data = event.data.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(GeminiStreamChunk.self, from: data) else {
                            continue
                        }

                        if let usage = chunk.usageMetadata {
                            promptTokens = usage.promptTokenCount ?? promptTokens
                            completionTokens = usage.candidatesTokenCount ?? completionTokens
                        }

                        var candidateFinished = false
                        if let candidates = chunk.candidates, !candidates.isEmpty {
                            for candidate in candidates {
                                if let parts = candidate.content?.parts {
                                    for part in parts {
                                        if let text = part.text, !text.isEmpty {
                                            accumulated += text
                                            continuation.yield(.chunk(text))
                                        }
                                    }
                                }
                                if candidate.finishReason == "STOP" {
                                    candidateFinished = true
                                }
                            }
                        }

                        if candidateFinished && !isFinished {
                            let result = LLMChatResult(
                                content: accumulated,
                                model: model,
                                promptTokens: promptTokens,
                                completionTokens: completionTokens
                            )
                            continuation.yield(.done(result))
                            isFinished = true
                            continuation.finish()
                            return
                        }
                    }

                    if !isFinished {
                        let result = LLMChatResult(
                            content: accumulated,
                            model: model,
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
                    Log.network.error("Gemini stream error on path \(endpoint): \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private struct GeminiModelsResponse: Decodable {
    let models: [GeminiModelEntry]
}

private struct GeminiModelEntry: Decodable {
    let name: String
    let supportedGenerationMethods: [String]?
}

private struct GeminiChatRequest: Encodable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiSystemInstruction?
}

private struct GeminiContent: Encodable {
    let parts: [GeminiPart]
    let role: String
}

private struct GeminiPart: Encodable {
    let text: String
}

private struct GeminiSystemInstruction: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiStreamChunk: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
            }
            let parts: [Part]?
        }
        let content: Content?
        let finishReason: String?
    }
    struct UsageMetadata: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
    }
    let candidates: [Candidate]?
    let usageMetadata: UsageMetadata?
}
