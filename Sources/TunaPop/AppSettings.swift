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

    private static let endpointKey = "endpoint"
    private static let modelKey = "model"
    private static let tokenAccount = "ollama"
    private static let legacyApiTokenKey = "apiToken"
    private static let defaultPromptKey = "defaultPrompt"
    private static let actionBarPositionKey = "actionBarPosition"

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
    }
}
