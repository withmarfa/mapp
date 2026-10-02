import SwiftUI

/// The page owns its title; the inspector is reserved for the rest of the item's details.
struct ItemPageHeader: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    let item: AppItem
    let drafts: DetailsPresentation
    let onStartWriting: () -> Void
    @FocusState private var titleFocused: Bool
    @State private var editingParent = false
    @State private var propertyError = false
    @StoredPageStyle private var style

    private var titleDraft: ItemPropertyDraft { drafts.draft(for: item.id, key: "title") }
    private var parent: ItemRelationship? { library.relationships(for: item.id).first { $0.field == "child-of" } }
    private var status: ItemPropertyDefinition? { item.properties.first { $0.key == "status" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Untitled", text: Binding {
                titleDraft.isDirty ? titleDraft.text : item.title
            } set: {
                titleDraft.text = $0
                titleDraft.isDirty = true
                titleDraft.rejected = false
            }, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: CGFloat(style.textSize) * 1.9, weight: .bold))
            .foregroundStyle(.primary)
            .lineLimit(1...6)
            .focused($titleFocused)
            .disabled(!item.isEditable)
            .accessibilityLabel("Title")
            .accessibilityIdentifier("ItemPageTitle")
            .onSubmit { if commitTitle() { onStartWriting() } }
            .onChange(of: titleFocused) { if !titleFocused { _ = commitTitle() } }
            if titleDraft.rejected {
                Text("The title could not be saved. Use a unique file name without slashes or line breaks.")
                    .font(.caption).foregroundStyle(.red)
                Button("Discard Changes") { titleDraft.isDirty = false; titleDraft.rejected = false }
                    .font(.caption)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 8) { chips }
                VStack(alignment: .leading, spacing: 8) { chips }
            }
            if propertyError {
                Text("The value could not be saved. Please try again.")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear { _ = commitTitle() }
        .popover(isPresented: $editingParent) {
            if let parent {
                ItemRelationshipPicker(relationship: parent, candidates: library.relationshipCandidates(for: item.id, field: parent.field)) {
                    library.setItemRelationship(item.id, field: parent.field, targetIDs: $0, undoManager: undoManager)
                }
            }
        }
    }

    @ViewBuilder private var chips: some View {
        if let type = item.type {
            Text(LocalizedStringKey(type.label))
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(.quaternary, in: .capsule)
                .help("Item Type")
        }
        if let status, case .choice(let choices) = status.kind {
            Menu {
                ForEach(choices, id: \.self) { choice in
                    Button {
                        propertyError = !library.setItemProperty(item.id, key: status.key, value: .string(choice), undoManager: undoManager)
                    } label: {
                        if item.fields[status.key]?.string == choice {
                            Label(LocalizedStringKey(ItemPropertyRow.choiceLabel(choice)), systemImage: "checkmark")
                        } else {
                            Text(LocalizedStringKey(ItemPropertyRow.choiceLabel(choice)))
                        }
                    }
                }
            } label: {
                Label((item.fields[status.key]?.string).map(ItemPropertyRow.choiceLabel) ?? String(localized: "Set Status"), systemImage: "circle.lefthalf.filled")
            }
            .menuStyle(.borderlessButton).fixedSize()
            .font(.caption).padding(.horizontal, 9).padding(.vertical, 5)
            .background(.quaternary, in: .capsule)
            .disabled(!item.isEditable)
            .accessibilityIdentifier("ItemStatusChip")
            .accessibilityLabel("Status")
        }
        if let parent {
            Menu {
                if let target = parent.targets.first, let id = target.itemID,
                   let path = library.item(id)?.projection.filePath {
                    Button("Open Parent") { openWindow(value: path) }
                }
                Button(parent.targets.isEmpty ? "Choose Parent…" : "Change Parent…") { editingParent = true }
                    .disabled(!parent.isEditable)
            } label: {
                Label(parent.targets.first?.title ?? String(localized: "Add Parent"), systemImage: "square.stack")
                    .lineLimit(2).multilineTextAlignment(.leading)
            }
            .menuStyle(.borderlessButton)
            .font(.caption).padding(.horizontal, 9).padding(.vertical, 5)
            .background(.quaternary, in: .rect(cornerRadius: 10))
            .accessibilityIdentifier("ItemParentChip")
        }
    }

    @discardableResult private func commitTitle() -> Bool {
        guard titleDraft.isDirty, item.isEditable else { return !titleDraft.rejected }
        let title = titleDraft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        titleDraft.rejected = !library.setItemProperty(item.id, key: "title", value: .string(title), undoManager: undoManager)
        if !titleDraft.rejected { titleDraft.isDirty = false }
        return !titleDraft.rejected
    }
}

#if DEBUG
#Preview("Editable Page Header") {
    let library = ItemPreviewFixtures.library
    ItemPageHeader(item: library.item(ItemPreviewFixtures.ticketID)!, drafts: DetailsPresentation(), onStartWriting: {})
        .environment(library)
        .padding(24)
        .frame(width: 620)
}

#Preview("Long Title and Narrow Page") {
    let library = ItemPreviewFixtures.library
    let _ = library.setItemProperty(ItemPreviewFixtures.ticketID, key: "title", value: .string("Review the field observations and decide which findings belong in the final report"))
    ItemPageHeader(item: library.item(ItemPreviewFixtures.ticketID)!, drafts: DetailsPresentation(), onStartWriting: {})
        .environment(library)
        .padding(24)
        .frame(width: 380)
}
#endif
