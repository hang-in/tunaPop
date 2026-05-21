import Foundation

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case ai
    case system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ai: return "AI 액션"
        case .system: return "기본 기능"
        }
    }
}
