import Foundation

enum LLMStreamEvent: Sendable {
    case chunk(String)
    case done(LLMChatResult)
}

struct LLMChatResult: Equatable, Sendable {
    let content: String
    let model: String
    let promptTokens: Int
    let completionTokens: Int
}

enum LLMClientError: LocalizedError, Sendable {
    case invalidEndpoint
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Invalid endpoint."
        case .requestFailed(let m): return m
        }
    }
}

protocol LLMClient: Sendable {
    var provider: AgentProvider { get }

    func listModels() async throws -> [String]

    func chatStream(
        model: String,
        prompt: String,
        payload: SelectionPayload,
        includeSelectionContext: Bool,
        systemPrompt: String?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error>
}
