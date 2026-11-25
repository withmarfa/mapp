import MarfaIcons
import SwiftUI

/// A relationship as a group of the inspector: its name as a small heading above a box of its own, each item it reaches
/// as a row in the box with the item's type icon, which opens it. An editable one offers Open and Remove from a menu that
/// shows on hover and in the context menu; the links are added and changed from the item's page.
struct ItemRelationshipGroup: View {
    let relationship: ItemRelationship
    /// The icon of the type of the item a target points at.
    var typeIcon: (ItemID) -> String? = { _ in nil }
    /// Whether the person has shown every link of the group, and what shows them.
    var isExpanded = false
    var onShowAll: () -> Void = {}
    let onOpen: (ItemID) -> Void
    let onRemove: (ItemID) async -> Bool
    /// Whether the page shows this relationship too, and what changes it; nil offers no choice.
    var shownOnPage = true
    var onShowOnPage: ((Bool) -> Void)?
    @State private var rejected = false

    /// The heading sits above a box of its own, so each relationship reads as a group. The box takes the links, the
    /// rest of them and a refusal as rows, never one row holding them.
    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.headingGap) {
            HStack(spacing: 4) {
                InspectorSubheading(title: relationship.label, count: relationship.targets.count)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, InspectorMetrics.boxInset)
            .contentShape(.rect)
            .showOnPageMenu(isShown: shownOnPage, onChange: onShowOnPage)
            let links = LinkLimit.split(relationship.targets, expanded: isExpanded)
            InspectorBox {
                ForEach(links.shown) { target in
                    ItemTargetRow(target: target, relationship: relationship, typeIcon: typeIcon, onOpen: onOpen) { id in
                        Task { rejected = !(await onRemove(id)) }
                    }
                    .showOnPageMenu(isShown: shownOnPage, onChange: onShowOnPage)
                }
                if links.hidden > 0 {
                    ItemShowMoreButton(count: links.hidden, identifier: "RelationshipShowMore.\(relationship.field)", action: onShowAll)
                }
                if rejected {
                    Text("The connection could not be removed.")
                        .interfaceFont(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}

/// The small heading of a group inside a section: the name of a relationship.
struct InspectorSubheading: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: title)
            if let count {
                Text(count, format: .number).monospacedDigit()
            }
        }
        .interfaceFont(.callout.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One item a relationship reaches, as a row across the width: the type's icon and the title, which opens the item.
/// Where a relationship can be changed, the row shows a menu while the pointer is over it.
struct ItemTargetRow: View {
    let target: ItemRelationshipTarget
    let relationship: ItemRelationship
    var typeIcon: (ItemID) -> String? = { _ in nil }
    let onOpen: (ItemID) -> Void
    let onRemove: (ItemID) -> Void
    @Environment(\.interfaceTextSize) private var textSize
    @State private var hovering = false

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        let shows = relationship.isEditable && hovering
        InspectorItemRow(target: target, typeIcon: typeIcon, onOpen: onOpen,
                         trailingInset: shows ? InspectorMetrics.trailingColumn * scale : 0)
            .overlay(alignment: .trailing) {
                if shows { actions.inspectorTrailingColumn(clearsFold: false) }
            }
            .onHover { hovering = $0 }
            .contextMenu { menuItems }
    }

    private var actions: some View {
        Menu {
            menuItems
        } label: {
            Label("Connection Actions", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .frame(width: InspectorMetrics.trailingColumn * InterfaceStyle.scale(for: textSize),
                       height: InspectorMetrics.trailingColumn * InterfaceStyle.scale(for: textSize))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Connection Actions")
        .accessibilityIdentifier("RelationshipActions.\(relationship.field).\(target.id)")
    }

    @ViewBuilder private var menuItems: some View {
        if let id = target.itemID, target.isOpenable {
            Button("Open Item") { onOpen(id) }
        }
        if relationship.isEditable {
            if let id = target.itemID {
                Button("Remove Connection", role: .destructive) { onRemove(id) }
            }
        }
    }
}

extension VerticalAlignment {
    /// The center of a link row's title, which its mark sits on, whatever stands under the title.
    static let inspectorTitleCenter = VerticalAlignment(InspectorTitleCenter.self)
}

private enum InspectorTitleCenter: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
}

/// The control that ends a group of links cut short: it shows the rest.
struct ItemShowMoreButton: View {
    let count: Int
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Show \(count) More")
                .interfaceFont(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(InspectorRowButtonStyle())
        .accessibilityIdentifier(identifier)
    }
}

/// An item as a light row across the width, with its type's icon. A link to an item the library does not hold, or
/// that cannot be opened, says why instead.
struct InspectorItemRow: View {
    let target: ItemRelationshipTarget
    var typeIcon: (ItemID) -> String? = { _ in nil }
    let onOpen: (ItemID) -> Void
    /// Room kept at the end of the row for a control laid over it.
    var trailingInset: CGFloat = 0

    var body: some View {
        Group {
            if let id = target.itemID, target.isOpenable {
                Button { onOpen(id) } label: {
                    HStack(alignment: .inspectorTitleCenter, spacing: InspectorMetrics.markGap) {
                        TonedGlyph(id: typeIcon(id))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.displayTitle)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .multilineTextAlignment(.leading)
                                .alignmentGuide(.inspectorTitleCenter) { $0[VerticalAlignment.center] }
                            if target.isDeleted {
                                Label("Deleted", systemImage: "trash")
                                    .interfaceFont(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.trailing, trailingInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(InspectorRowButtonStyle())
                .foregroundStyle(.primary)
                .help(target.displayTitle)
                .accessibilityIdentifier("RelationshipTarget.\(id.rawValue)")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    // A link to an item the library does not hold has no title to show.
                    if !target.title.isEmpty {
                        Text(target.title).lineLimit(2)
                    }
                    Label(resolutionLabel, systemImage: "exclamationmark.triangle")
                        .interfaceFont(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .interfaceFont(.body)
    }

    private var resolutionLabel: String {
        switch target.resolution {
        case .ambiguous: String(localized: "More than one item matches")
        case .missing: String(localized: "Item not found")
        case .pending: String(localized: "Not looked up yet")
        case .refused: String(localized: "The server refused this link")
        case .resolved: String(localized: "Item unavailable")
        }
    }
}

#if DEBUG
#Preview("Wrapping Connections") {
    let id = ItemID("10000000-0000-0000-0000-000000000001")
    let names = SampleLibrary.catalogue.edgeTypes
    let parent = ItemRelationship(
        field: "child-of", label: names["parent-of"]?.reverseLabel ?? "", targets: [
            .init(title: "Field Research: review the observations and photographs from every location", itemID: id, resolution: .resolved(id))
        ], isEditable: true)
    let about = ItemRelationship(
        field: "about", label: names["about"]?.label ?? "", targets: [
            .init(title: "Field notes", itemID: id, resolution: .resolved(id)),
            .init(title: "Interview with the site manager", itemID: nil, resolution: .missing)
        ], isEditable: true)
    VStack(alignment: .leading, spacing: InspectorMetrics.groupGap) {
        ItemRelationshipGroup(relationship: parent, onOpen: { _ in }, onRemove: { _ in true })
        ItemRelationshipGroup(relationship: about, onOpen: { _ in }, onRemove: { _ in true })
    }
    .padding(16)
    .interfaceTextStyle()
    .frame(width: 300)
}
#endif
