import SwiftUI

/// A row of the list, for any type: what the type's look says (`RowContent`, worked out once for the item), laid out at the
/// density the list has. Standard is laid out as Mail lays out a message: the title and, at the trailing edge, the date;
/// under them one line in secondary color; then the bottom line of chips. A row has only the lines it has something to put
/// in, so one with nothing under its title is the title and the date. Compact is the type's mark where the list mixes
/// types, the title and the date. Nothing sits at the leading edge of a Standard row, so titles line up down the list.
/// A search's row is always laid out as a Standard one, since its excerpt, which stands in the place of the line under the
/// title, is the point.
struct ItemRow: View {
    let content: RowContent
    var density = Density.standard
    /// The words a search found in the item, in place of the line under its title.
    var excerpt: SearchExcerpt?

    /// A match in the title is shown in the title itself, since the excerpt would only say it again.
    private var titleExcerpt: SearchExcerpt? {
        guard let excerpt, !content.title.isEmpty,
              excerpt.plainText.trimmingCharacters(in: .whitespaces) == content.title
        else { return nil }
        return excerpt
    }

    var body: some View {
        let isCompact = density == .compact && excerpt == nil
        Group {
            if isCompact { compact } else { standard }
        }
        .padding(.vertical, isCompact ? 3 : 6)
        // One piece of text, which is how a row is found by its words (`value`) in the accessibility tree.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.spoken)
        .accessibilityAddTraits(.isStaticText)
    }

    private var compact: some View {
        HStack(spacing: 8) {
            if content.mixesTypes { TypeMark(icon: content.typeIcon) }
            Text(content.title)
                .interfaceFont(.body)
                .lineLimit(1)
            Spacer(minLength: 8)
            dateText
        }
    }

    private var standard: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Group {
                    if let titleExcerpt { Text(titleExcerpt.attributed()) } else { Text(content.title) }
                }
                .interfaceFont(.body.weight(.semibold))
                .lineLimit(1)
                Spacer(minLength: 8)
                dateText
            }
            if let excerpt, titleExcerpt == nil {
                Text(excerpt.attributed())
                    .interfaceFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if excerpt == nil, let secondary = content.secondary {
                Text(secondary)
                    .interfaceFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !content.chips.isEmpty || content.more > 0 {
                ChipLine(content: content)
                    .padding(.top, 1)
            }
        }
    }

    @ViewBuilder private var dateText: some View {
        if let date = content.date {
            Text(date)
                .interfaceFont(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }
}
