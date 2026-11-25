import SwiftUI

/// The panel's Links: what links to the item and what it links to, each group a heading with its count and its rows.
/// A group past its first rows ends with Show All.
struct PanelLinksView: View {
    let groups: [PanelLinkGroup]
    /// Opens the item as Settings > Open Items says, through the browser's follow function.
    let onOpen: (ItemID) -> Void
    @State private var expanded: Set<PanelLinkGroup.Kind> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                PanelHeading(title: group.title, count: group.links.count, isFirst: index == 0)
                let isOpen = expanded.contains(group.kind)
                let shown = isOpen ? group.links[...] : group.links.prefix(group.shownFirst)
                ForEach(shown) { link in
                    PanelLinkRow(group: group.kind, link: link, onOpen: onOpen)
                }
                if !isOpen, group.links.count > group.shownFirst {
                    PanelMoreButton(title: String(localized: "Show All \(group.links.count)"), identifier: "PanelShowAll.\(group.kind.rawValue)") {
                        expanded.insert(group.kind)
                    }
                }
            }
        }
        .accessibilityIdentifier("PanelLinks")
    }
}

/// One linked item: its mark (a task's status in place of its type's), its name, and when it last changed.
private struct PanelLinkRow: View {
    @Environment(\.interfaceTextSize) private var textSize
    let group: PanelLinkGroup.Kind
    let link: PanelLink
    let onOpen: (ItemID) -> Void

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        Button { onOpen(link.item) } label: {
            HStack(spacing: 8) {
                Group {
                    if let status = link.status { StatusMark(group: status, scale: scale) } else { TonedGlyph(id: link.icon) }
                }
                .frame(width: 16)
                Text(verbatim: link.title)
                    .fontWeight(link.isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                if !link.detail.isEmpty {
                    Text(verbatim: link.detail).interfaceFont(.callout).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                }
            }
            .interfaceFont(.body)
            .frame(maxWidth: .infinity, minHeight: PanelMetrics.rowHeight * scale, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("PanelLink.\(group.rawValue).\(link.item.rawValue)")
    }
}
