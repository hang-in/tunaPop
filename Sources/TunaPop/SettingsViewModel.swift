import SwiftUI
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    let settings: AppSettings

    @Published var fetchedModels: [String] = []
    @Published var lastFetched: Date?
    @Published var isFetching = false
    @Published var fetchError: String?
    @Published var customModelEntry: String = ""

    // 임시 UI 편집 상태
    @Published var isEditing = false
    @Published var editingAction: Action = Action(id: "", label: "", prompt: "", systemImage: "text.bubble")
    @Published var editingIndex: Int? = nil
    @Published var editingBuiltinId: String? = nil

    @Published var isAccessibilityTrusted = Accessibility.isTrusted

    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings
        self.customModelEntry = settings.model
        self.isAccessibilityTrusted = Accessibility.isTrusted

        settings.$model
            .sink { [weak self] newModel in
                guard let self else { return }
                if self.showsCustomModelField(for: newModel) {
                    self.customModelEntry = newModel
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.isAccessibilityTrusted = Accessibility.isTrusted
            }
            .store(in: &cancellables)
    }

    var showsCustomModelField: Bool {
        showsCustomModelField(for: settings.model)
    }

    private func showsCustomModelField(for model: String) -> Bool {
        model.isEmpty || !fetchedModels.contains(model)
    }

    func refreshModels() async {
        guard !isFetching else { return }
        isFetching = true
        fetchError = nil
        defer { isFetching = false }
        do {
            let client = LLMClientFactory.make(for: settings)
            fetchedModels = try await client.listModels()
            lastFetched = Date()
            
            if showsCustomModelField {
                customModelEntry = settings.model
            }
        } catch is CancellationError {
            // silent
        } catch let urlError as URLError where urlError.code == .cancelled {
            // silent
        } catch {
            fetchError = error.localizedDescription
        }
    }

    func updateCustomModel(_ newValue: String) {
        settings.model = newValue
    }

    func isLocalEndpoint(_ raw: String) -> Bool {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host else {
            return true
        }
        let lower = host.lowercased()
        return lower == "localhost" || lower == "127.0.0.1" || lower == "::1"
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            ?? URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        NSWorkspace.shared.open(url)
    }

    func startEditingNewAction() {
        editingAction = Action(
            id: UUID().uuidString,
            label: "",
            prompt: "",
            systemImage: "text.bubble"
        )
        editingIndex = nil
        editingBuiltinId = nil
        isEditing = true
    }

    func startEditingBuiltin(action: Action, originalId: String) {
        editingAction = action
        editingIndex = nil
        editingBuiltinId = originalId
        isEditing = true
    }

    func startEditingCustom(action: Action) {
        editingAction = action
        editingIndex = settings.customActions.firstIndex(where: { $0.id == action.id })
        editingBuiltinId = nil
        isEditing = true
    }

    func commitEditing() {
        if let bid = editingBuiltinId {
            settings.builtinOverrides[bid] = editingAction
        } else if let idx = editingIndex {
            settings.customActions[idx] = editingAction
        } else {
            settings.customActions.append(editingAction)
        }
        isEditing = false
        editingIndex = nil
        editingBuiltinId = nil
    }

    func cancelEditing() {
        isEditing = false
        editingIndex = nil
        editingBuiltinId = nil
    }

    func usedSymbols(excludingId: String) -> Set<String> {
        var symbols: Set<String> = []
        for action in Action.allBuiltins {
            let resolved = settings.resolvedBuiltin(action)
            if resolved.id == excludingId { continue }
            symbols.insert(resolved.systemImage)
        }
        for action in settings.customActions {
            if action.id == excludingId { continue }
            symbols.insert(action.systemImage)
        }
        return symbols
    }

    func moveUp(action: Action) {
        guard let index = settings.customActions.firstIndex(where: { $0.id == action.id }), index > 0 else { return }
        settings.customActions.swapAt(index, index - 1)
    }

    func moveDown(action: Action) {
        guard let index = settings.customActions.firstIndex(where: { $0.id == action.id }), index < settings.customActions.count - 1 else { return }
        settings.customActions.swapAt(index, index + 1)
    }

    func deleteCustomAction(_ action: Action) {
        settings.customActions.removeAll(where: { $0.id == action.id })
    }
}
