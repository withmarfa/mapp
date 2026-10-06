import SwiftUI
import UniformTypeIdentifiers

struct ItemInspectorHost: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    let browser: Browser?
    let itemID: ItemID?
    let details: DetailsPresentation
    @State private var editing: ItemRelationship?

    init(browser: Browser, details: DetailsPresentation) { self.browser = browser; itemID = nil; self.details = details }
    init(itemID: ItemID, details: DetailsPresentation = DetailsPresentation()) { self.itemID = itemID; browser = nil; self.details = details }

    private var selectedID: ItemID? { itemID ?? (browser?.selection.count == 1 ? browser?.selection.first : nil) }

    var body: some View {
        Group {
            if let id = selectedID, let item = library.item(id) {
                ItemInspector(
                    item: item,
                    type: library.catalogue.itemTypes[item.type],
                    path: library.path(of: id),
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

    private func open(_ id: ItemID) {
        guard let browser else {
            if library.item(id) != nil { openWindow(value: id) }
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
    let item: Item
    /// Nil for a type the catalogue does not hold, which is shown by its name with no fields.
    let type: ItemTypeInfo?
    /// Where the item is kept, for a library of files.
    var path: String? = nil
    let relationships: [ItemRelationship]
    let mentions: [ItemRelationshipTarget]
    let onProperty: (String, PropertyValue?) -> Bool
    let onOpen: (ItemID) -> Void
    let onEdit: (ItemRelationship) -> Void
    var onRemove: ((ItemRelationship, ItemID) -> Bool)? = nil
    var drafts: DetailsPresentation? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Type") {
                        if let type { Text(LocalizedStringKey(type.label)) }
                        else { Text(item.type.rawValue) }
                    }
                    .font(.callout)
                    if let message = item.problem?.message {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.red)
                    }
                }
                if let fields = type?.fields, !fields.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(fields) { field in
                            ItemPropertyRow(definition: field, value: item.value(of: field.key), isEditable: item.isEditable,
                                            onChange: { onProperty(field.key, $0) }, retainedDraft: drafts?.draft(for: item.id, key: field.key))
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
                if !otherProperties.isEmpty {
                    DisclosureGroup("Other Properties") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(otherProperties) { property in
                                LabeledContent(property.key, value: ItemValueText.string(property.value))
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                if path != nil || item.isFile {
                    Divider()
                    DisclosureGroup("File") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let path {
                                Text(path).font(.caption).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if case .file(let contentType, let byteCount) = item.content {
                                LabeledContent("Kind", value: contentType.localizedDescription ?? String(localized: "File"))
                                // A server gives a file's size once it holds the bytes, so a file not yet sent has none.
                                if path != nil || byteCount > 0 {
                                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                                }
                                LabeledContent("Created", value: item.created.formatted(date: .abbreviated, time: .shortened))
                                LabeledContent("Modified", value: item.modified.formatted(date: .abbreviated, time: .shortened))
                                if path != nil {
                                    Text("File properties cannot be edited in this file-backed library.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
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

    /// Every property the type does not name or show elsewhere, in the order the item holds them. A source that
    /// keeps no tags field still shows the item's tags among them.
    private var otherProperties: [Property] {
        var shown = Set((type?.fields ?? []).map(\.key) + ["title", "type", "marfa_id", "marfa_version"])
        shown.formUnion(relationships.map(\.field))
        var properties = item.properties.filter { !shown.contains($0.key) }
        if !item.tags.isEmpty && item.value(of: "tags") == nil {
            properties.append(Property(key: "tags", value: .array(item.tags.sorted().map(PropertyValue.string))))
        }
        return properties
    }
}
