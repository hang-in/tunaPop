import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var endpoint: String {
        didSet { UserDefaults.standard.set(endpoint, forKey: Self.endpointKey) }
    }

    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Self.modelKey) }
    }

    @Published var apiToken: String {
        didSet {
            try? KeychainHelper.set(apiToken, forAccount: Self.tokenAccount)
        }
    }

    @Published var defaultPrompt: String {
        didSet { UserDefaults.standard.set(defaultPrompt, forKey: Self.defaultPromptKey) }
    }

    @Published var actionBarPosition: ActionBarPosition {
        didSet { UserDefaults.standard.set(actionBarPosition.rawValue, forKey: Self.actionBarPositionKey) }
    }

    @Published var customActions: [Action] {
        didSet { persistCustomActions() }
    }

    @Published var agentProvider: AgentProvider {
        didSet { UserDefaults.standard.set(agentProvider.rawValue, forKey: Self.agentProviderKey) }
    }

    @Published var responseLanguage: ResponseLanguage {
        didSet { UserDefaults.standard.set(responseLanguage.rawValue, forKey: Self.responseLanguageKey) }
    }

    @Published var builtinOverrides: [String: Action] {
        didSet { persistBuiltinOverrides() }
    }

    @Published var hiddenBuiltinIds: Set<String> {
        didSet { persistHiddenBuiltinIds() }
    }

    private static let endpointKey = "endpoint"
    private static let modelKey = "model"
    private static let tokenAccount = "ollama"
    private static let legacyApiTokenKey = "apiToken"
    private static let defaultPromptKey = "defaultPrompt"
    private static let actionBarPositionKey = "actionBarPosition"
    private static let customActionsKey = "customActions"
    private static let agentProviderKey = "agentProvider"
    private static let responseLanguageKey = "responseLanguage"
    private static let builtinOverridesKey = "builtinOverrides"
    private static let hiddenBuiltinIdsKey = "hiddenBuiltinIds"

    private func persistCustomActions() {
        if let data = try? JSONEncoder().encode(customActions) {
            UserDefaults.standard.set(data, forKey: Self.customActionsKey)
        }
    }

    private func persistBuiltinOverrides() {
        if let data = try? JSONEncoder().encode(builtinOverrides) {
            UserDefaults.standard.set(data, forKey: Self.builtinOverridesKey)
        }
    }

    private func persistHiddenBuiltinIds() {
        let array = Array(hiddenBuiltinIds)
        if let data = try? JSONEncoder().encode(array) {
            UserDefaults.standard.set(data, forKey: Self.hiddenBuiltinIdsKey)
        }
    }

    func resolvedBuiltin(_ original: Action) -> Action {
        builtinOverrides[original.id] ?? original
    }

    func resetBuiltin(_ id: String) {
        builtinOverrides.removeValue(forKey: id)
        hiddenBuiltinIds.remove(id)
    }

    func isHidden(_ id: String) -> Bool {
        hiddenBuiltinIds.contains(id)
    }

    init() {
        endpoint = UserDefaults.standard.string(forKey: Self.endpointKey) ?? "http://localhost:11434"
        model = UserDefaults.standard.string(forKey: Self.modelKey) ?? ""
        let migrated: String? = {
            if let legacy = UserDefaults.standard.string(forKey: Self.legacyApiTokenKey),
               !legacy.isEmpty {
                try? KeychainHelper.set(legacy, forAccount: Self.tokenAccount)
                UserDefaults.standard.removeObject(forKey: Self.legacyApiTokenKey)
                return legacy
            }
            return nil
        }()
        apiToken = migrated ?? KeychainHelper.get(forAccount: Self.tokenAccount) ?? ""
        defaultPrompt = UserDefaults.standard.string(forKey: Self.defaultPromptKey) ?? "Explain this selection clearly and concisely."
        let positionRaw = UserDefaults.standard.string(forKey: Self.actionBarPositionKey)
        actionBarPosition = positionRaw.flatMap(ActionBarPosition.init(rawValue:)) ?? .topRight

        if let data = UserDefaults.standard.data(forKey: Self.customActionsKey),
           let decoded = try? JSONDecoder().decode([Action].self, from: data) {
            customActions = decoded
        } else {
            customActions = []
        }

        let providerRaw = UserDefaults.standard.string(forKey: Self.agentProviderKey)
        agentProvider = providerRaw.flatMap(AgentProvider.init(rawValue:)) ?? .ollama

        let languageRaw = UserDefaults.standard.string(forKey: Self.responseLanguageKey)
        responseLanguage = languageRaw.flatMap(ResponseLanguage.init(rawValue:)) ?? .auto

        if let data = UserDefaults.standard.data(forKey: Self.builtinOverridesKey),
           let decoded = try? JSONDecoder().decode([String: Action].self, from: data) {
            builtinOverrides = decoded
        } else {
            builtinOverrides = [:]
        }

        if let data = UserDefaults.standard.data(forKey: Self.hiddenBuiltinIdsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            hiddenBuiltinIds = Set(decoded)
        } else {
            hiddenBuiltinIds = []
        }
    }
}
