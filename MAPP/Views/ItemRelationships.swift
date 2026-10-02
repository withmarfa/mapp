import SwiftUI

struct ItemRelationshipSection: View {
    let relationship: ItemRelationship
    let onOpen: (UUID) -> Void
    let onEdit: () -> Void

    var onRemove: ((UUID) -> Bool)? = nil
    @State private var rejected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(relationship.label))
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if relationship.isEditable {
                    Button(action: onEdit) {
                        Image(systemName: relationship.targets.isEmpty ? "plus" : "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help(relationship.targets.isEmpty ? String(localized: "Add Relationship") : String(localized: "Change Relationship"))
                    .accessibilityLabel(relationship.targets.isEmpty ? "Add Relationship" : "Change Relationship")
                    .accessibilityIdentifier("RelationshipEdit.\(relationship.field)")
                }
            }
            ForEach(relationship.targets) { target in
                HStack(alignment: .top, spacing: 6) {
                    ItemTargetRow(target: target, onOpen: onOpen)
                    if relationship.isEditable {
                        Menu {
                            if let id = target.itemID {
                                Button("Open Item") { onOpen(id) }
                            }
                            Button(relationship.allowsMultiple ? "Manage Connections…" : "Replace…", action: onEdit)
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
                    }
                }
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
    let onOpen: (UUID) -> Void

    var body: some View {
        if let id = target.itemID {
            Button { onOpen(id) } label: {
                HStack {
                    Text(target.title)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("RelationshipTarget.\(id.uuidString)")
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
        case .resolved: String(localized: "Item unavailable")
        }
    }
}

/// Changes are committed together; dismissing the chooser leaves existing connections intact.
struct ItemRelationshipPicker: View {
    let relationship: ItemRelationship
    let candidates: [AppItem]
    let onSave: ([UUID]) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: Set<UUID>
    @State private var rejected = false

    init(relationship: ItemRelationship, candidates: [AppItem], onSave: @escaping ([UUID]) -> Bool) {
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
                            Text(LocalizedStringKey(candidate.type?.label ?? "File"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("RelationshipCandidate.\(candidate.id.uuidString)")
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
                    if onSave(selection.sorted { $0.uuidString < $1.uuidString }) { dismiss() } else { rejected = true }
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

    private var filtered: [AppItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? candidates : candidates.filter { $0.title.localizedStandardContains(query) }
    }
}

#Preview("Wrapping Connections") {
    let id = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    ItemRelationshipSection(
        relationship: .init(field: "child-of", label: "Parent", targets: [
            .init(title: "Field Research: review the observations and photographs from every location", itemID: id, resolution: .resolved(id))
        ], isEditable: true, allowsMultiple: false),
        onOpen: { _ in }, onEdit: {}, onRemove: { _ in true }
    )
    .padding(16)
    .frame(width: 300)
}
