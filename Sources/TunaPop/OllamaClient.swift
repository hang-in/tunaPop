import Foundation

struct OllamaClient {
    var endpoint: String
    var token: String

    func chat(model: String, prompt: String, payload: SelectionPayload) async throws -> OllamaChatResult {
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
            userMessage = OllamaMessage(role: "user", content: "\(prompt)\n\nSelection:\n\(text)", images: nil)
        case .image:
            userMessage = OllamaMessage(role: "user", content: prompt, images: payload.imageBase64PNG.map { [$0] })
        }

        let body = OllamaChatRequest(model: model, messages: [userMessage], stream: false)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed"
            throw OllamaError.requestFailed(message)
        }

        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        return OllamaChatResult(
            content: decoded.message.content,
            model: decoded.model ?? model,
            evalCount: decoded.evalCount ?? 0,
            promptEvalCount: decoded.promptEvalCount ?? 0
        )
    }

    func listModels() async throws -> [String] {
        guard let baseURL = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw OllamaError.invalidEndpoint
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
            throw OllamaError.requestFailed(message)
        }

        let responseObj = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return responseObj.models.map { $0.name }
    }
}

struct OllamaChatResult: Equatable, Sendable {
    let content: String
    let model: String
    let evalCount: Int
    let promptEvalCount: Int
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

enum OllamaError: LocalizedError {
    case invalidEndpoint
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid Ollama endpoint."
        case .requestFailed(let message):
            return message
        }
    }
}
