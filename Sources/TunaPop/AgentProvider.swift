import Foundation

enum AgentProvider: String, CaseIterable, Codable, Identifiable {
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        }
    }
}
