import SwiftUI

/// The panel's Links: what links to the item and what it links to, each group a heading with its count and its rows.
/// A group past its first rows ends with Show All. A group whose field the item takes a change to has a plus on its
/// heading, which opens the page's own relation panel, and Remove in the menu of each of its links.
struct PanelLinksView: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    let item: ItemID
    let groups: [PanelLinkGroup]
    /// Opens the item as Settings > Open Items says, through the browser's follow function.
    let onOpen: (ItemID) -> Void
    @State private var expanded: Set<PanelLinkGroup.Kind> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                PanelLinkHeading(group: group, isFirst: index == 0, add: add)
                let isOpen = expanded.contains(group.kind)
                let shown = isOpen ? group.links[...] : group.links.prefix(group.shownFirst)
                ForEach(shown) { link in
                    PanelLinkRow(group: group, link: link, onOpen: onOpen) { remove(link.item, from: $0) }
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

    /// Opens the panel the page's row of the same field opens, under the heading.
    private func add(field: String, under anchor: NSView) {
        var request = ValueEditRequest(kind: .relation(field), library: library, item: item, undoManager: undoManager)
        request.open = onOpen
        ValueEditPresenter.shared.present(request, anchor: anchor)
    }

    /// One undo step. A refusal is told by the library, which leaves the link where it was.
    private func remove(_ link: ItemID, from field: String) {
        Task { await library.changeLinks(item, field: field, adding: [], removing: [link], undoManager: undoManager) }
    }
}

/// A group's heading, with a plus at its end while the pointer is over it, for a group that takes a new link.
private struct PanelLinkHeading: View {
    let group: PanelLinkGroup
    let isFirst: Bool
    let add: (String, NSView) -> Void
    @State private var hovering = false
    @State private var anchor = ValueEditAnchorBox()
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            PanelHeading(title: group.title, count: group.links.count, isFirst: isFirst)
            Spacer(minLength: 6)
            if let field = group.editableField {
                Button {
                    if let view = anchor.view { add(field, view) }
                } label: {
                    Image(systemName: "plus").foregroundStyle(.secondary).frame(width: 20, height: 20).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .focused($isFocused)
                .opacity(hovering || isFocused ? 1 : 0)
                .help("Add to \(group.title)")
                .accessibilityLabel("Add to \(group.title)")
                .accessibilityIdentifier("PanelLinkAdd.\(group.kind.rawValue)")
            }
        }
        .background(ValueEditAnchor(box: anchor))
        .contentShape(.rect)
        .onHover { hovering = $0 }
    }
}

/// One linked item: its mark (a task's status in place of its type's), its name, and when it last changed. In a group
/// that takes a change, a menu with Open and Remove replaces the date while the pointer is over the row.
private struct PanelLinkRow: View {
    @Environment(\.interfaceTextSize) private var textSize
    let group: PanelLinkGroup
    let link: PanelLink
    let onOpen: (ItemID) -> Void
    /// Removes the link from the field it is in.
    let onRemove: (String) -> Void
    @State private var hovering = false

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
                if !link.detail.isEmpty, !(hovering && group.editableField != nil) {
                    Text(verbatim: link.detail).interfaceFont(.callout).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                }
            }
            .interfaceFont(.body)
            .frame(maxWidth: .infinity, minHeight: PanelMetrics.rowHeight * scale, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if let field = group.editableField, hovering {
                Menu { actions(field) } label: {
                    Label("Link Actions", systemImage: "ellipsis").labelStyle(.iconOnly).frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityIdentifier("PanelLinkActions.\(group.kind.rawValue).\(link.item.rawValue)")
            }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            if let field = group.editableField { actions(field) }
        }
        .accessibilityIdentifier("PanelLink.\(group.kind.rawValue).\(link.item.rawValue)")
    }

    @ViewBuilder private func actions(_ field: String) -> some View {
        Button("Open Item") { onOpen(link.item) }
        Button("Remove", role: .destructive) { onRemove(field) }
    }
}
