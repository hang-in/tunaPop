import Foundation

struct Action: Identifiable, Equatable {
    let id: String
    let label: String
    let prompt: String
    let systemImage: String
}

extension Action {
    static let defaults: [Action] = [
        Action(id: "explain",   label: "설명", prompt: "Explain this selection clearly and concisely.",            systemImage: "text.alignleft"),
        Action(id: "summarize", label: "요약", prompt: "Summarize this selection in three bullets.",                systemImage: "list.bullet"),
        Action(id: "translate", label: "번역", prompt: "Translate this selection into Korean. Keep meaning and tone.", systemImage: "globe"),
    ]
}
