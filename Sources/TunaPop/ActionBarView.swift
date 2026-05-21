import SwiftUI

struct ActionBarView: View {
    let actions: [Action]
    let onAction: (Action) -> Void
    var onHoverStateChanged: ((Bool) -> Void)? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(actions) { action in
                TooltipImageButton(
                    systemImage: action.systemImage,
                    toolTip: action.label
                ) {
                    onAction(action)
                }
                .frame(width: 30, height: 30)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .onHover { hovering in
            onHoverStateChanged?(hovering)
        }
    }
}
