import SwiftUI

extension Bundle {
    var appVersionDisplay: String {
        if let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return version
        }
        return "0.1.0"
    }
}

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @ObservedObject private var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        self._viewModel = StateObject(wrappedValue: SettingsViewModel(settings: settings))
    }

    private static var appDelegate: AppDelegate? {
        NSApplication.shared.delegate as? AppDelegate
    }

    @State private var permissionRefreshTick = Date()

    private var endpointSelection: Binding<String> {
        Binding<String>(
            get: { settings.endpoint },
            set: { settings.endpoint = $0 }
        )
    }

    private var apiTokenSelection: Binding<String> {
        Binding<String>(
            get: { settings.apiToken },
            set: { settings.apiToken = $0 }
        )
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
                    settings.model = viewModel.customModelEntry
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
                .onChange(of: settings.agentProvider) { _, _ in
                    Task {
                        await viewModel.refreshModels()
                    }
                }
                
                TextField("Endpoint", text: endpointSelection)
                    .textFieldStyle(.roundedBorder)
                
                if !viewModel.isLocalEndpoint(settings.endpoint) {
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
                        ForEach(viewModel.fetchedModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                        
                        if !settings.model.isEmpty && !viewModel.fetchedModels.contains(settings.model) {
                            Text("Custom: \(settings.model)").tag(settings.model)
                        }
                        
                        Text("Custom...").tag("")
                    }
                    
                    Button {
                        Task {
                            await viewModel.refreshModels()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("모델 목록 새로고침")
                    .disabled(viewModel.isFetching)
                }
                
                if viewModel.showsCustomModelField {
                    TextField("Custom model", text: $viewModel.customModelEntry)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: viewModel.customModelEntry) { _, newValue in
                            viewModel.updateCustomModel(newValue)
                        }
                }
                
                SecureField(
                    settings.agentProvider.requiresAPIKey ? "API token" : "API token (선택)",
                    text: apiTokenSelection
                )
                .textFieldStyle(.roundedBorder)
            }
            
            Section("환경") {
                Picker("응답 언어", selection: $settings.responseLanguage) {
                    ForEach(ResponseLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                Picker("ActionBar 위치", selection: $settings.actionBarPosition) {
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
                    viewModel.startEditingNewAction()
                } label: {
                    Label("새 액션 추가", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            Section("권한") {
                permissionRow(
                    label: "Accessibility",
                    isTrusted: viewModel.isAccessibilityTrusted,
                    actionTitle: "시스템 설정 열기",
                    action: { viewModel.openSystemSettings() }
                )
            }

            Section("고급") {
                Button("업데이트 확인...") {
                    Self.appDelegate?.updater.checkForUpdates()
                }
                Toggle("진단 로그 표시", isOn: $settings.verboseLogging)
                Text("켜면 Console.app에서 subsystem:app.tunapop 으로 자세한 로그를 볼 수 있습니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                if let error = viewModel.fetchError, viewModel.isLocalEndpoint(settings.endpoint) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Text("tunaPop v\(Bundle.main.appVersionDisplay)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .sheet(isPresented: $viewModel.isEditing) {
            CustomActionEditor(
                action: $viewModel.editingAction,
                usedSymbols: viewModel.usedSymbols(excludingId: viewModel.editingBuiltinId ?? viewModel.editingAction.id),
                onCommit: { _ in
                    viewModel.commitEditing()
                },
                onCancel: {
                    viewModel.cancelEditing()
                }
            )
        }
        .task {
            if viewModel.showsCustomModelField {
                viewModel.customModelEntry = settings.model
            }
            
            if viewModel.lastFetched == nil || Date().timeIntervalSince(viewModel.lastFetched!) > 60 {
                await viewModel.refreshModels()
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            permissionRefreshTick = Date()
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

    @ViewBuilder
    private func builtInRow(action: Action, originalId: String) -> some View {
        let isHidden = settings.isHidden(originalId)
        let isOverridden = settings.builtinOverrides[originalId] != nil
        let visibleBuiltinCount = Action.allBuiltins.filter { !settings.isHidden($0.id) }.count
        let isLastVisible = !isHidden && visibleBuiltinCount <= 1
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
                viewModel.startEditingBuiltin(action: action, originalId: originalId)
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
            .help(isLastVisible ? "마지막 기본 액션은 숨길 수 없습니다" : (isHidden ? "숨김 해제" : "숨기기"))
            .disabled(isLastVisible)
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
                viewModel.moveUp(action: action)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(settings.customActions.firstIndex(where: { $0.id == action.id }) == 0)

            Button {
                viewModel.moveDown(action: action)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(settings.customActions.firstIndex(where: { $0.id == action.id }) == settings.customActions.count - 1)

            Button {
                viewModel.startEditingCustom(action: action)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("수정")

            Button {
                viewModel.deleteCustomAction(action)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("삭제")
        }
    }
}
