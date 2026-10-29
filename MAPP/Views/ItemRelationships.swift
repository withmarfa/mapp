import MarfaIcons
import SwiftUI

/// A relationship as a group of the inspector: its name as a small heading, each item it reaches as a chip with the
/// item's type icon, which opens it, and a quiet row to add another where the relationship takes several. An
/// editable one offers Open, Change or Manage, and Remove from a menu that shows on hover and in the context menu.
struct ItemRelationshipGroup: View {
    let relationship: ItemRelationship
    /// The icon of the type of the item a target points at.
    var typeIcon: (ItemID) -> String? = { _ in nil }
    /// Whether the person has shown every link of the group, and what shows them.
    var isExpanded = false
    var onShowAll: () -> Void = {}
    let onOpen: (ItemID) -> Void
    let onEdit: () -> Void
    let onRemove: (ItemID) -> Bool
    /// Whether the page shows this relationship too, and what changes it; nil offers no choice.
    var shownOnPage = true
    var onShowOnPage: ((Bool) -> Void)?
    @State private var rejected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            InspectorSubheading(title: ItemTypeInfo.Field.displayLabel(relationship.label))
            let links = LinkLimit.split(relationship.targets, expanded: isExpanded)
            ForEach(links.shown) { target in
                ItemTargetChip(target: target, relationship: relationship, typeIcon: typeIcon, onOpen: onOpen, onEdit: onEdit) { id in
                    rejected = !onRemove(id)
                }
            }
            if links.hidden > 0 {
                ItemShowMoreButton(count: links.hidden, identifier: "RelationshipShowMore.\(relationship.field)", action: onShowAll)
            }
            if relationship.isEditable && relationship.allowsMultiple {
                InspectorAddRow(title: "Add", identifier: "RelationshipAddRow.\(relationship.field)", action: onEdit)
            }
            if rejected {
                Text("The connection could not be removed.")
                    .interfaceFont(.caption).foregroundStyle(.red)
            }
        }
        .showOnPageMenu(isShown: shownOnPage, onChange: onShowOnPage)
    }
}

/// The small heading of a group inside a section: the name of a relationship.
struct InspectorSubheading: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .interfaceFont(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One item a relationship reaches, as a chip across the width: the type's icon and the title, which opens the
/// item. Where a relationship can be changed, the chip shows a menu while the pointer is over it.
struct ItemTargetChip: View {
    let target: ItemRelationshipTarget
    let relationship: ItemRelationship
    var typeIcon: (ItemID) -> String? = { _ in nil }
    let onOpen: (ItemID) -> Void
    let onEdit: () -> Void
    let onRemove: (ItemID) -> Void
    @State private var hovering = false

    var body: some View {
        ItemChip(target: target, typeIcon: typeIcon, onOpen: onOpen, trailingInset: relationship.isEditable && hovering ? 22 : 0)
            .overlay(alignment: .trailing) {
                if relationship.isEditable && hovering {
                    actions.padding(.trailing, 6)
                }
            }
            .onHover { hovering = $0 }
            .contextMenu { menuItems }
    }

    private var actions: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis")
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
            Button(relationship.allowsMultiple ? "Manage Connections…" : "Replace…", action: onEdit)
                .accessibilityIdentifier("RelationshipEdit.\(relationship.field)")
            if let id = target.itemID {
                Button("Remove Connection", role: .destructive) { onRemove(id) }
            }
        }
    }
}

/// The control that ends a group of links cut short: it shows the rest.
struct ItemShowMoreButton: View {
    let count: Int
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button("Show \(count) More", action: action)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .inspectorMinimumHeight()
            .inspectorValue()
            .accessibilityIdentifier(identifier)
    }
}

/// An item as a chip across the width, with its type's icon. A link to an item the library does not hold, or that
/// cannot be opened, says why instead.
struct ItemChip: View {
    let target: ItemRelationshipTarget
    var typeIcon: (ItemID) -> String? = { _ in nil }
    let onOpen: (ItemID) -> Void
    /// Room kept at the end of the chip for a control laid over it.
    var trailingInset: CGFloat = 0

    var body: some View {
        if let id = target.itemID, target.isOpenable {
            Button { onOpen(id) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TypeIcon(name: typeIcon(id))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.title)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
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
            .buttonStyle(InspectorChipStyle())
            .foregroundStyle(.primary)
            .help(target.title)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .inspectorChip()
        }
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

/// The last control of the Relationships section: the relationships the item can still take, each opening the
/// chooser. It offers one only when it is empty or takes several, since a single one that is set is changed from
/// its own chip.
struct ItemAddRelationshipButton: View {
    let options: [ItemRelationship]
    let onEdit: (ItemRelationship) -> Void

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button(ItemTypeInfo.Field.displayLabel(option.label)) { onEdit(option) }
                    .accessibilityIdentifier("RelationshipAdd.\(option.field)")
            }
        } label: {
            Label("Add Relationship", systemImage: "plus")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .fixedSize()
        .accessibilityIdentifier("RelationshipAddMenu")
    }
}

/// Changes are committed together; dismissing the chooser leaves existing connections intact.
struct ItemRelationshipPicker: View {
    @CurrentLibrary private var library
    let relationship: ItemRelationship
    let candidates: [Item]
    let onSave: ([ItemID]) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: Set<ItemID>
    @State private var rejected = false

    init(relationship: ItemRelationship, candidates: [Item], onSave: @escaping ([ItemID]) -> Bool) {
        self.relationship = relationship
        self.candidates = candidates
        self.onSave = onSave
        _selection = State(initialValue: Set(relationship.targets.compactMap(\.itemID)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(ItemTypeInfo.Field.displayLabel(relationship.label))).interfaceFont(.title2.bold())
            TextField("Search Items", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("RelationshipSearch")
            List(filtered) { candidate in
                Button {
                    if selection.contains(candidate.id) {
                        selection.remove(candidate.id)
                    } else if relationship.allowsMultiple {
                        selection.insert(candidate.id)
                    } else {
                        selection = [candidate.id]
                    }
                } label: {
                    HStack {
                        Image(systemName: selection.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection.contains(candidate.id) ? Color.accentColor : .secondary)
                        VStack(alignment: .leading) {
                            Text(candidate.title)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(LocalizedStringKey(library.catalogue.itemTypes[candidate.type]?.label ?? candidate.type.rawValue))
                                .interfaceFont(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("RelationshipCandidate.\(candidate.id.rawValue)")
                .accessibilityValue(selection.contains(candidate.id) ? "Selected" : "Not Selected")
            }
            .overlay {
                if filtered.isEmpty { ContentUnavailableView.search(text: query) }
            }
            if relationship.targets.contains(where: { $0.itemID == nil }) {
                Text("Unresolved connections will be preserved.")
                    .interfaceFont(.caption).foregroundStyle(.secondary)
            }
            if rejected {
                Text("The connections could not be saved. Your selection has been kept.")
                    .interfaceFont(.callout).foregroundStyle(.red)
            }
            HStack {
                Button("Clear Selection") { selection = [] }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if onSave(selection.sorted { $0.rawValue < $1.rawValue }) { dismiss() } else { rejected = true }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("RelationshipSave")
            }
        }
        .padding(20)
        .frame(width: 440, height: 460)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("RelationshipPicker")
    }

    private var filtered: [Item] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? candidates : candidates.filter { $0.title.localizedStandardContains(query) }
    }
}

#if DEBUG
#Preview("Wrapping Connections") {
    let id = ItemID("10000000-0000-0000-0000-000000000001")
    let names = SampleLibrary.catalogue.edgeTypes
    let parent = ItemRelationship(
        field: "child-of", label: names["parent-of"]?.reverseLabel ?? "", targets: [
            .init(title: "Field Research: review the observations and photographs from every location", itemID: id, resolution: .resolved(id))
        ], isEditable: true, allowsMultiple: false)
    let about = ItemRelationship(
        field: "about", label: names["about"]?.label ?? "", targets: [
            .init(title: "Field notes", itemID: id, resolution: .resolved(id)),
            .init(title: "Interview with the site manager", itemID: nil, resolution: .missing)
        ], isEditable: true, allowsMultiple: true)
    let supersedes = ItemRelationship(field: "supersedes", label: names["supersedes"]?.label ?? "", targets: [], isEditable: true, allowsMultiple: false)
    VStack(alignment: .leading, spacing: 12) {
        ItemRelationshipGroup(relationship: parent, onOpen: { _ in }, onEdit: {}, onRemove: { _ in true })
        ItemRelationshipGroup(relationship: about, onOpen: { _ in }, onEdit: {}, onRemove: { _ in true })
        ItemAddRelationshipButton(options: [supersedes, about], onEdit: { _ in })
    }
    .padding(16)
    .interfaceTextStyle()
    .frame(width: 300)
}
#endif
