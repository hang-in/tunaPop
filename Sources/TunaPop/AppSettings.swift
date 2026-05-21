import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Self.modelKey) }
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
        didSet {
            UserDefaults.standard.set(agentProvider.rawValue, forKey: Self.agentProviderKey)
            apiTokenForActiveProvider = KeychainHelper.get(forAccount: agentProvider.keychainAccount) ?? ""
        }
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

    @Published var verboseLogging: Bool {
        didSet {
            UserDefaults.standard.set(verboseLogging, forKey: Self.verboseLoggingKey)
            Log.setVerbose(verboseLogging)
        }
    }

    @Published var endpoints: [AgentProvider: String] {
        didSet { persistEndpoints() }
    }

    @Published var apiTokenForActiveProvider: String {
        didSet {
            try? KeychainHelper.set(apiTokenForActiveProvider, forAccount: agentProvider.keychainAccount)
        }
    }

    var endpoint: String {
        get { endpoints[agentProvider] ?? agentProvider.defaultEndpoint }
        set {
            endpoints[agentProvider] = newValue
        }
    }

    var apiToken: String {
        get { apiTokenForActiveProvider }
        set { apiTokenForActiveProvider = newValue }
    }

    private static let modelKey = "model"
    private static let legacyApiTokenKey = "apiToken"
    private static let defaultPromptKey = "defaultPrompt"
    private static let actionBarPositionKey = "actionBarPosition"
    private static let customActionsKey = "customActions"
    private static let agentProviderKey = "agentProvider"
    private static let responseLanguageKey = "responseLanguage"
    private static let builtinOverridesKey = "builtinOverrides"
    private static let hiddenBuiltinIdsKey = "hiddenBuiltinIds"
    private static let verboseLoggingKey = "verboseLogging"
    private static let endpointsKey = "endpointsPerProvider"

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

    private func persistEndpoints() {
        if let data = try? JSONEncoder().encode(endpoints) {
            UserDefaults.standard.set(data, forKey: Self.endpointsKey)
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
        // 1. Gather all raw parameters locally to avoid referencing self before fully initialized
        let providerRaw = UserDefaults.standard.string(forKey: Self.agentProviderKey)
        let loadedProvider = providerRaw.flatMap(AgentProvider.init(rawValue:)) ?? .ollama

        let loadedModel = UserDefaults.standard.string(forKey: Self.modelKey) ?? ""

        // Legacy apiToken migration
        if let legacy = UserDefaults.standard.string(forKey: Self.legacyApiTokenKey), !legacy.isEmpty {
            try? KeychainHelper.set(legacy, forAccount: "ollama")
            UserDefaults.standard.removeObject(forKey: Self.legacyApiTokenKey)
        }

        // Load endpoints
        var loadedEndpoints: [AgentProvider: String] = [:]
        if let data = UserDefaults.standard.data(forKey: Self.endpointsKey),
           let decoded = try? JSONDecoder().decode([AgentProvider: String].self, from: data) {
            loadedEndpoints = decoded
        }

        // Legacy endpoint migration
        if let legacyEndpoint = UserDefaults.standard.string(forKey: "endpoint") {
            loadedEndpoints[.ollama] = legacyEndpoint
            UserDefaults.standard.removeObject(forKey: "endpoint")
            if let data = try? JSONEncoder().encode(loadedEndpoints) {
                UserDefaults.standard.set(data, forKey: Self.endpointsKey)
            }
        }

        // Load active apiToken
        let loadedApiToken = KeychainHelper.get(forAccount: loadedProvider.keychainAccount) ?? ""

        let loadedDefaultPrompt = UserDefaults.standard.string(forKey: Self.defaultPromptKey) ?? "Explain this selection clearly and concisely in {language}."
        let positionRaw = UserDefaults.standard.string(forKey: Self.actionBarPositionKey)
        let loadedActionBarPosition = positionRaw.flatMap(ActionBarPosition.init(rawValue:)) ?? .topRight

        var loadedCustomActions: [Action] = []
        if let data = UserDefaults.standard.data(forKey: Self.customActionsKey),
           let decoded = try? JSONDecoder().decode([Action].self, from: data) {
            loadedCustomActions = decoded
        }

        let languageRaw = UserDefaults.standard.string(forKey: Self.responseLanguageKey)
        let loadedResponseLanguage = languageRaw.flatMap(ResponseLanguage.init(rawValue:)) ?? .auto

        var loadedBuiltinOverrides: [String: Action] = [:]
        if let data = UserDefaults.standard.data(forKey: Self.builtinOverridesKey),
           let decoded = try? JSONDecoder().decode([String: Action].self, from: data) {
            loadedBuiltinOverrides = decoded
        }

        var loadedHiddenBuiltinIds: Set<String> = []
        if let data = UserDefaults.standard.data(forKey: Self.hiddenBuiltinIdsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            loadedHiddenBuiltinIds = Set(decoded)
        }

        let loadedVerboseLogging = UserDefaults.standard.bool(forKey: Self.verboseLoggingKey)

        // 2. Initialize all stored properties
        self.model = loadedModel
        self.defaultPrompt = loadedDefaultPrompt
        self.actionBarPosition = loadedActionBarPosition
        self.customActions = loadedCustomActions
        self.agentProvider = loadedProvider
        self.responseLanguage = loadedResponseLanguage
        self.builtinOverrides = loadedBuiltinOverrides
        self.hiddenBuiltinIds = loadedHiddenBuiltinIds
        self.verboseLogging = loadedVerboseLogging
        self.endpoints = loadedEndpoints
        self.apiTokenForActiveProvider = loadedApiToken

        // 3. Post-initialization side effects
        Log.setVerbose(loadedVerboseLogging)
    }
}
