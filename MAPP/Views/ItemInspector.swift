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
                    place: Self.place(of: item, in: library),
                    catalogue: library.catalogue,
                    hiddenKeys: library.hiddenPropertyKeys(of: item),
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
                // The page beside it already says that nothing is selected.
                Color.clear
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

    /// Where the item is kept: a folder of the notes folder, or the Inbox; for a Marfa item, its tier.
    private static func place(of item: Item, in library: any ItemLibrary) -> String {
        if library.path(of: item.id) != nil {
            return library.folder(of: item)?.name ?? String(localized: "Inbox")
        }
        return item.tier == .feed ? String(localized: "Inbox") : String(localized: "Library")
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

/// Inspector content is data-driven and independent of storage, making each item state previewable. It reads as
/// a property sheet: the type's properties, the item's relationships, then its details, folded away until asked
/// for.
struct ItemInspector: View {
    @Environment(\.interfaceTextSize) private var textSize
    let item: Item
    /// Nil for a type the catalogue does not hold, which is shown with no fields.
    let type: ItemTypeInfo?
    /// Where the item is kept, for a library of files.
    var path: String? = nil
    /// The folder, the Inbox or the Library the item is in.
    var place: String? = nil
    /// Calls a property the item's type does not define by the label another type gives it.
    var catalogue = Catalogue()
    /// The item's property keys that are not listed: the title, the text, and any the library keeps for itself.
    var hiddenKeys: Set<String> = []
    let relationships: [ItemRelationship]
    let mentions: [ItemRelationshipTarget]
    let onProperty: (String, PropertyValue?) -> Bool
    let onOpen: (ItemID) -> Void
    let onEdit: (ItemRelationship) -> Void
    let onRemove: (ItemRelationship, ItemID) -> Bool
    var drafts: DetailsPresentation? = nil
    @State private var detailsOpen = false
    /// The empty properties the person has added, and the ones they have edited, which stay listed if cleared.
    /// The host remakes the inspector for another item, which forgets them.
    @State private var revealed: Set<String> = []
    /// The property just added, whose row opens ready to edit.
    @State private var adding: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let message = item.problem?.message {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .interfaceFont(.callout).foregroundStyle(.red)
                        .padding(.vertical, 8)
                }
                if hasProperties {
                    InspectorHeading(title: "Properties", topPadding: 2)
                    ForEach(fields) { field in
                        ItemPropertyRow(definition: field, value: item.value(of: field.key), isEditable: item.isEditable,
                                        // A property the person has touched stays listed, even once cleared.
                                        onChange: { revealed.insert(field.key); return onProperty(field.key, $0) },
                                        retainedDraft: drafts?.draft(for: item.id, key: field.key),
                                        startsEditing: adding == field.key)
                    }
                    if !emptyFields.isEmpty {
                        InspectorAddMenu(title: "Add Property", identifier: "ItemInspectorAddProperty") {
                            ForEach(emptyFields) { field in
                                Button(field.displayLabel) { add(field) }
                                    .accessibilityIdentifier("ItemInspectorAdd.\(field.key)")
                            }
                        }
                    }
                }
                if hasRelationships {
                    if hasProperties { InspectorSectionDivider() }
                    InspectorHeading(title: "Relationships", topPadding: hasProperties ? 10 : 2)
                    ForEach(shownRelationships) { relationship in
                        ItemRelationshipRow(relationship: relationship, onOpen: onOpen, onEdit: { onEdit(relationship) },
                                            onRemove: { onRemove(relationship, $0) })
                    }
                    if !mentions.isEmpty {
                        InspectorRow(name: "Links in Content") {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(mentions) { target in
                                    ItemTargetRow(target: target, onOpen: onOpen)
                                        .inspectorMinimumHeight()
                                }
                            }
                        }
                    }
                    if !addable.isEmpty {
                        ItemAddRelationshipRow(options: addable, onEdit: onEdit)
                    }
                }
                if hasProperties || hasRelationships { InspectorSectionDivider() }
                detailsHeading
                if detailsOpen { details }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// The properties that have a value, then any the person added or cleared since the inspector showed this item.
    private var fields: [ItemTypeInfo.Field] {
        InspectorFields.properties(of: item, type: type, hidden: hiddenKeys, revealed: revealed)
    }

    private var emptyFields: [ItemTypeInfo.Field] {
        InspectorFields.addable(of: item, type: type, hidden: hiddenKeys, revealed: revealed)
    }

    private var hasProperties: Bool { !fields.isEmpty || !emptyFields.isEmpty }

    private var hasRelationships: Bool { !shownRelationships.isEmpty || !addable.isEmpty || !mentions.isEmpty }

    private func add(_ field: ItemTypeInfo.Field) {
        withAnimation(.snappy(duration: 0.2)) {
            revealed.insert(field.key)
            adding = field.key
        }
    }

    private var shownRelationships: [ItemRelationship] {
        relationships.filter { !$0.targets.isEmpty }
    }

    private var addable: [ItemRelationship] {
        relationships.filter { $0.isEditable && ($0.targets.isEmpty || $0.allowsMultiple) }
    }

    private var detailsHeading: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { detailsOpen.toggle() }
        } label: {
            HStack(spacing: 4) {
                Text("Details")
                Image(systemName: "chevron.right")
                    .font(.system(size: 9 * InterfaceStyle.scale(for: textSize), weight: .bold))
                    .rotationEffect(.degrees(detailsOpen ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .interfaceFont(.subheadline.bold())
            .foregroundStyle(.secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.top, hasProperties || hasRelationships ? 10 : 2)
        .padding(.bottom, 6)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(detailsOpen ? Text("Expanded") : Text("Collapsed"))
        .accessibilityIdentifier("ItemInspectorDetails")
    }

    @ViewBuilder private var details: some View {
        detail("Created", item.created.formatted(date: .abbreviated, time: .shortened))
        detail("Edited", item.modified.formatted(date: .abbreviated, time: .shortened))
        if let source = item.source { detail("Made by", source) }
        if let place { detail("Place", place) }
        // Only a server counts an item's versions; a file has no such number.
        if path == nil { detail("Version", item.version.rawValue.formatted()) }
        if case .file(let contentType, let byteCount) = item.content {
            detail("Kind", contentType.localizedDescription ?? String(localized: "File"))
            // A server gives a file's size once it holds the bytes, so a file not yet sent has none.
            if path != nil || byteCount > 0 {
                detail("Size", ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
            }
        }
        if let path { detail("Path", path) }
        ForEach(otherProperties) { property in
            InspectorRow(name: Self.name(of: property.key, label: catalogue.label(ofField: property.key, for: item.type))) {
                Text(ItemValueText.string(property.value))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func detail(_ name: LocalizedStringKey, _ value: String) -> some View {
        InspectorRow(name: name) {
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The catalogue's label for a key, else the key written for reading.
    private static func name(of key: String, label: String?) -> LocalizedStringKey {
        if let label { return LocalizedStringKey(ItemTypeInfo.Field.displayLabel(label)) }
        let words = key.split { $0 == "_" || $0 == "-" || $0 == "." }.joined(separator: " ")
        return LocalizedStringKey(ItemTypeInfo.Field.displayLabel(words))
    }

    /// Every property the type does not name or show elsewhere, in the order the item holds them. A source that
    /// keeps no tags field still shows the item's tags among them.
    private var otherProperties: [Property] {
        var shown = InspectorFields.accountedFor(type: type, hidden: hiddenKeys)
        shown.formUnion(relationships.map(\.field))
        var properties = item.properties.filter { !shown.contains($0.key) }
        if !item.tags.isEmpty && item.value(of: "tags") == nil {
            properties.append(Property(key: "tags", value: .array(item.tags.sorted().map(PropertyValue.string))))
        }
        return properties
    }
}
