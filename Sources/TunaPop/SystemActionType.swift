import Foundation

enum SystemActionType: String, Codable, CaseIterable, Identifiable {
    case copy
    case paste
    case webSearch
    case lookUp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .copy: return "복사"
        case .paste: return "붙여넣기"
        case .webSearch: return "웹 검색"
        case .lookUp: return "사전 조회"
        }
    }

    var defaultLabel: String { displayName }

    var defaultSystemImage: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .paste: return "doc.on.clipboard"
        case .webSearch: return "magnifyingglass"
        case .lookUp: return "character.book.closed"
        }
    }
}
