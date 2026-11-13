import Marfa
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
    /// The page beside the sidebar, which lists the headings of the note on it and goes to one, for the Outline section.
    /// Nil where no page is beside the sidebar, and the Outline then has no rows.
    var editor: EditorController?
    @State private var editing: ItemRelationship?
    @AppStorage(PagePlacements.key) private var placements = PagePlacements()
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard

    init(browser: Browser, details: DetailsPresentation, editor: EditorController? = nil) {
        self.browser = browser; itemID = nil; self.details = details; self.editor = editor
    }
    init(itemID: ItemID, details: DetailsPresentation = DetailsPresentation(), editor: EditorController? = nil) {
        self.itemID = itemID; browser = nil; self.details = details; self.editor = editor
    }

    private var selectedID: ItemID? { itemID ?? (browser?.selection.count == 1 ? browser?.selection.first : nil) }

    var body: some View {
        Group {
            if let browser, details.isEditingView, let panel = browser.viewPanel {
                ViewEditPanel(browser: browser, panel: panel)
                    .onExitCommand { browser.escapeViewPanel(in: library) }
            } else if let id = selectedID, let item = library.item(id), details.isCustomizingLayout, PageCustomization.isAvailable(for: item) {
                ItemLayoutPanel(item: item, outline: editor?.headings(of: id) ?? [])
                    .onExitCommand { details.endLayout() }
            } else if let id = selectedID, let item = library.item(id) {
                let placement = placements.placement(of: item.type, in: library.catalogue)
                let relationships = library.relationships(for: id)
                let sections = placement.sidebarSections.compactMap(SidebarSection.init(id:))
                let outline = editor?.headings(of: id) ?? []
                ItemInspector(
                    item: item,
                    type: library.catalogue.itemTypes[item.type],
                    place: item.tier == .feed ? String(localized: "Inbox") : String(localized: "Library"),
                    source: item.source.map { library.sources.info($0) },
                    catalogue: library.catalogue,
                    hiddenKeys: library.hiddenPropertyKeys(of: item),
                    relationships: relationships,
                    mentions: library.bodyMentions(for: id),
                    onProperty: { key, value in library.setItemProperty(id, key: key, value: value, undoManager: undoManager) },
                    isWritingProperties: { library.isWritingProperties(of: id) },
                    onOpen: open,
                    onEdit: { editing = $0 },
                    onRemove: { relationship, target in
                        await library.changeItemRelationship(id, field: relationship.field, adding: [], removing: [target], undoManager: undoManager)
                    },
                    tags: library.tags(of: item),
                    onRemoveTag: { library.removeTag($0, from: [id], undoManager: undoManager) },
                    drafts: details,
                    placement: placement,
                    onPlace: PageCustomization.isAvailable(for: item) ? { row, shown in placements.set(shown, row: row, of: item.type, in: library.catalogue) } : nil,
                    drawnByPage: PageCustomization.drawnKeys(of: item, in: library.catalogue),
                    linked: placement.linkedFromPlace == .inspector ? linked(to: item, in: relationships) : [],
                    typeIcon: { target in library.item(target).flatMap { library.catalogue.icon(for: $0.type) } },
                    sections: sections,
                    extras: SidebarExtras.of(item, in: library, relationships: relationships, sections: sections, outline: outline),
                    onHeading: { editor?.revealHeading(at: $0) }
                )
                .id(id)
            } else {
                // The page beside it already says that nothing is selected.
                Color.clear
            }
        }
        .sheet(item: $editing) { relationship in
            if let id = selectedID {
                ItemRelationshipPicker(owner: id, relationship: relationship, candidates: library.relationshipCandidates(for: id, field: relationship.field)) {
                    await library.changeItemRelationship(id, field: relationship.field, adding: $0, removing: $1, undoManager: undoManager)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ItemInspector")
    }

    /// The items that link to the one shown, newest first. A collection's members are its contents, which stay on
    /// its page.
    private func linked(to item: Item, in relationships: [ItemRelationship]) -> [LinkedItem] {
        Self.linked(to: item, in: relationships, library: library, format: dateFormat)
    }

    static func linked(to item: Item, in relationships: [ItemRelationship], library: any ItemLibrary, format: DateFormat) -> [LinkedItem] {
        LinkedItem.list(
            pointingTo: item.id, in: relationships, catalogue: library.catalogue, now: library.now(), format: format,
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
/// a property sheet: the item's details first, as cells, then the type's properties, the item's relationships, the
/// links in its page, the items that link to it (where the person placed that list here) and tags. Every section
/// folds. Every property is listed
/// here; a context menu on one says whether the page shows it too.
struct ItemInspector: View {
    @Environment(\.interfaceTextSize) private var textSize
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    @AppStorage(PageKey.showsCoordinates) private var showsCoordinates = false
    let item: Item
    /// Nil for a type the catalogue does not hold, which is shown with no fields.
    let type: ItemTypeInfo?
    /// The Inbox or the Library, by the item's tier.
    var place: String? = nil
    /// The source that made the item, as the server names it; the code stands in until it has.
    var source: SourceInfo? = nil
    /// Calls a property the item's type does not define by the label another type gives it.
    var catalogue = Catalogue()
    /// The item's property keys that are not listed: the title, the text, and any the library keeps for itself.
    var hiddenKeys: Set<String> = []
    let relationships: [ItemRelationship]
    let mentions: [ItemRelationshipTarget]
    let onProperty: (String, PropertyValue?) -> Bool
    /// Whether an edit of the item's properties is still on its way into the library, read only for a list of
    /// entries, which waits for it.
    var isWritingProperties: () -> Bool = { false }
    let onOpen: (ItemID) -> Void
    let onEdit: (ItemRelationship) -> Void
    let onRemove: (ItemRelationship, ItemID) async -> Bool
    /// The tags the person manages, which exclude the favorite tag, and what removes one. Tags are added in the value
    /// editor, which reaches the library itself.
    var tags: [String] = []
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
    /// The sections to list, in order: the person's arrangement for the item's type. A section with nothing to show for
    /// this item is left out of what is drawn but keeps its place in the arrangement.
    var sections: [SidebarSection] = SidebarSection.defaults
    /// What the outline, attachments, collections and app sections hold for this item.
    var extras = SidebarExtras()
    /// Goes to a heading of the item's text.
    var onHeading: (Int) -> Void = { _ in }
    /// Holds what the window keeps for the inspector when no window gives it, as in a preview.
    @State private var ownPresentation = DetailsPresentation()
    /// The empty properties the person has added, and the ones they have edited, which stay listed if cleared.
    /// The host remakes the inspector for another item, which forgets them.
    @State private var revealed: Set<String> = []
    /// The property just added, whose row opens ready to edit.
    @State private var adding: String?
    /// Where the Tags heading's plus opens the tag editor.
    @State private var tagAnchor = ValueEditAnchorBox()
    @Environment(\.library) private var library
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: InspectorMetrics.sectionGap) {
                if let message = item.problem?.message {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .interfaceFont(.callout).foregroundStyle(.red)
                }
                if item.readOnly {
                    Label("Read only. A connector manages this item, so changes made here would be overwritten.", systemImage: "lock")
                        .interfaceFont(.callout).foregroundStyle(.secondary)
                }
                ForEach(sections, id: \.id) { section in
                    switch section {
                    case .details: detailsSection
                    case .properties: if hasProperties { properties }
                    case .relationships: if hasRelationships { relationshipSection }
                    case .linksInPage: if !mentions.isEmpty { linksInPageSection }
                    case .linkedFrom: if !linked.isEmpty { linkedFromSection }
                    case .tags: if hasTags { tagSection }
                    case .outline: if !extras.outline.isEmpty { outlineSection }
                    case .attachments: if !extras.attachments.isEmpty { itemsSection(.attachments, title: "Attachments", targets: extras.attachments) }
                    case .collections: if !extras.collections.isEmpty { itemsSection(.collections, title: "Collections", targets: extras.collections) }
                    case .app:
                        if let app = extras.apps.first(where: { $0.section == section }) { appSection(app) }
                    }
                }
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
        InspectorSectionView(.properties, title: "Properties", count: entries.count,
                             placeholder: entries.isEmpty ? "No Properties" : nil, add: { hovering in
            if !emptyFields.isEmpty || offersLocation {
                InspectorPlusMenu(accessibilityLabel: "Add Property", identifier: "ItemInspectorAddProperty", isRowHovered: hovering) {
                    if offersLocation {
                        Button("Location") { addLocation() }
                            .accessibilityIdentifier("ItemInspectorAdd.location")
                    }
                    ForEach(emptyFields) { field in
                        Button(field.label) { add(field) }
                            .accessibilityIdentifier("ItemInspectorAdd.\(field.key)")
                    }
                }
            }
        }) {
            ForEach(entries) { entry in
                switch entry {
                case .location(let spec):
                    ItemLocationRow(
                        spec: spec, item: item, shownOnPage: placement.showsOnPage(ItemLocation.rowID),
                        onShowOnPage: showOnPage(ItemLocation.rowID), startsEditing: adding == ItemLocation.rowID)
                case .field(let field):
                    ItemPropertyRow(definition: field, value: item.value(of: field.key), isEditable: item.isEditable,
                                    // A property the person has touched stays listed, even once cleared.
                                    onChange: { revealed.insert(field.key); return onProperty(field.key, $0) },
                                    item: item.id,
                                    retainedDraft: drafts?.draft(for: item.id, key: field.key),
                                    startsEditing: adding == field.key,
                                    // The window holds the draft, so folding this section does not give it back.
                                    handsOffOnLeave: drafts == nil,
                                    shownOnPage: placement.showsOnPage(field.key), onShowOnPage: showOnPage(field.key),
                                    isWriting: field.kind.isList && isWritingProperties())
                }
            }
        }
    }

    private var relationshipSection: some View {
        InspectorSectionView(.relationships, title: "Relationships", count: relationshipCount,
                             placeholder: relationshipCount == 0 ? "No Relationships" : nil, boxed: false, add: { hovering in
            if !addable.isEmpty {
                InspectorPlusMenu(accessibilityLabel: "Add Relationship", identifier: "RelationshipAddMenu", isRowHovered: hovering) {
                    ForEach(addable) { option in
                        Button(option.label) { onEdit(option) }
                            .accessibilityIdentifier("RelationshipAdd.\(option.field)")
                    }
                }
            }
        }) {
            VStack(alignment: .leading, spacing: InspectorMetrics.groupGap) {
                ForEach(shownRelationships) { relationship in
                    let group = LinkGroup(item: item.id, field: relationship.field)
                    ItemRelationshipGroup(
                        relationship: relationship, typeIcon: typeIcon, isExpanded: presentation.expandedLinks.contains(group),
                        onShowAll: { presentation.expandLinks(group) }, onOpen: onOpen, onEdit: { onEdit(relationship) },
                        onRemove: { await onRemove(relationship, $0) }, shownOnPage: placement.showsOnPage(relationship.field),
                        onShowOnPage: showOnPage(relationship.field))
                }
            }
        }
    }

    /// Every link the section lists, which its heading counts.
    private var relationshipCount: Int {
        shownRelationships.reduce(0) { $0 + $1.targets.count }
    }

    /// The items the page's text links to, in a section of their own.
    private var linksInPageSection: some View {
        let group = LinkGroup.content(of: item.id)
        let links = LinkLimit.split(mentions, expanded: presentation.expandedLinks.contains(group))
        return InspectorSectionView(.linksInPage, title: "Links in This Page", count: mentions.count) {
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
        InspectorSectionView(.tags, title: "Tags", count: tags.count,
                             placeholder: tags.isEmpty ? "No Tags" : nil, add: { hovering in
            if item.canEditTags {
                InspectorPlusButton(accessibilityLabel: "Add Tag", identifier: "ItemTagAdd", isRowHovered: hovering, action: addTag)
            }
        }) {
            ItemTagsSection(tags: tags, isEditable: item.canEditTags, onRemove: onRemoveTag)
        }
        .background(ValueEditAnchor(box: tagAnchor))
        .showOnPageMenu(isShown: placement.showsOnPage(PagePlacement.tags), onChange: showOnPage(PagePlacement.tags))
    }

    private func addTag() {
        guard let library, let view = tagAnchor.view else { return }
        ValueEditPresenter.shared.present(
            ValueEditRequest(kind: .tags, library: library, item: item.id, undoManager: undoManager) { _ in false }, anchor: view)
    }

    /// The items that link to this one, in a section of their own.
    private var linkedFromSection: some View {
        let group = LinkGroup(item: item.id, field: "#linked")
        let links = LinkLimit.split(linked, expanded: presentation.expandedLinks.contains(group))
        return InspectorSectionView(.linkedFrom, title: "Linked From", count: linked.count) {
            ForEach(links.shown, id: \.item) { link in
                LinkedItemRow(link: link, onOpen: onOpen)
            }
            if links.hidden > 0 {
                ItemShowMoreButton(count: links.hidden, identifier: "LinkedFromShowMore") {
                    presentation.expandLinks(group)
                }
            }
        }
        .showOnPageMenu(isShown: false, onChange: showOnPage(PagePlacement.linkedFrom))
    }

    /// The note's headings; one goes to its place in the text.
    private var outlineSection: some View {
        InspectorSectionView(.outline, title: "Outline", count: extras.outline.count) {
            ForEach(extras.outline) { heading in
                Button { onHeading(heading.index) } label: {
                    Text(verbatim: heading.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, CGFloat(heading.level - 1) * 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(InspectorRowButtonStyle())
                .foregroundStyle(.primary)
                .accessibilityIdentifier("OutlineHeading.\(heading.index)")
            }
        }
    }

    /// Items the item holds or is in, such as its files and its collections.
    private func itemsSection(_ kind: InspectorSectionKind, title: LocalizedStringKey, targets: [ItemRelationshipTarget]) -> some View {
        let group = LinkGroup(item: item.id, field: "#" + kind.identifier)
        let links = LinkLimit.split(targets, expanded: presentation.expandedLinks.contains(group))
        return InspectorSectionView(kind, title: title, count: targets.count) {
            ForEach(links.shown) { target in
                InspectorItemRow(target: target, typeIcon: typeIcon, onOpen: onOpen)
            }
            if links.hidden > 0 {
                ItemShowMoreButton(count: links.hidden, identifier: kind.identifier + "ShowMore") { presentation.expandLinks(group) }
            }
        }
    }

    /// The items an app's data gives the item, of one type, named for the type and the app.
    private func appSection(_ app: AppSection) -> some View {
        let group = LinkGroup(item: item.id, field: "#" + app.id)
        let links = LinkLimit.split(app.targets, expanded: presentation.expandedLinks.contains(group))
        return InspectorSectionView(
            .app, title: LocalizedStringKey(app.title), count: app.targets.count, foldKey: "\(InspectorSectionKind.app.key).\(app.id)",
            identifier: "\(InspectorSectionKind.app.identifier)-\(app.id)") {
            ForEach(links.shown) { target in
                InspectorItemRow(target: target, typeIcon: typeIcon, onOpen: onOpen)
            }
            if links.hidden > 0 {
                ItemShowMoreButton(count: links.hidden, identifier: "AppSectionShowMore-\(app.id)") { presentation.expandLinks(group) }
            }
        }
    }

    /// Details is a grid of small cells, so its section draws no box around them.
    private var detailsSection: some View {
        InspectorSectionView(.details, title: "Details", boxed: false) { InspectorCellGrid(spacing: InspectorMetrics.cellGap) { details } }
    }

    @ViewBuilder private var details: some View {
        if let source { InspectorDetailCell(name: String(localized: "Source"), value: source.name, mark: source.mark) }
        detail("Version", item.version.rawValue.formatted())
        moment("Created", item.created)
        moment("Edited", item.modified)
        if let place { detail("Place", place) }
        if case .file(let contentType, let byteCount) = item.content {
            detail("Kind", contentType.localizedDescription ?? String(localized: "File"))
            // A server gives a file's size once it holds the bytes, so a file not yet sent has none.
            if byteCount > 0 {
                detail("Size", ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
            }
        }
        ForEach(otherProperties) { property in
            InspectorDetailCell(
                name: Self.name(of: property.key, label: catalogue.label(ofField: property.key, for: item.type)),
                value: Self.text(of: property.value, format: dateFormat), isDate: Self.isDate(property.value))
        }
    }

    private func detail(_ name: LocalizedStringResource, _ value: String, isDate: Bool = false) -> some View {
        InspectorDetailCell(name: String(localized: name), value: value, isDate: isDate)
    }

    /// The day fits a cell beside its neighbor; the time stays in the help and in what Copy takes.
    private func moment(_ name: LocalizedStringResource, _ date: Date) -> some View {
        InspectorDetailCell(
            name: String(localized: name), value: ItemDate.text(of: date, hasTime: false, format: dateFormat), isDate: true,
            fullValue: ItemDate.text(of: date, hasTime: true, format: dateFormat))
    }

    // MARK: Contents

    /// The properties that have a value, then any the person added or cleared since the inspector showed this item.
    private var fields: [ItemTypeInfo.Field] {
        InspectorFields.properties(of: item, type: type, hidden: hiddenKeys, revealed: revealed)
    }

    /// The item's Location, which stands in the list for the fields it is made of (`ItemLocation`).
    private var location: ItemLocation? { ItemLocation.of(type) }

    /// Whether the list shows the Location: the item holds something it draws, or the person just added it.
    private var listsLocation: Bool {
        guard let location else { return false }
        return location.hasValue(in: item) || (item.isEditable && revealed.contains(ItemLocation.rowID))
    }

    /// Whether the Add Property menu offers the Location, which the item does not show yet.
    private var offersLocation: Bool { location != nil && item.isEditable && !listsLocation }

    /// The list's entries: the fields, with the Location in place of the ones it is made of.
    private var entries: [ItemLocation.Entry] {
        guard let location else { return fields.map { .field($0) } }
        return location.folding(fields, showingCoordinates: showsCoordinates, listsLocation: listsLocation)
    }

    private var emptyFields: [ItemTypeInfo.Field] {
        let addable = InspectorFields.addable(of: item, type: type, hidden: hiddenKeys, revealed: revealed)
        guard let location else { return addable }
        let owned = location.ownedKeys(showingCoordinates: showsCoordinates)
        return addable.filter { !owned.contains($0.key) }
    }

    private var hasProperties: Bool { !entries.isEmpty || !emptyFields.isEmpty || offersLocation }

    private var hasRelationships: Bool { !shownRelationships.isEmpty || !addable.isEmpty || !mentions.isEmpty || !linked.isEmpty }

    /// An item that can take a tag shows the section for adding one; one that can't shows it only if it has tags.
    private var hasTags: Bool { item.canEditTags || !tags.isEmpty }

    private func addLocation() {
        withAnimation(.snappy(duration: 0.2)) {
            revealed.insert(ItemLocation.rowID)
            adding = ItemLocation.rowID
        }
    }

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
    private static func text(of value: PropertyValue, format: DateFormat) -> String {
        if let string = value.string, let date = ItemDate.parse(string) { return date.text(format: format) }
        return ItemValueText.string(value)
    }

    /// The catalogue's label for a key, else the key written for reading.
    private static func name(of key: String, label: String?) -> String {
        if let label { return label }
        let words = key.split { $0 == "_" || $0 == "-" || $0 == "." }.joined(separator: " ")
        return words
    }

    /// Every property the type does not name or show elsewhere, in the order the item holds them.
    private var otherProperties: [Property] {
        var shown = InspectorFields.accountedFor(type: type, hidden: hiddenKeys)
        shown.formUnion(relationships.map(\.field))
        return item.properties.filter { !shown.contains($0.key) }
    }
}

/// A fact about the item in Details: a small cell, with its value cut in the middle where it is long.
private struct InspectorDetailCell: View {
    let name: String
    let value: String
    var isDate = false
    /// An icon ID drawn before the value.
    var mark: String?
    /// What the help and Copy give where the cell shows less than the whole value.
    var fullValue: String?

    var body: some View {
        InspectorCell(name: name) {
            HStack(spacing: 6) {
                if let mark { TypeGlyph(id: mark).foregroundStyle(.secondary) }
                InspectorText(text: value, keepsOneLine: isDate, lines: InspectorMetrics.cellValueLines)
            }
        }
        .help(String((fullValue ?? value).prefix(600)))
        .contextMenu { Button("Copy") { InspectorPasteboard.copy(fullValue ?? value) } }
    }
}

/// An item that links to the one shown: a light row with its type's mark and title, and the day it last changed.
private struct LinkedItemRow: View {
    let link: LinkedItem
    let onOpen: (ItemID) -> Void

    var body: some View {
        Button { onOpen(link.item) } label: {
            HStack(spacing: InspectorMetrics.markGap) {
                TypeMark(icon: link.icon, size: .row)
                Text(verbatim: link.title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 6)
                Text(verbatim: link.date).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    .interfaceFont(.callout)
            }
            .interfaceFont(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(InspectorRowButtonStyle())
        .foregroundStyle(.primary)
        .accessibilityIdentifier("LinkedFrom.\(link.item.rawValue)")
    }
}
