import SwiftUI

/// The small card a linked item shows under the pointer: its type's mark and name, its own name, and up to two lines
/// (`LinkCardContent`). It draws what the copy holds and the counts Marfa last answered, asks for nothing, and an item
/// that cannot be shown draws nothing, so no card appears for it.
struct LinkCardView: View {
    let id: ItemID
    let library: any ItemLibrary
    let textSize: Int
    @Environment(\.colorScheme) private var scheme

    /// The card's content for the item now, or nil where there is none to show.
    static func content(of id: ItemID, in library: any ItemLibrary) -> LinkCardContent? {
        guard let item = library.cardItem(id) else { return nil }
        var counts: [CountQuery: ItemCountAnswer] = [:]
        for query in LinkCardContent.counts(for: item, in: library.catalogue) {
            if let answer = library.counts.answer(of: id, query) { counts[query] = answer }
        }
        return LinkCardContent.of(item, in: library.catalogue, counts: counts, format: .stored(), now: library.now())
    }

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        if let content = Self.content(of: id, in: library) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5 * scale) {
                    TonedGlyph(id: content.icon, size: 14 * scale)
                    Text(verbatim: content.typeName).font(.system(size: 11.5 * scale, weight: .medium)).foregroundStyle(.secondary)
                }
                .frame(height: 17 * scale)
                Text(verbatim: content.title)
                    .font(.system(size: 14 * scale, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.top, 2 * scale)
                ForEach(content.lines, id: \.self) { line in
                    Text(verbatim: line).font(.system(size: 12 * scale)).foregroundStyle(.secondary).padding(.top, scale)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.init(top: 9 * scale, leading: 14 * scale, bottom: 10 * scale, trailing: 14 * scale))
            .frame(maxWidth: 340 * scale, alignment: .leading)
            .fixedSize()
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: ([content.typeName, content.title] + content.lines).joined(separator: ", ")))
        }
    }
}
