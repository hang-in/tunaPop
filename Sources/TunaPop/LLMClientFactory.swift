import Foundation

@MainActor
enum LLMClientFactory {
    static func make(for settings: AppSettings) -> LLMClient {
        let endpoint = settings.endpoint
        let token = settings.apiToken
        switch settings.agentProvider {
        case .ollama:
            return OllamaClient(endpoint: endpoint, token: token)
        case .lmStudio:
            return OpenAIClient(
                provider: .lmStudio,
                endpoint: endpoint,
                token: token
            )
        case .openai:
            return OpenAIClient(
                provider: .openai,
                endpoint: endpoint,
                token: token
            )
        case .anthropic:
            return AnthropicClient(endpoint: endpoint, token: token)
        case .gemini:
            return GeminiClient(endpoint: endpoint, token: token)
        }
    }
}
