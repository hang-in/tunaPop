import SwiftUI

struct SymbolGridPicker: View {
    @Binding var selection: String
    var usedSymbols: Set<String> = []

    static let curated: [String] = [
        "text.bubble", "list.bullet.rectangle", "character.bubble",
        "doc.text", "info.bubble", "lightbulb", "questionmark.circle",
        "highlighter", "pencil.tip.crop.circle", "doc.on.clipboard",
        "wand.and.stars", "sparkles", "globe", "translate",
        "character.book.closed", "text.book.closed",
        "magnifyingglass", "checkmark.circle", "exclamationmark.bubble",
        "quote.bubble", "bubble.left.and.bubble.right",
        "arrow.left.arrow.right.circle", "arrow.triangle.2.circlepath",
        "scissors", "doc.on.doc", "paintbrush", "wand.and.rays",
        "ellipsis.bubble", "rectangle.and.text.magnifyingglass",
        "fish"
    ]

    private let columns = Array(repeating: GridItem(.fixed(36), spacing: 6), count: 6)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Self.curated, id: \.self) { name in
                    let isUsed = usedSymbols.contains(name) && name != selection
                    Button {
                        if !isUsed {
                            selection = name
                        }
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 16))
                            .frame(width: 32, height: 32)
                            .opacity(isUsed ? 0.25 : 1.0)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selection == name ? Color.accentColor.opacity(0.25) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        selection == name ? Color.accentColor : Color.primary.opacity(0.1),
                                        lineWidth: selection == name ? 1.5 : 0.5
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(isUsed)
                    .help(isUsed ? "\(name) — 이미 사용 중" : name)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 200)
    }
}
