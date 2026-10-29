import MarfaIcons
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
    @AppStorage(PagePlacements.key) private var placements = PagePlacements()

    init(browser: Browser, details: DetailsPresentation) { self.browser = browser; itemID = nil; self.details = details }
    init(itemID: ItemID, details: DetailsPresentation = DetailsPresentation()) { self.itemID = itemID; browser = nil; self.details = details }

    private var selectedID: ItemID? { itemID ?? (browser?.selection.count == 1 ? browser?.selection.first : nil) }

    var body: some View {
        Group {
            if let id = selectedID, let item = library.item(id) {
                let placement = placements.placement(of: item.type, in: library.catalogue)
                let relationships = library.relationships(for: id)
                ItemInspector(
                    item: item,
                    type: library.catalogue.itemTypes[item.type],
                    place: item.tier == .feed ? String(localized: "Inbox") : String(localized: "Library"),
                    catalogue: library.catalogue,
                    hiddenKeys: library.hiddenPropertyKeys(of: item),
                    relationships: relationships,
                    mentions: library.bodyMentions(for: id),
                    onProperty: { key, value in library.setItemProperty(id, key: key, value: value, undoManager: undoManager) },
                    onOpen: open,
                    onEdit: { editing = $0 },
                    onRemove: { relationship, target in
                        library.setItemRelationship(id, field: relationship.field,
                            targetIDs: relationship.targets.compactMap(\.itemID).filter { $0 != target }, undoManager: undoManager)
                    },
                    tags: library.tags(of: item),
                    onAddTag: { library.addTag($0, to: [id], undoManager: undoManager) },
                    onRemoveTag: { library.removeTag($0, from: [id], undoManager: undoManager) },
                    drafts: details,
                    placement: placement,
                    onPlace: PageCustomization.isAvailable(for: item) ? { row, shown in placements.set(shown, row: row, of: item.type) } : nil,
                    drawnByPage: PageCustomization.drawnKeys(of: item, in: library.catalogue),
                    linked: placement.linkedFromPlace == .inspector ? linked(to: item, in: relationships) : [],
                    typeIcon: { target in library.item(target).flatMap { library.catalogue.icon(for: $0.type) } }
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

    /// The items that link to the one shown, newest first. A collection's members are its contents, which stay on
    /// its page.
    private func linked(to item: Item, in relationships: [ItemRelationship]) -> [LinkedItem] {
        LinkedItem.list(
            pointingTo: item.id, in: relationships, catalogue: library.catalogue, now: library.now(),
            members: library.catalogue.isCollection(item.type) ? .excluding : .all, item: { library.item($0) })
    }

    private func open(_ id: ItemID) {
        guard let browser else {
            if library.item(id) != nil { openWindow(value: id) }
            return
        }
        browser.searchText = ""
        browser.sidebarItem = library.item(id).map(browser.place(listing:)) ?? .allNotes
        browser.selection = [id]
        browser.focusRequest = .list
    }
}

/// Inspector content is data-driven and independent of storage, making each item state previewable. It reads as
/// a property sheet: the item's details first, then the type's properties, the item's relationships and tags, and
/// the items that link to it where the person placed that list here. Every section folds. Every property is listed
/// here; a context menu on one says whether the page shows it too.
struct ItemInspector: View {
    @Environment(\.interfaceTextSize) private var textSize
    let item: Item
    /// Nil for a type the catalogue does not hold, which is shown with no fields.
    let type: ItemTypeInfo?
    /// The Inbox or the Library, by the item's tier.
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
    /// The tags the person manages, which exclude the favorite tag, and what adds and removes one. A tag is added
    /// by its text, which the library refuses with the reason.
    var tags: [String] = []
    var onAddTag: (String) -> ItemTag.Refusal? = { _ in nil }
    var onRemoveTag: (String) -> Void = { _ in }
    var drafts: DetailsPresentation? = nil
    /// What the page shows of this type's items, and what changes a row of it. A row not offered a change has no
    /// Show on Page menu.
    var placement: PagePlacement = .standard
    var onPlace: ((String, Bool) -> Void)?
    /// The properties the page's header draws itself, which no choice of where to show them changes.
    var drawnByPage: Set<String> = []
    /// The items that link to this one, when the person placed Linked From in the inspector.
    var linked: [LinkedItem] = []
    /// The icon of the type of the item with this identifier, for the rows that name an item.
    var typeIcon: (ItemID) -> String? = { _ in nil }
    /// Holds what the window keeps for the inspector when no window gives it, as in a preview.
    @State private var ownPresentation = DetailsPresentation()
    /// The empty properties the person has added, and the ones they have edited, which stay listed if cleared.
    /// The host remakes the inspector for another item, which forgets them.
    @State private var revealed: Set<String> = []
    /// The property just added, whose row opens ready to edit.
    @State private var adding: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: InspectorMetrics.sectionGap) {
                if let message = item.problem?.message {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .interfaceFont(.callout).foregroundStyle(.red)
                }
                detailsSection
                if hasProperties { properties }
                if hasRelationships { relationshipSection }
                if hasTags { tagSection }
                if !linked.isEmpty { linkedSection }
            }
            .sharesInspectorNameColumn()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var presentation: DetailsPresentation { drafts ?? ownPresentation }

    /// The change a row's Show on Page menu makes, where the inspector has one to make.
    private func showOnPage(_ row: String) -> ((Bool) -> Void)? {
        if drawnByPage.contains(row) { return nil }
        return onPlace.map { place in { place(row, $0) } }
    }

    // MARK: Sections

    private var properties: some View {
        InspectorSectionView(.properties, title: "Properties") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(fields) { field in
                    ItemPropertyRow(definition: field, value: item.value(of: field.key), isEditable: item.isEditable,
                                    // A property the person has touched stays listed, even once cleared.
                                    onChange: { revealed.insert(field.key); return onProperty(field.key, $0) },
                                    retainedDraft: drafts?.draft(for: item.id, key: field.key),
                                    startsEditing: adding == field.key,
                                    isStatus: field.key == type?.statusField?.key,
                                    shownOnPage: placement.showsOnPage(field.key), onShowOnPage: showOnPage(field.key))
                }
            }
            if !emptyFields.isEmpty {
                InspectorAddMenu(title: "Add Property", identifier: "ItemInspectorAddProperty") {
                    ForEach(emptyFields) { field in
                        Button(field.displayLabel) { add(field) }
                            .accessibilityIdentifier("ItemInspectorAdd.\(field.key)")
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var relationshipSection: some View {
        InspectorSectionView(.relationships, title: "Relationships") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(shownRelationships) { relationship in
                    let group = LinkGroup(item: item.id, field: relationship.field)
                    ItemRelationshipGroup(
                        relationship: relationship, typeIcon: typeIcon, isExpanded: presentation.expandedLinks.contains(group),
                        onShowAll: { presentation.expandLinks(group) }, onOpen: onOpen, onEdit: { onEdit(relationship) },
                        onRemove: { onRemove(relationship, $0) }, shownOnPage: placement.showsOnPage(relationship.field),
                        onShowOnPage: showOnPage(relationship.field))
                }
                if !mentions.isEmpty { contentLinks }
            }
            if !addable.isEmpty {
                ItemAddRelationshipButton(options: addable, onEdit: onEdit)
                    .padding(.top, 4)
            }
        }
    }

    private var contentLinks: some View {
        let group = LinkGroup.content(of: item.id)
        let links = LinkLimit.split(mentions, expanded: presentation.expandedLinks.contains(group))
        return VStack(alignment: .leading, spacing: 0) {
            InspectorSubheading(title: String(localized: "Links in Content"))
            ForEach(links.shown) { target in
                InspectorItemRow(target: target, typeIcon: typeIcon, onOpen: onOpen)
            }
            if links.hidden > 0 {
                ItemShowMoreButton(count: links.hidden, identifier: "ContentLinksShowMore") {
                    presentation.expandLinks(group)
                }
            }
        }
    }

    private var tagSection: some View {
        InspectorSectionView(.tags, title: "Tags") {
            ItemTagsSection(tags: tags, isEditable: item.canEditTags, retainedDraft: drafts?.draft(for: item.id, key: "new-tag"),
                            onAdd: onAddTag, onRemove: onRemoveTag)
        }
        .showOnPageMenu(isShown: placement.showsOnPage(PagePlacement.tags), onChange: showOnPage(PagePlacement.tags))
    }

    private var linkedSection: some View {
        let group = LinkGroup(item: item.id, field: "#linked")
        let links = LinkLimit.split(linked, expanded: presentation.expandedLinks.contains(group))
        return InspectorSectionView(.linkedFrom, title: "Linked From", count: linked.count) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(links.shown, id: \.item) { link in
                    LinkedItemRow(link: link, onOpen: onOpen)
                }
                if links.hidden > 0 {
                    ItemShowMoreButton(count: links.hidden, identifier: "LinkedFromShowMore") {
                        presentation.expandLinks(group)
                    }
                }
            }
        }
        .showOnPageMenu(isShown: false, onChange: showOnPage(PagePlacement.linkedFrom))
    }

    private var detailsSection: some View {
        InspectorSectionView(.details, title: "Details") { details }
    }

    @ViewBuilder private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            detail("Created", ItemDate(date: item.created, hasTime: true).text(), isDate: true)
            detail("Edited", ItemDate(date: item.modified, hasTime: true).text(), isDate: true)
            if let source = item.source { detail("Made by", source) }
            if let place { detail("Place", place) }
            detail("Version", item.version.rawValue.formatted())
            if case .file(let contentType, let byteCount) = item.content {
                detail("Kind", contentType.localizedDescription ?? String(localized: "File"))
                // A server gives a file's size once it holds the bytes, so a file not yet sent has none.
                if byteCount > 0 {
                    detail("Size", ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                }
            }
            ForEach(otherProperties) { property in
                InspectorDetailRow(
                    name: Self.name(of: property.key, label: catalogue.label(ofField: property.key, for: item.type)),
                    value: Self.text(of: property.value), isDate: Self.isDate(property.value))
            }
        }
    }

    private func detail(_ name: LocalizedStringResource, _ value: String, isDate: Bool = false) -> some View {
        InspectorDetailRow(name: String(localized: name), value: value, isDate: isDate)
    }

    // MARK: Contents

    /// The properties that have a value, then any the person added or cleared since the inspector showed this item.
    private var fields: [ItemTypeInfo.Field] {
        InspectorFields.properties(of: item, type: type, hidden: hiddenKeys, revealed: revealed)
    }

    private var emptyFields: [ItemTypeInfo.Field] {
        InspectorFields.addable(of: item, type: type, hidden: hiddenKeys, revealed: revealed)
    }

    private var hasProperties: Bool { !fields.isEmpty || !emptyFields.isEmpty }

    private var hasRelationships: Bool { !shownRelationships.isEmpty || !addable.isEmpty || !mentions.isEmpty }

    /// An item that can take a tag shows the section for adding one; one that can't shows it only if it has tags.
    private var hasTags: Bool { item.canEditTags || !tags.isEmpty }

    private func add(_ field: ItemTypeInfo.Field) {
        withAnimation(.snappy(duration: 0.2)) {
            revealed.insert(field.key)
            adding = field.key
        }
    }

    private var shownRelationships: [ItemRelationship] {
        InspectorFields.relationships(relationships)
    }

    private var addable: [ItemRelationship] {
        relationships.filter { $0.isEditable && ($0.targets.isEmpty || $0.allowsMultiple) }
    }

    private static func isDate(_ value: PropertyValue) -> Bool {
        value.string.flatMap { ItemDate.parse($0) } != nil
    }

    /// A value no field describes, with a date in it read as the fields' dates are.
    private static func text(of value: PropertyValue) -> String {
        if let string = value.string, let date = ItemDate.parse(string) { return date.text() }
        return ItemValueText.string(value)
    }

    /// The catalogue's label for a key, else the key written for reading.
    private static func name(of key: String, label: String?) -> String {
        if let label { return ItemTypeInfo.Field.displayLabel(label) }
        let words = key.split { $0 == "_" || $0 == "-" || $0 == "." }.joined(separator: " ")
        return ItemTypeInfo.Field.displayLabel(words)
    }

    /// Every property the type does not name or show elsewhere, in the order the item holds them.
    private var otherProperties: [Property] {
        var shown = InspectorFields.accountedFor(type: type, hidden: hiddenKeys)
        shown.formUnion(relationships.map(\.field))
        return item.properties.filter { !shown.contains($0.key) }
    }
}

/// A fact about the item in Details: a compact row, with its value cut in the middle where it is long.
private struct InspectorDetailRow: View {
    let name: String
    let value: String
    var isDate = false

    var body: some View {
        InspectorRow(verbatimName: name, isCompact: true) {
            InspectorText(text: value, keepsOneLine: isDate)
        }
        .contextMenu { Button("Copy") { InspectorPasteboard.copy(value) } }
    }
}

/// An item that links to the one shown: a light row with its type's icon and title, and the day it last changed.
private struct LinkedItemRow: View {
    let link: LinkedItem
    let onOpen: (ItemID) -> Void

    var body: some View {
        Button { onOpen(link.item) } label: {
            HStack(spacing: 6) {
                TypeIcon(name: link.icon)
                Text(verbatim: link.title).lineLimit(1)
                Spacer(minLength: 6)
                Text(verbatim: link.date).foregroundStyle(.secondary).lineLimit(1)
                    .interfaceFont(.caption)
            }
            .interfaceFont(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(InspectorRowButtonStyle())
        .foregroundStyle(.primary)
        .help(link.title)
        .accessibilityIdentifier("LinkedFrom.\(link.item.rawValue)")
    }
}
