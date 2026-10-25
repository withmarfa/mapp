import SwiftUI

/// A relationship as a row of the property sheet: its name, then each item it reaches by title, which opens it. An
/// editable one offers Open, Change or Manage, and Remove from a menu that shows on hover and in the context menu.
struct ItemRelationshipRow: View {
    let relationship: ItemRelationship
    let onOpen: (ItemID) -> Void
    let onEdit: () -> Void
    let onRemove: (ItemID) -> Bool
    @State private var rejected = false

    var body: some View {
        InspectorRow(verbatimName: relationship.label) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(relationship.targets) { target in
                    ItemRelationshipTargetRow(target: target, relationship: relationship, onOpen: onOpen, onEdit: onEdit) { id in
                        rejected = !onRemove(id)
                    }
                    .inspectorMinimumHeight()
                }
                if rejected {
                    Text("The connection could not be removed.")
                        .interfaceFont(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}

/// One item a relationship reaches. The title is the control: plain text until hovered, then filled.
struct ItemRelationshipTargetRow: View {
    let target: ItemRelationshipTarget
    let relationship: ItemRelationship
    let onOpen: (ItemID) -> Void
    let onEdit: () -> Void
    let onRemove: (ItemID) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            ItemTargetRow(target: target, onOpen: onOpen)
            if relationship.isEditable {
                actions
                    .opacity(hovering ? 1 : 0)
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
        if let id = target.itemID {
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

/// The last row of the Relationships section: the relationships the item can still take, each opening the
/// chooser. It offers one only when it is empty or takes several, since a single one that is set is changed from
/// its own row.
struct ItemAddRelationshipRow: View {
    let options: [ItemRelationship]
    let onEdit: (ItemRelationship) -> Void

    var body: some View {
        InspectorAddMenu(title: "Add Relationship…", identifier: "RelationshipAddMenu") {
            ForEach(options) { option in
                Button(ItemTypeInfo.Field.displayLabel(option.label)) { onEdit(option) }
                    .accessibilityIdentifier("RelationshipAdd.\(option.field)")
            }
        }
    }
}

struct ItemTargetRow: View {
    let target: ItemRelationshipTarget
    let onOpen: (ItemID) -> Void

    var body: some View {
        if let id = target.itemID {
            Button { onOpen(id) } label: {
                Text(target.title)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .inspectorValue()
            .accessibilityIdentifier("RelationshipTarget.\(id.rawValue)")
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(target.title)
                    .fixedSize(horizontal: false, vertical: true)
                Label(resolutionLabel, systemImage: "exclamationmark.triangle")
                    .interfaceFont(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
    VStack(alignment: .leading, spacing: 0) {
        ItemRelationshipRow(relationship: parent, onOpen: { _ in }, onEdit: {}, onRemove: { _ in true })
        ItemRelationshipRow(relationship: about, onOpen: { _ in }, onEdit: {}, onRemove: { _ in true })
        ItemAddRelationshipRow(options: [supersedes, about], onEdit: { _ in })
    }
    .padding(16)
    .interfaceTextStyle()
    .frame(width: 300)
}
