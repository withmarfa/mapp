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
                    otherLabels: Self.labels(in: library.catalogue),
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

    /// Where the item is kept: a folder of the notes folder, or the Inbox; for a Marfa item, its tier.
    private static func place(of item: Item, in library: any ItemLibrary) -> String {
        if library.path(of: item.id) != nil {
            return library.folder(of: item)?.name ?? String(localized: "Inbox")
        }
        return item.tier == .feed ? String(localized: "Inbox") : String(localized: "Library")
    }

    /// Every property key the catalogue names, so one the item's type does not define is still called by its label.
    private static func labels(in catalogue: Catalogue) -> [String: String] {
        var labels: [String: String] = [:]
        for type in catalogue.itemTypes.values {
            for field in type.fields where labels[field.key] == nil { labels[field.key] = field.label }
        }
        return labels
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
    /// The catalogue's labels by property key, for properties the item's type does not define.
    var otherLabels: [String: String] = [:]
    let relationships: [ItemRelationship]
    let mentions: [ItemRelationshipTarget]
    let onProperty: (String, PropertyValue?) -> Bool
    let onOpen: (ItemID) -> Void
    let onEdit: (ItemRelationship) -> Void
    var onRemove: ((ItemRelationship, ItemID) -> Bool)? = nil
    var drafts: DetailsPresentation? = nil
    @State private var detailsOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let message = item.problem?.message {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .interfaceFont(.callout).foregroundStyle(.red)
                        .padding(.vertical, 8)
                }
                if !fields.isEmpty {
                    InspectorHeading(title: "Properties", topPadding: 2)
                    ForEach(fields) { field in
                        ItemPropertyRow(definition: field, value: item.value(of: field.key), isEditable: item.isEditable,
                                        onChange: { onProperty(field.key, $0) }, retainedDraft: drafts?.draft(for: item.id, key: field.key))
                    }
                }
                if !shownRelationships.isEmpty || !addable.isEmpty || !mentions.isEmpty {
                    InspectorHeading(title: "Relationships", topPadding: fields.isEmpty ? 2 : 18)
                    ForEach(shownRelationships) { relationship in
                        ItemRelationshipRow(relationship: relationship, onOpen: onOpen, onEdit: { onEdit(relationship) },
                                            onRemove: onRemove.map { remove in { target in remove(relationship, target) } })
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

    private var fields: [ItemTypeInfo.Field] { InspectorFields.properties(of: item, type: type) }

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
            }
            .interfaceFont(.subheadline.bold())
            .foregroundStyle(.secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.top, 18)
        .padding(.bottom, 6)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(detailsOpen ? Text("Expanded") : Text("Collapsed"))
        .accessibilityIdentifier("ItemInspectorDetails")
    }

    @ViewBuilder private var details: some View {
        detail("Created", item.created.formatted(date: .abbreviated, time: .shortened))
        detail("Edited", item.modified.formatted(date: .abbreviated, time: .shortened))
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
            InspectorRow(name: Self.name(of: property.key, labels: otherLabels)) {
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
    private static func name(of key: String, labels: [String: String]) -> LocalizedStringKey {
        if let label = labels[key] { return LocalizedStringKey(label) }
        let words = key.split { $0 == "_" || $0 == "-" || $0 == "." }.joined(separator: " ")
        return LocalizedStringKey(words.prefix(1).uppercased() + words.dropFirst())
    }

    /// Every property the type does not name or show elsewhere, in the order the item holds them. A source that
    /// keeps no tags field still shows the item's tags among them.
    private var otherProperties: [Property] {
        var shown = InspectorFields.accountedFor(item: item, type: type)
        shown.formUnion(relationships.map(\.field))
        var properties = item.properties.filter { !shown.contains($0.key) }
        if !item.tags.isEmpty && item.value(of: "tags") == nil {
            properties.append(Property(key: "tags", value: .array(item.tags.sorted().map(PropertyValue.string))))
        }
        return properties
    }
}
