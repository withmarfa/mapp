import SwiftUI
import UniformTypeIdentifiers

struct ItemInspectorHost: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    let browser: Browser?
    let itemID: UUID?
    let details: DetailsPresentation
    @State private var editing: ItemRelationship?

    init(browser: Browser, details: DetailsPresentation) { self.browser = browser; itemID = nil; self.details = details }
    init(itemID: UUID, details: DetailsPresentation = DetailsPresentation()) { self.itemID = itemID; browser = nil; self.details = details }

    private var selectedID: UUID? { itemID ?? (browser?.selection.count == 1 ? browser?.selection.first : nil) }

    var body: some View {
        Group {
            if let id = selectedID, let item = library.item(id) {
                ItemInspector(
                    item: item,
                    relationships: library.relationships(for: id),
                    mentions: library.bodyMentions(for: id),
                    onProperty: { key, value in library.setItemProperty(id, key: key, value: value, undoManager: undoManager) },
                    onOpen: open,
                    onEdit: { editing = $0 },
                    onRemove: { relationship, target in
                        library.setItemRelationship(id, field: relationship.field,
                            targetIDs: relationship.targets.compactMap(\.itemID).filter { $0 != target }, undoManager: undoManager)
                    },
                    drafts: details
                )
                .id(id)
            } else {
                ContentUnavailableView("No Item Selected", systemImage: "sidebar.right")
            }
        }
        .sheet(item: $editing) { relationship in
            if let id = selectedID {
                ItemRelationshipPicker(relationship: relationship, candidates: library.relationshipCandidates(for: id, field: relationship.field)) {
                    library.setItemRelationship(id, field: relationship.field, targetIDs: $0, undoManager: undoManager)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ItemInspector")
    }

    private func open(_ id: UUID) {
        guard let browser else {
            if let path = library.item(id)?.projection.filePath { openWindow(value: path) }
            return
        }
        browser.searchText = ""
        browser.sidebarItem = .allNotes
        browser.selection = [id]
        browser.focusRequest = .list
    }
}

/// Inspector content is data-driven and independent of storage, making each item state previewable.
struct ItemInspector: View {
    let item: AppItem
    let relationships: [ItemRelationship]
    let mentions: [ItemRelationshipTarget]
    let onProperty: (String, NoteFieldValue?) -> Bool
    let onOpen: (UUID) -> Void
    let onEdit: (ItemRelationship) -> Void
    var onRemove: ((ItemRelationship, UUID) -> Bool)? = nil
    var drafts: DetailsPresentation? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Type") {
                        if let type = item.type { Text(LocalizedStringKey(type.label)) }
                        else { Text(item.projection.declaredType ?? String(localized: "File")) }
                    }
                    .font(.callout)
                    if let message = item.validationMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.red)
                    }
                }
                if !item.properties.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(item.properties) { property in
                            ItemPropertyRow(definition: property, value: item.fields[property.key], isEditable: item.isEditable,
                                            onChange: { onProperty(property.key, $0) }, retainedDraft: drafts?.draft(for: item.id, key: property.key))
                        }
                    }
                }
                if relationships.contains(where: { !$0.targets.isEmpty || $0.isEditable }) {
                    Divider()
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(relationships.filter { !$0.targets.isEmpty || $0.isEditable }) { relationship in
                            ItemRelationshipSection(relationship: relationship, onOpen: onOpen, onEdit: { onEdit(relationship) },
                                onRemove: onRemove.map { remove in { target in remove(relationship, target) } })
                        }

                    }
                }
                if !mentions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Links in Content").font(.subheadline).foregroundStyle(.secondary)
                        ForEach(mentions) { target in
                            ItemTargetRow(target: target, onOpen: onOpen)
                                .padding(.vertical, 5)
                        }
                        Text("These links come from the document text.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !otherFields.isEmpty {
                    DisclosureGroup("Other Properties") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(otherFields, id: \.self) { key in
                                LabeledContent(key, value: ItemValueText.string(item.fields[key]!))
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                if let path = item.projection.filePath {
                    Divider()
                    DisclosureGroup("File") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(path).font(.caption).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let file = item.file {
                                LabeledContent("Kind", value: file.contentType.localizedDescription ?? String(localized: "File"))
                                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: file.stored.byteCount, countStyle: .file))
                                LabeledContent("Created", value: file.stored.created.formatted(date: .abbreviated, time: .shortened))
                                LabeledContent("Modified", value: file.stored.modified.formatted(date: .abbreviated, time: .shortened))
                                Text("File properties cannot be edited in this file-backed library.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                        .padding(.top, 8)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var otherFields: [String] {
        let displayed = Set(item.properties.map(\.key) + item.relationshipFields + ["title", "type", "marfa_id", "marfa_version"])
        return item.fields.keys.filter { !displayed.contains($0) }.sorted()
    }
}
