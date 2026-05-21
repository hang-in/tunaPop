import Foundation

struct Action: Identifiable, Equatable, Codable {
    let id: String
    let label: String
    let prompt: String
    let systemImage: String
    let kind: ActionKind
    let systemType: SystemActionType?

    init(
        id: String,
        label: String,
        prompt: String,
        systemImage: String,
        kind: ActionKind = .ai,
        systemType: SystemActionType? = nil
    ) {
        self.id = id
        self.label = label
        self.prompt = prompt
        self.systemImage = systemImage
        self.kind = kind
        self.systemType = systemType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        prompt = try c.decode(String.self, forKey: .prompt)
        systemImage = try c.decode(String.self, forKey: .systemImage)
        kind = try c.decodeIfPresent(ActionKind.self, forKey: .kind) ?? .ai
        systemType = try c.decodeIfPresent(SystemActionType.self, forKey: .systemType)
    }
}

extension Action {
    static let defaults: [Action] = [
        Action(id: "explain",   label: "설명", prompt: "Explain the selected text clearly and concisely. If the selection is code, explain its purpose, key logic, and structure using markdown code blocks. Respond in {language}. Do not include conversational filler like 'Sure, here is...' or introductory remarks.",            systemImage: "text.bubble"),
        Action(id: "summarize", label: "요약", prompt: "Summarize the selected text into exactly 3 clear, informative bullet points. Focus on extracting the core argument and key takeaways. Respond in {language} using a clean markdown list. Do not output anything other than the summary.",                systemImage: "list.bullet.rectangle"),
        Action(id: "translate", label: "번역", prompt: "Translate this selection. Keep meaning and tone.", systemImage: "character.bubble"),
        Action(id: "proofread", label: "다듬기", prompt: "Proofread the selected text and improve its grammar, flow, and clarity. Respond in {language}.", systemImage: "sparkles"),
        Action(id: "alternatives", label: "대체 표현", prompt: "Provide 3 alternative ways to express the selected text in {language}. Keep the original meaning.", systemImage: "arrow.triangle.2.circlepath"),
        Action(id: "customInput", label: "직접 입력", prompt: "", systemImage: "pencil.line"),
    ]

    static let systemDefaults: [Action] = [
        Action(
            id: "system.copy",
            label: SystemActionType.copy.defaultLabel,
            prompt: "",
            systemImage: SystemActionType.copy.defaultSystemImage,
            kind: .system,
            systemType: .copy
        ),
        Action(
            id: "system.paste",
            label: SystemActionType.paste.defaultLabel,
            prompt: "",
            systemImage: SystemActionType.paste.defaultSystemImage,
            kind: .system,
            systemType: .paste
        ),
        Action(
            id: "system.webSearch",
            label: SystemActionType.webSearch.defaultLabel,
            prompt: "",
            systemImage: SystemActionType.webSearch.defaultSystemImage,
            kind: .system,
            systemType: .webSearch
        ),
        Action(
            id: "system.lookUp",
            label: SystemActionType.lookUp.defaultLabel,
            prompt: "",
            systemImage: SystemActionType.lookUp.defaultSystemImage,
            kind: .system,
            systemType: .lookUp
        ),
    ]

    static var allBuiltins: [Action] { defaults + systemDefaults }
}
