import SwiftUI

struct ResponseView: View {
    let state: ResponseState
    let isPinned: Bool
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    var onHoverStateChanged: ((Bool) -> Void)? = nil

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            body(for: state)
        }
        .frame(width: 360)
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .onHover { hovering in
            onHoverStateChanged?(hovering)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("tunaPop")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                onTogglePin()
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(isPinned ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            }
            .buttonStyle(.plain)
            .help(isPinned ? "고정 해제" : "고정")
            Button {
                onCopy()
                didCopy = true
                Task {
                    try? await Task.sleep(for: .milliseconds(1500))
                    didCopy = false
                }
            } label: {
                Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(didCopy ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func body(for state: ResponseState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .success(let text, let metadata):
            VStack(alignment: .leading, spacing: 6) {
                ScrollView {
                    Text(text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 60, maxHeight: 280)
                if let metadata {
                    Text("model: \(metadata.model) · tokens: \(metadata.totalTokens)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        case .failure(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
