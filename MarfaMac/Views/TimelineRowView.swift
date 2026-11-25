import SwiftUI

/// A row of the timeline (boards V5 and V6): the title in regular weight on one line, with the row's chips at the trailing
/// edge of that line, then a second line in caption size and secondary color, led by the type's name where the list mixes
/// types. Every row is these two lines and one height, so a row with nothing to say on the second line keeps it.
struct TimelineRowView: View {
    let content: RowContent
    /// The item the row is for, which its status chip changes by a click.
    var itemID: ItemID?

    var body: some View {
        let face = TimelineRowFace(content)
        VStack(alignment: .leading, spacing: 2) {
            // A chip is taller than the title's text, so an unseen one holds the line's height for rows with none.
            ZStack(alignment: .leading) {
                PageChip(text: "Ag", kind: .tag, size: .row).hidden().accessibilityHidden(true)
                HStack(alignment: .center, spacing: 8) {
                    Text(face.title)
                        .interfaceFont(.body)
                        .lineLimit(1)
                    if content.inFeed { FeedMark() }
                    Spacer(minLength: 8)
                    if !face.chips.isEmpty || face.more > 0 {
                        ChipLine(chips: face.chips, more: face.more, statusItem: content.editsStatus ? itemID : nil)
                            .fixedSize()
                            .layoutPriority(1)
                    }
                }
            }
            HStack(spacing: 6) {
                if let type = face.typeName { Text(type).lineLimit(1).layoutPriority(1) }
                if let secondary = face.secondary { Text(secondary).lineLimit(1) }
                if !face.hasSecondLine { Text(verbatim: " ") }
                Spacer(minLength: 0)
            }
            .interfaceFont(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.spoken)
        .accessibilityAddTraits(.isStaticText)
        .changesStatus(of: content.editsStatus ? itemID : nil)
    }
}
