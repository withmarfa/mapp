import SwiftUI

struct ItemRelationshipSection: View {
    let relationship: ItemRelationship
    let onOpen: (ItemID) -> Void
    let onEdit: () -> Void

    var onRemove: ((ItemID) -> Bool)? = nil
    @State private var rejected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(relationship.label))
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(relationship.targets) { target in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ItemTargetRow(target: target, onOpen: onOpen)
                    if relationship.isEditable {
                        Menu {
                            if let id = target.itemID {
                                Button("Open Item") { onOpen(id) }
                            }
                            Button(relationship.allowsMultiple ? "Manage Connections…" : "Replace…", action: onEdit)
                                .accessibilityIdentifier("RelationshipEdit.\(relationship.field)")
                            if let id = target.itemID, let onRemove {
                                Button("Remove Connection", role: .destructive) { rejected = !onRemove(id) }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel("Connection Actions")
                        .accessibilityIdentifier("RelationshipActions.\(relationship.field).\(target.id)")
                    }
                }
                .padding(.vertical, 4)
            }
            if relationship.isEditable && (relationship.targets.isEmpty || relationship.allowsMultiple) {
                Button(action: onEdit) {
                    Label {
                        Text("Add \(Text(LocalizedStringKey(relationship.label)))…")
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .accessibilityIdentifier("RelationshipAdd.\(relationship.field)")
            }
            if rejected {
                Text("The connection could not be removed.")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("RelationshipTarget.\(id.rawValue)")
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(target.title)
                    .fixedSize(horizontal: false, vertical: true)
                Label(resolutionLabel, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
            Text(LocalizedStringKey(relationship.label)).font(.title2.bold())
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
                                .font(.caption).foregroundStyle(.secondary)
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
                    .font(.caption).foregroundStyle(.secondary)
            }
            if rejected {
                Text("The connections could not be saved. Your selection has been kept.")
                    .font(.callout).foregroundStyle(.red)
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
    VStack(alignment: .leading, spacing: 18) {
        ItemRelationshipSection(
            relationship: .init(field: "child-of", label: "Parent", targets: [
                .init(title: "Field Research: review the observations and photographs from every location", itemID: id, resolution: .resolved(id))
            ], isEditable: true, allowsMultiple: false),
            onOpen: { _ in }, onEdit: {}, onRemove: { _ in true }
        )
        ItemRelationshipSection(
            relationship: .init(field: "about", label: "About", targets: [
                .init(title: "Field notes", itemID: id, resolution: .resolved(id))
            ], isEditable: true, allowsMultiple: true),
            onOpen: { _ in }, onEdit: {}, onRemove: { _ in true }
        )
        ItemRelationshipSection(
            relationship: .init(field: "supersedes", label: "Supersedes", targets: [], isEditable: true, allowsMultiple: false),
            onOpen: { _ in }, onEdit: {}
        )
    }
    .padding(16)
    .frame(width: 300)
}
