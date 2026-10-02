import SwiftUI

struct ItemRelationshipSection: View {
    let relationship: ItemRelationship
    let onOpen: (UUID) -> Void
    let onEdit: () -> Void

    var body: some View {
        Section {
            if relationship.targets.isEmpty {
                Text("Not Set").foregroundStyle(.secondary)
            } else {
                ForEach(relationship.targets) { target in
                    ItemTargetRow(target: target, onOpen: onOpen)
                }
            }
            if relationship.isEditable {
                Button("Edit…", action: onEdit)
                    .accessibilityIdentifier("RelationshipEdit.\(relationship.field)")
            }
        } header: {
            Text(LocalizedStringKey(relationship.label))
        }
    }
}

struct ItemTargetRow: View {
    let target: ItemRelationshipTarget
    let onOpen: (UUID) -> Void

    var body: some View {
        if let id = target.itemID {
            Button { onOpen(id) } label: {
                HStack {
                    Text(target.title).multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("RelationshipTarget.\(id.uuidString)")
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(target.title)
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
