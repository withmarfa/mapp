import Marfa
import MarfaIcons
import SwiftUI
import UniformTypeIdentifiers

struct ItemInspectorHost: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @StoredOrder private var order
    let browser: Browser?
    let itemID: ItemID?
    let details: DetailsPresentation
    /// The page beside the panel, which lists the headings of the item on it and goes to one, for the Outline.
    /// Nil where no page is beside the panel, and the Outline then has no headings.
    var editor: EditorController?
    @AppStorage(PagePlacements.key) private var placements = PagePlacements()

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
            } else if let id = selectedID, let item = library.headerItem(id), details.isCustomizingLayout, PageCustomization.isAvailable(for: item) {
                ItemLayoutPanel(item: item)
                    .onExitCommand { details.endLayout() }
            } else if let id = selectedID, let item = library.headerItem(id) {
                let placement = placements.placement(of: item.type, in: library.catalogue)
                let relationships = library.relationships(for: id)
                ItemPanelLoader(
                    item: item, relationships: relationships, mentions: library.bodyMentions(for: id), editor: editor, details: details,
                    onOpen: open
                ) {
                    ItemInspector(
                        item: item,
                        type: library.catalogue.itemTypes[item.type],
                        catalogue: library.catalogue,
                        hiddenKeys: library.hiddenPropertyKeys(of: item),
                        relationships: relationships,
                        onProperty: { key, value in library.setItemProperty(id, key: key, value: value, undoManager: undoManager) },
                        isWritingProperties: { library.isWritingProperties(of: id) },
                        onOpen: open,
                        onRemove: { relationship, target in
                            await library.changeLinks(id, field: relationship.field, adding: [], removing: [target], undoManager: undoManager) == .taken
                        },
                        tags: library.tags(of: item),
                        onRemoveTag: { library.removeTag($0, from: [id], undoManager: undoManager) },
                        drafts: details,
                        placement: placement,
                        onPlace: PageCustomization.isAvailable(for: item) ? { row, shown in placements.set(shown, row: row, of: item.type, in: library.catalogue) } : nil,
                        drawnByPage: PageCustomization.drawnKeys(of: item, in: library.catalogue),
                        typeIcon: { target in library.headerItem(target).flatMap { library.catalogue.icon(for: $0.type) } }
                    )
                }
                .id(id)
            } else if let browser, browser.selection.count > 1 {
                EmptyState(title: Text("^[\(browser.selection.count) item](inflect: true) selected"), detail: nil, actions: { EmptyView() })
            } else if selectedID != nil {
                // The library has not read the chosen item yet.
                if library.isLoaded && library.syncReport.phase == .current { Color.clear } else { InspectorReadingView() }
            } else {
                // A place with no items says so in the main area, and so does the list layout's page column.
                Color.clear
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ItemInspector")
    }

    /// Follows a link as Settings > Open Items says. In a window of its own, which has no list, the item opens in
    /// another window.
    private func open(_ id: ItemID) {
        guard let browser else {
            if library.item(id) != nil { openWindow(value: id) }
            return
        }
        browser.searchText = ""
        if library.item(id)?.state == .trashed {
            browser.showSettings(.recentlyDeleted)
            return
        }
        guard let item = library.item(id) else { return }
        browser.follow(link: item, in: library, order: order)
    }
}

/// What the panel's Info still carries until the page's rows edit it: the item's properties, its relationships and its
/// tags. Every property is listed here; a context menu on one says whether the page shows it too.
struct ItemInspector: View {
    @AppStorage(PageKey.showsCoordinates) private var showsCoordinates = false
    let item: Item
    /// Nil for a type the catalogue does not hold, which is shown with no fields.
    let type: ItemTypeInfo?
    /// Calls a property the item's type does not define by the label another type gives it.
    var catalogue = Catalogue()
    /// The item's property keys that are not listed: the title, the text, and any the library keeps for itself.
    var hiddenKeys: Set<String> = []
    let relationships: [ItemRelationship]
    let onProperty: (String, PropertyValue?) -> Bool
    /// Whether an edit of the item's properties is still on its way into the library, read only for a list of
    /// entries, which waits for it.
    var isWritingProperties: () -> Bool = { false }
    let onOpen: (ItemID) -> Void
    let onRemove: (ItemRelationship, ItemID) async -> Bool
    /// The tags the person manages, which exclude the favorite tag, and what removes one. Tags are added in the Tags box,
    /// whose editor reaches the library itself.
    var tags: [String] = []
    var onRemoveTag: (String) -> Void = { _ in }
    var drafts: DetailsPresentation? = nil
    /// What the page shows of this type's items, and what changes a row of it. A row not offered a change has no
    /// Show on Page menu.
    var placement: PagePlacement = .standard
    var onPlace: ((String, Bool) -> Void)?
    /// The properties the page's header draws itself, which no choice of where to show them changes.
    var drawnByPage: Set<String> = []
    /// The icon of the type of the item with this identifier, for the rows that name an item.
    var typeIcon: (ItemID) -> String? = { _ in nil }
    /// Holds what the window keeps for the inspector when no window gives it, as in a preview.
    @State private var ownPresentation = DetailsPresentation()
    /// The empty properties the person has added, and the ones they have edited, which stay listed if cleared.
    /// The host remakes the inspector for another item, which forgets them.
    @State private var revealed: Set<String> = []
    /// The property just added, whose row opens ready to edit.
    @State private var adding: String?
    /// The Tags box while a tag is being added in it.
    @State private var tagEditor: ValueEditModel?
    @Environment(\.library) private var library
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.sectionGap) {
            if let message = item.problem?.message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .interfaceFont(.callout).foregroundStyle(.red)
            }
            if hasProperties { properties }
            if hasRelationships { relationshipSection }
            if hasTags { tagSection }
        }
        .sharesInspectorNameColumn()
        .padding(.top, InspectorMetrics.sectionGap)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var presentation: DetailsPresentation { drafts ?? ownPresentation }

    /// The change a row's Show on Page menu makes, where the inspector has one to make.
    private func showOnPage(_ row: String) -> ((Bool) -> Void)? {
        if drawnByPage.contains(row) { return nil }
        return onPlace.map { place in { place(row, $0) } }
    }

    // MARK: Sections

    private var properties: some View {
        PanelSection(title: "Properties", count: entries.count, placeholder: entries.isEmpty ? "No Properties" : nil, add: { hovering in
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
                    ItemPropertyRow(definition: field, value: item.value(of: field.key), isEditable: item.allows(.fields),
                                    // A property the person has touched stays listed, even once cleared.
                                    onChange: { revealed.insert(field.key); return onProperty(field.key, $0) },
                                    item: item.id,
                                    retainedDraft: drafts?.draft(for: item.id, key: field.key),
                                    startsEditing: adding == field.key,
                                    // The window holds the draft, so closing the panel does not give it back.
                                    handsOffOnLeave: drafts == nil,
                                    shownOnPage: placement.showsOnPage(field.key), onShowOnPage: showOnPage(field.key),
                                    isWriting: field.kind.isList && isWritingProperties())
                }
            }
        }
    }

    private var relationshipSection: some View {
        PanelSection(title: "Relationships", count: relationshipCount,
                     placeholder: relationshipCount == 0 ? "No Relationships" : nil, boxed: false) {
            VStack(alignment: .leading, spacing: InspectorMetrics.groupGap) {
                ForEach(shownRelationships) { relationship in
                    let group = LinkGroup(item: item.id, field: relationship.field)
                    ItemRelationshipGroup(
                        relationship: relationship, typeIcon: typeIcon, isExpanded: presentation.expandedLinks.contains(group),
                        onShowAll: { presentation.expandLinks(group) }, onOpen: onOpen,
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

    private var tagSection: some View {
        PanelSection(title: "Tags", count: tags.count, boxed: false, add: { hovering in
            if item.allows(.tags) {
                InspectorPlusButton(accessibilityLabel: "Add Tag", identifier: "ItemTagAdd", isRowHovered: hovering, action: beginTags)
            }
        }) {
            InspectorTagsContent(
                tags: tags, isEditable: item.allows(.tags), onRemove: onRemoveTag, editor: tagEditor,
                begin: beginTags, finish: finishTags, cancel: { tagEditor = nil })
        }
        .onDisappear(perform: finishTags)
        .showOnPageMenu(isShown: placement.showsOnPage(PagePlacement.tags), onChange: showOnPage(PagePlacement.tags))
    }

    /// Puts the text cursor in the Tags box.
    private func beginTags() {
        guard let library, item.allows(.tags), tagEditor == nil else { return }
        ValueEditPresenter.shared.dismiss(restoringFocus: false)
        let model = ValueEditModel(ValueEditRequest(kind: .tags, library: library, item: item.id, undoManager: undoManager))
        // The model closes the box itself where the item can no longer take tags, which ends it as leaving it does.
        model.close = { finishTags() }
        tagEditor = model
    }

    /// Ends the editing without Escape: a tag typed and not yet added is added, or kept and told where the library
    /// refuses it, so leaving the box, the item or the panel never drops it.
    private func finishTags() {
        guard let model = tagEditor else { return }
        tagEditor = nil
        model.finishTagField()
    }

    // MARK: Contents

    /// The item's Location, which stands in the list for the fields it is made of (`ItemLocation`).
    private var location: ItemLocation? { ItemLocation.of(type) }

    /// Whether the Add Property menu offers the Location, which the item does not show yet.
    private var offersLocation: Bool {
        guard let location else { return false }
        return item.allows(.fields) && !location.isListed(in: item, revealed: revealed)
    }

    /// The properties that have a value, then any the person added or cleared since the inspector showed this item, with
    /// the Location in place of the fields it is made of.
    private var entries: [ItemLocation.Entry] {
        InspectorFields.entries(of: item, type: type, hidden: hiddenKeys, revealed: revealed, showingCoordinates: showsCoordinates)
    }

    private var emptyFields: [ItemTypeInfo.Field] {
        let addable = InspectorFields.addable(of: item, type: type, hidden: hiddenKeys, revealed: revealed)
        guard let location else { return addable }
        let owned = location.ownedKeys(showingCoordinates: showsCoordinates)
        return addable.filter { !owned.contains($0.key) }
    }

    private var hasProperties: Bool { !entries.isEmpty || !emptyFields.isEmpty || offersLocation }

    private var hasRelationships: Bool { !shownRelationships.isEmpty }

    /// An item that can take a tag shows the section for adding one; one that can't shows it only if it has tags.
    private var hasTags: Bool { item.allows(.tags) || !tags.isEmpty }

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
}

/// A section of the inspector that does not fold: a heading with its count, a plus where the section takes something new,
/// and its content in a grouped box (or as it is, where it is not `boxed`). A section with nothing in it shows
/// `placeholder` as its one row.
private struct PanelSection<Content: View, Add: View>: View {
    let title: LocalizedStringKey
    var count: Int?
    var placeholder: LocalizedStringKey?
    var boxed = true
    /// The plus control, given whether the heading is hovered.
    @ViewBuilder let add: (Bool) -> Add
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.headingGap) {
            HStack(spacing: 4) {
                Text(title)
                if let count, count > 0 {
                    Text(count, format: .number).monospacedDigit().fontWeight(.regular).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .interfaceFont(.body.weight(.semibold))
            .padding(.horizontal, InspectorMetrics.headingInset)
            .accessibilityAddTraits(.isHeader)
            .overlay(alignment: .trailing) { add(hovering).inspectorTrailingColumn(clearsFold: false) }
            .onHover { hovering = $0 }
            if let placeholder {
                InspectorBox { Text(placeholder).foregroundStyle(.secondary) }
            } else if boxed {
                InspectorBox { content }
            } else {
                content
            }
        }
    }
}
