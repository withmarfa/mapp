import SwiftUI

/// The bottom line of a row, a gallery card or a board card: the page's own chips at row size, then how many values the
/// line leaves out. A long label gives way before a mark does.
struct ChipLine: View {
    let chips: [RowContent.Chip]
    let more: Int
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize

    init(content: RowContent) {
        chips = content.chips
        more = content.more
    }

    var body: some View {
        let size = ChipLooks.current.rowTextSize * CGFloat(textSize) / 13
        HStack(spacing: 6) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                switch chip {
                case .type(let icon, let label):
                    PageChip(text: label, kind: .type(icon: icon), size: .row)
                case .status(let symbol, let label):
                    PageChip(text: label, kind: .status(symbol, chevron: false), size: .row)
                case .option(let label, let tone):
                    PageChip(text: label, kind: .option(tone), size: .row)
                case .person(let initials, let name):
                    PagePerson(name: name, initials: initials, size: .row).help(name)
                case .tag(let tag):
                    PageChip(text: tag, kind: .tag, size: .row)
                case .text(let text):
                    Text(verbatim: text).font(.system(size: size)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if more > 0 {
                Text(verbatim: "+\(more)").font(.system(size: size)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }
}
