import SwiftUI

/// A row of the list, for any type: what the type's look says (`RowContent`, worked out once for the item), laid out at the
/// density the list has. Standard is laid out as Mail lays out a message: the title and, at the trailing edge, the date;
/// under them one line in secondary color; then the bottom line of chips. A row has only the lines it has something to put
/// in, so one with nothing under its title is the title and the date. Compact is the type's mark where the list mixes
/// types, the title and the date. Nothing sits at the leading edge of a Standard row, so titles line up down the list.
/// A search's row is always laid out as a Standard one, since its excerpt, which stands in the place of the line under the
/// title, is the point.
///
/// A Standard row whose content has a picture (`RowContent.picture`, which the list decided) draws it at the trailing edge
/// under the date, beside the lines under the title. That row is as tall as the picture needs, so it is the one row that is
/// taller than its words; a Compact row never has one.
struct ItemRow: View {
    let content: RowContent
    var density = Density.standard
    /// The words a search found in the item, in place of the line under its title.
    var excerpt: SearchExcerpt?
    /// The item the row is for, which its status chip changes by a click. Nil for a row with no item behind it.
    var itemID: ItemID?
    /// Whether the row draws a sample picture, for a preview with no item behind it (`SamplePicture`).
    var showsSample = false

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
        .changesStatus(of: content.editsStatus ? itemID : nil)
    }

    private var compact: some View {
        HStack(spacing: 8) {
            if content.mixesTypes { TonedGlyph(id: content.typeIcon) }
            Text(content.title)
                .interfaceFont(InterfaceStyle.primaryFont)
                .lineLimit(1)
            if content.inFeed { FeedMark() }
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
                .interfaceFont(InterfaceStyle.primaryFont.weight(.semibold))
                .lineLimit(1)
                if content.inFeed { FeedMark() }
                Spacer(minLength: 8)
                dateText
            }
            if content.picture != nil || showsSample {
                HStack(alignment: .top, spacing: 8) {
                    if hasDetails { details.frame(maxWidth: .infinity, alignment: .leading) } else { Spacer(minLength: 0) }
                    picture
                }
            } else if hasDetails {
                details
            }
        }
    }

    private var hasSecondary: Bool {
        (excerpt != nil && titleExcerpt == nil) || (excerpt == nil && content.secondary != nil)
    }

    private var hasDetails: Bool { hasSecondary || !content.chips.isEmpty || content.more > 0 }

    /// The line under the title, then the bottom line of chips.
    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let excerpt, titleExcerpt == nil {
                Text(excerpt.attributed())
                    .interfaceFont(InterfaceStyle.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if excerpt == nil, let secondary = content.secondary {
                Text(secondary)
                    .interfaceFont(InterfaceStyle.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !content.chips.isEmpty || content.more > 0 {
                ChipLine(content: content, statusItem: itemID, typeFont: InterfaceStyle.captionFont)
                    .padding(.top, 1)
            }
        }
    }

    @ViewBuilder private var picture: some View {
        if showsSample {
            RowPictureFrame { SamplePicture() }
        } else if let picture = content.picture {
            RowPictureView(picture: picture, icon: content.typeIcon)
        }
    }

    @ViewBuilder private var dateText: some View {
        if let date = content.date {
            Text(date)
                .interfaceFont(InterfaceStyle.captionFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }
}
