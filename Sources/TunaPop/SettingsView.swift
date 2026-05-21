import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    @State private var fetchedModels: [String] = []
    @State private var lastFetched: Date?
    @State private var isFetching = false
    @State private var fetchError: String?
    @State private var customModelEntry: String = ""

    @State private var permissionRefreshTick = Date()

    @State private var isEditing = false
    @State private var editingAction: Action = Action(id: "", label: "", prompt: "", systemImage: "text.bubble")
    @State private var editingIndex: Int? = nil
    @State private var editingBuiltinId: String? = nil

    private var showsCustomModelField: Bool {
        settings.model.isEmpty || !fetchedModels.contains(settings.model)
    }

    private var modelSelection: Binding<String> {
        Binding<String>(
            get: {
                if settings.model.isEmpty {
                    return ""
                }
                return settings.model
            },
            set: { newValue in
                if newValue.isEmpty {
                    settings.model = customModelEntry
                } else {
                    settings.model = newValue
                }
            }
        )
    }

    var body: some View {
        Form {
            Section("Agent") {
                Picker("Provider", selection: $settings.agentProvider) {
                    ForEach(AgentProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                TextField("Endpoint", text: $settings.endpoint)
                    .textFieldStyle(.roundedBorder)
                
                if !isLocalEndpoint(settings.endpoint) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("이 엔드포인트는 로컬이 아닙니다. 선택한 텍스트가 외부 네트워크로 전송됩니다.")
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }
                
                HStack {
                    Picker("Model", selection: modelSelection) {
                        ForEach(fetchedModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                        
                        if !settings.model.isEmpty && !fetchedModels.contains(settings.model) {
                            Text("Custom: \(settings.model)").tag(settings.model)
                        }
                        
                        Text("Custom...").tag("")
                    }
                    
                    Button {
                        Task {
                            await refreshModels()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("모델 목록 새로고침")
                    .disabled(isFetching)
                }
                
                if showsCustomModelField {
                    TextField("Custom model", text: $customModelEntry)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customModelEntry) { _, newValue in
                            settings.model = newValue
                        }
                }
                
                SecureField("API token", text: $settings.apiToken)
                    .textFieldStyle(.roundedBorder)
            }
            
            Section("응답 언어") {
                Picker("AI 응답 언어", selection: $settings.responseLanguage) {
                    ForEach(ResponseLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            }

            Section("ActionBar") {
                Picker("위치", selection: $settings.actionBarPosition) {
                    Text("↖ Top Left").tag(ActionBarPosition.topLeft)
                    Text("↑ Top").tag(ActionBarPosition.top)
                    Text("↗ Top Right").tag(ActionBarPosition.topRight)
                    Text("← Left").tag(ActionBarPosition.left)
                    Text("→ Right").tag(ActionBarPosition.right)
                    Text("↙ Bottom Left").tag(ActionBarPosition.bottomLeft)
                    Text("↓ Bottom").tag(ActionBarPosition.bottom)
                    Text("↘ Bottom Right").tag(ActionBarPosition.bottomRight)
                }
            }

            Section("액션") {
                ForEach(Action.allBuiltins) { action in
                    builtInRow(action: settings.resolvedBuiltin(action), originalId: action.id)
                }
                Divider()
                ForEach(settings.customActions) { action in
                    customRow(action: action)
                }
                .onMove { fromOffsets, toOffset in
                    settings.customActions.move(fromOffsets: fromOffsets, toOffset: toOffset)
                }
                Button {
                    editingAction = newDraftAction()
                    isEditing = true
                } label: {
                    Label("새 액션 추가", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            Section("권한") {
                permissionRow(
                    label: "Accessibility",
                    isTrusted: Accessibility.isTrusted,
                    actionTitle: "시스템 설정 열기",
                    action: { openSystemSettings(.accessibility) }
                )
            }
            
            Section {
                if let error = fetchError, isLocalEndpoint(settings.endpoint) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .sheet(isPresented: $isEditing) {
            CustomActionEditor(
                action: $editingAction,
                onCommit: { committed in
                    if let bid = editingBuiltinId {
                        settings.builtinOverrides[bid] = committed
                    } else if let idx = editingIndex {
                        settings.customActions[idx] = committed
                    } else {
                        settings.customActions.append(committed)
                    }
                    isEditing = false
                    editingIndex = nil
                    editingBuiltinId = nil
                },
                onCancel: {
                    isEditing = false
                    editingIndex = nil
                    editingBuiltinId = nil
                }
            )
        }
        .task {
            if showsCustomModelField {
                customModelEntry = settings.model
            }
            
            if lastFetched == nil || Date().timeIntervalSince(lastFetched!) > 60 {
                await refreshModels()
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            permissionRefreshTick = Date()
        }
    }

    @MainActor
    private func refreshModels() async {
        guard !isFetching else { return }
        isFetching = true
        fetchError = nil
        defer { isFetching = false }
        do {
            let client = OllamaClient(endpoint: settings.endpoint, token: settings.apiToken)
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

    @ViewBuilder
    private func permissionRow(
        label: String,
        isTrusted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        let _ = permissionRefreshTick
        HStack(spacing: 8) {
            Image(systemName: isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isTrusted ? Color.green : Color.orange)
            Text(label)
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.borderless)
        }
    }

    private enum PrivacyPanel: String {
        case accessibility = "Privacy_Accessibility"
    }

    private func openSystemSettings(_ panel: PrivacyPanel) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(panel.rawValue)")
            ?? URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        NSWorkspace.shared.open(url)
    }

    private func isLocalEndpoint(_ raw: String) -> Bool {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host else {
            return true
        }
        let lower = host.lowercased()
        return lower == "localhost" || lower == "127.0.0.1" || lower == "::1"
    }

    @ViewBuilder
    private func builtInRow(action: Action, originalId: String) -> some View {
        let isHidden = settings.isHidden(originalId)
        let isOverridden = settings.builtinOverrides[originalId] != nil
        HStack(spacing: 8) {
            Image(systemName: action.systemImage)
                .foregroundStyle(isHidden ? .secondary : .primary)
            Text(action.label)
                .foregroundStyle(isHidden ? .secondary : .primary)
            Spacer()
            Text("기본")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button {
                editingAction = action
                editingIndex = nil
                editingBuiltinId = originalId
                isEditing = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("수정")
            Button {
                if isHidden {
                    settings.hiddenBuiltinIds.remove(originalId)
                } else {
                    settings.hiddenBuiltinIds.insert(originalId)
                }
            } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(isHidden ? "숨김 해제" : "숨기기")
            Button {
                settings.resetBuiltin(originalId)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("초기화")
            .disabled(!isOverridden && !isHidden)
        }
    }

    @ViewBuilder
    private func customRow(action: Action) -> some View {
        HStack(spacing: 8) {
            Image(systemName: action.systemImage)
            Text(action.label)
            Spacer()

            Button {
                moveUp(action: action)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(settings.customActions.firstIndex(where: { $0.id == action.id }) == 0)

            Button {
                moveDown(action: action)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(settings.customActions.firstIndex(where: { $0.id == action.id }) == settings.customActions.count - 1)

            Button {
                editingAction = action
                editingIndex = settings.customActions.firstIndex(where: { $0.id == action.id })
                isEditing = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("수정")

            Button {
                settings.customActions.removeAll(where: { $0.id == action.id })
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("삭제")
        }
    }

    private func newDraftAction() -> Action {
        Action(
            id: UUID().uuidString,
            label: "",
            prompt: "",
            systemImage: "text.bubble"
        )
    }

    private func moveUp(action: Action) {
        guard let index = settings.customActions.firstIndex(where: { $0.id == action.id }), index > 0 else { return }
        settings.customActions.swapAt(index, index - 1)
    }

    private func moveDown(action: Action) {
        guard let index = settings.customActions.firstIndex(where: { $0.id == action.id }), index < settings.customActions.count - 1 else { return }
        settings.customActions.swapAt(index, index + 1)
    }
}
