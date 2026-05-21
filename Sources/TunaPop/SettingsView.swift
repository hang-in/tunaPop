import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    @State private var fetchedModels: [String] = []
    @State private var lastFetched: Date?
    @State private var isFetching = false
    @State private var fetchError: String?
    @State private var customModelEntry: String = ""

    @State private var permissionRefreshTick = Date()

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
            Section("Ollama") {
                TextField("Endpoint", text: $settings.endpoint)
                    .textFieldStyle(.roundedBorder)
                
                if !isLocalEndpoint(settings.endpoint) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("이 엔드포인트는 로컬이 아닙니다. 선택한 텍스트가 외부 네트워크로 전송됩니다.")
                            .font(.caption)
                            .foregroundStyle(.orange)
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
                        .onChange(of: customModelEntry) { oldValue, newValue in
                            settings.model = newValue
                        }
                }
                
                SecureField("API token", text: $settings.apiToken)
                    .textFieldStyle(.roundedBorder)
            }
            
            Section("기본 동작") {
                TextField("Default prompt", text: $settings.defaultPrompt, axis: .vertical)
                    .lineLimit(3...5)
                    .textFieldStyle(.roundedBorder)
                
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

            Section("권한") {
                permissionRow(
                    label: "Accessibility",
                    isTrusted: Accessibility.isTrusted,
                    actionTitle: "시스템 설정 열기",
                    action: { openSystemSettings(.accessibility) }
                )
                permissionRow(
                    label: "Input Monitoring",
                    isTrusted: InputMonitoring.isTrusted,
                    actionTitle: "권한 요청",
                    action: { InputMonitoring.request() }
                )
            }
            
            Section {
                if let error = fetchError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
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
        case inputMonitoring = "Privacy_ListenEvent"
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
}
