import SwiftUI

struct CustomActionEditor: View {
    @Binding var action: Action
    let onCommit: (Action) -> Void
    let onCancel: () -> Void

    @State private var label: String = ""
    @State private var prompt: String = ""
    @State private var systemImage: String = "text.bubble"
    @State private var kind: ActionKind = .ai
    @State private var systemType: SystemActionType = .copy

    private var isSaveDisabled: Bool {
        switch kind {
        case .ai:
            return label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .system:
            return label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("액션 편집")
                .font(.headline)

            Form {
                Picker("종류", selection: $kind) {
                    ForEach(ActionKind.allCases) { k in
                        Text(k.displayName).tag(k)
                    }
                }
                .pickerStyle(.segmented)

                if kind == .system {
                    Picker("기본 기능", selection: $systemType) {
                        ForEach(SystemActionType.allCases) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                }

                TextField("이름", text: $label)
                    .textFieldStyle(.roundedBorder)

                if kind == .ai {
                    TextField("프롬프트", text: $prompt, axis: .vertical)
                        .lineLimit(4...8)
                        .textFieldStyle(.roundedBorder)
                    Text("프롬프트 변수: {selection}, {language}, {appBundleID}")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("아이콘")
                .font(.subheadline)
            SymbolGridPicker(selection: $systemImage)

            HStack {
                Spacer()
                Button("취소") { onCancel() }
                Button("저장") {
                    let result: Action
                    switch kind {
                    case .ai:
                        result = Action(
                            id: action.id,
                            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                            prompt: prompt,
                            systemImage: systemImage,
                            kind: .ai,
                            systemType: nil
                        )
                    case .system:
                        result = Action(
                            id: action.id,
                            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                            prompt: "",
                            systemImage: systemImage,
                            kind: .system,
                            systemType: systemType
                        )
                    }
                    onCommit(result)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaveDisabled)
            }
        }
        .padding(20)
        .frame(width: 480, height: 480)
        .onAppear {
            label = action.label
            prompt = action.prompt
            systemImage = action.systemImage
            kind = action.kind
            systemType = action.systemType ?? .copy
        }
    }
}
