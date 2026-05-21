import Foundation

enum ResponseLanguage: String, CaseIterable, Codable, Identifiable {
    case auto
    case english
    case korean
    case japanese
    case chinese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "시스템 따름"
        case .english: return "English"
        case .korean: return "한국어"
        case .japanese: return "日本語"
        case .chinese: return "中文"
        }
    }

    var systemPromptName: String? {
        switch self {
        case .auto:
            return ResponseLanguage.fromSystemLocale().systemPromptName
        case .english: return "English"
        case .korean: return "Korean"
        case .japanese: return "Japanese"
        case .chinese: return "Chinese"
        }
    }

    static func fromSystemLocale() -> ResponseLanguage {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        switch code {
        case "ko": return .korean
        case "ja": return .japanese
        case "zh": return .chinese
        case "en": return .english
        default: return .english
        }
    }
}
