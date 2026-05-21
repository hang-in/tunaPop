import Foundation

enum AgentProvider: String, CaseIterable, Codable, Identifiable {
    case ollama
    case lmStudio
    case openai
    case anthropic
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama:    return "Ollama"
        case .lmStudio:  return "LM Studio"
        case .openai:    return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini:    return "Gemini"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .ollama:    return "http://localhost:11434"
        case .lmStudio:  return "http://localhost:1234/v1"
        case .openai:    return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini:    return "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    var keychainAccount: String { rawValue }

    var requiresAPIKey: Bool {
        switch self {
        case .ollama, .lmStudio: return false
        case .openai, .anthropic, .gemini: return true
        }
    }
}
