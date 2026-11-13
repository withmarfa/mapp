import AppKit
import SwiftUI

/// The page owns its title; the inspector is reserved for the rest of the item's details. The page draws the
/// title and pinned properties above the note, so they scroll with it as one surface, and this carries out what
/// the person does there: the title is saved as the item's property, and every other value opens in the panel under
/// it (`ValueEditPresenter`). Applied to the editor's view, whose container the panel's frames arrive in.
struct ItemPageHeader: ViewModifier {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @AppStorage(InterfaceKey.textSize) private var interfaceTextSize = InterfaceStyle.defaultTextSize
    @AppStorage(PagePlacements.key) private var placements = PagePlacements()
    @AppStorage(PageKey.titleLines) private var titleLines = TitleLines.standard
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    let item: Item
    let editor: EditorController
    let drafts: DetailsPresentation
    func body(content: Content) -> some View {
        content
            // The action may run on an earlier copy of this view, so it takes what changed from the change itself.
            .onChange(of: item.id, initial: true) { old, id in
                if old != id {
                    drafts.saveTitle(of: old, in: library, undoManager: undoManager)
                }
                ValueEditPresenter.shared.itemChanged(to: id)
                editor.onHeaderEvent = handler
                let library = library, drafts = drafts
                editor.showHeader { Cost.measure(.pageHeader) { Self.header(of: id, in: library, drafts: drafts) } }
            }
            .onChange(of: interfaceTextSize) { editor.refreshHeader() }
            .onChange(of: titleLines) { editor.refreshHeader() }
            .onChange(of: dateFormat) { editor.refreshHeader() }
            // The page is drawn from the defaults as they are when it is read, so a change made anywhere, in the
            // inspector, in the sheet or from the page's own menu, needs it read again.
            .onChange(of: placements) { editor.refreshHeader() }
            #if DEBUG
            // A chip knob in the Tuning panel changes the open page's header at once. Reading the looks here makes the
            // view depend on them, and the header reads them again as it is rebuilt.
            .onChange(of: Tuning.shared.chipLooks) { editor.refreshHeader() }
            #endif
            .onDisappear { drafts.saveTitle(of: item.id, in: library, undoManager: undoManager) }
    }

    /// What the page's header shows for the item, read from the library and the window's drafts as they are now.
    static func header(
        of id: ItemID, in library: any ItemLibrary, drafts: DetailsPresentation, placements: PagePlacements = .stored(),
        titleLines: Int = TitleLines.stored(), dateFormat: DateFormat = .stored()
    ) -> PageHeader? {
        guard let item = library.item(id) else { return nil }
        let draft = drafts.draft(for: item.id, key: "title")
        let parts = PageHeaderParts(of: item, in: library, placements: placements, dateFormat: dateFormat, offersEmpty: true)
        let (type, placement, relationships, now, kind, lead, pins) =
            (parts.type, parts.placement, parts.relationships, parts.now, parts.kind, parts.lead, parts.pins)
        let status = type?.statusField
        let parent = Self.parent(in: relationships)
        func typeIcon(of target: ItemID) -> String? { PageHeaderParts.typeIcon(of: target, in: library) }
        let properties = lead.refine(PropertyRow.block(parts.candidates, placement: placement, excluding: pins.leftOutOfBlock))
        let isCollection = library.catalogue.isCollection(item.type)
        let contents = isCollection
            ? LinkedItem.list(
                pointingTo: item.id, in: relationships, catalogue: library.catalogue, now: now, format: dateFormat, members: .only,
                item: { library.item($0) })
            : []
        let allLinked = LinkedItem.list(
            pointingTo: item.id, in: relationships, catalogue: library.catalogue, now: now, format: dateFormat,
            members: isCollection ? .excluding : .all, item: { library.item($0) })
        // Where the person put Linked From: the page's foot, or only the inspector.
        let linked = placement.linkedFromPlace == .page ? allLinked : []
        let hasText = library.catalogue.itemTypes[item.type]?.bodyKey != nil
        // A collection with no text, as a folder a connector keeps has, is its members: an editor with nothing in it
        // would only invite typing that the connector puts back.
        let showsText = hasText && !(isCollection && library.body(of: item.id)?.text.isEmpty != false)
        return PageHeader(
            item: item.id.rawValue,
            hidden: item.state == .trashed,
            title: item.title,
            draft: draft.isDirty ? draft.text : nil,
            titleRejected: draft.rejected,
            titleRefusal: library.titleRefusal,
            editable: library.canSetTitle(of: item),
            showsTitle: item.titleRule != .firstLine,
            kind: kind,
            person: lead.person,
            subtitle: lead.subtitle,
            status: status.map { field in
                let value = PagePins.statusValue(of: item, in: field)
                // With nothing to pick from, the pin only shows the status the item has.
                return PageHeader.Pin(label: value.map { ItemTypeInfo.Field.label(ofOption: $0) } ?? "",
                                      enabled: item.isEditable && field.isPicked, empty: value == nil, mark: .init(StatusSymbol(group: value.flatMap(field.statusGroup(of:)))))
            },
            parent: parent.flatMap { parent in
                guard let target = parent.targets.first else { return nil }
                let icon = target.itemID.flatMap(typeIcon(of:))
                return PageHeader.Pin(label: target.title, enabled: true, icon: .init(name: icon), tone: TypeTone(icon: icon).rawValue)
            },
            pins: pins.pins,
            properties: properties,
            contents: contents,
            linked: linked,
            showsText: showsText,
            showMore: String(localized: "Show \(max(0, properties.count - PropertyRow.foldAfter)) More"),
            showMoreContents: String(localized: "Show \(max(0, contents.count - LinkedItem.foldAfter)) More"),
            showMoreLinked: String(localized: "Show \(max(0, linked.count - LinkedItem.foldAfter)) More"),
            interfaceTextSize: UserDefaults.standard.object(forKey: InterfaceKey.textSize) as? Int ?? InterfaceStyle.defaultTextSize,
            titleLines: titleLines,
            chips: .init(),
            linkedCount: allLinked.count,
            layoutOn: PageCustomization.isAvailable(for: item) ? drafts.isCustomizingLayout : nil
        )
    }

    /// Carries out what the page asks, for the item it names, which may be one the page has just left: a title draft
    /// is kept for it, but a menu is only for the item on the page now.
    private var handler: (PageHeaderEvent) -> Void {
        let library = library, drafts = drafts, undoManager = undoManager
        // The editor keeps this, so it holds the editor weakly; otherwise neither would ever be released.
        return { [weak editor] event in
            guard let editor else { return }
            switch event {
            case .titleInput(let id, let text):
                let draft = drafts.draft(for: id, key: "title")
                draft.text = text
                draft.isDirty = true
                draft.rejected = false
            case .titleCommit(let id, let text, let startWriting):
                let draft = drafts.draft(for: id, key: "title")
                if text != (draft.isDirty ? draft.text : library.item(id)?.title) {
                    draft.text = text
                    draft.isDirty = true
                    draft.rejected = false
                }
                if drafts.saveTitle(of: id, in: library, undoManager: undoManager), startWriting {
                    editor.focus(id)
                }
            case .titleDiscard(let id):
                let draft = drafts.draft(for: id, key: "title")
                draft.isDirty = false
                draft.rejected = false
            case .menu(.status, let id, let rect):
                guard editor.isShowing(id), let item = library.item(id), let status = library.catalogue.itemTypes[item.type]?.statusField else { return }
                editor.presentEditor(Self.request(.status(status), of: id, in: library, undoManager: undoManager, editor: editor), under: rect)
            case .menu(.parent, let id, let rect):
                guard editor.isShowing(id), let item = library.item(id) else { return }
                // An item that cannot be edited has no panel to change the parent in; the pin then only opens it.
                guard item.isEditable else {
                    if let target = Self.parent(in: library.relationships(for: id))?.targets.first?.itemID { editor.onOpenNote(target) }
                    return
                }
                editor.presentEditor(Self.request(.parent, of: id, in: library, undoManager: undoManager, editor: editor), under: rect)
            case .edit(let row, let id, let rect):
                guard editor.isShowing(id), let item = library.item(id) else { return }
                let kind: ValueEditKind?
                switch row {
                case PagePlacement.tags:
                    kind = item.canEditTags ? .tags : nil
                case PagePlacement.parent:
                    kind = item.isEditable ? .parent : nil
                case PagePlacement.type:
                    kind = library.offersTypeChange(for: [id]) ? .type : nil
                default:
                    let field = library.catalogue.itemTypes[item.type]?.fields.first { $0.key == row }
                    // A yes or no is a toggle, not a panel.
                    if let field, field.kind == .boolean, item.isEditable {
                        library.setItemProperty(id, key: row, value: .bool(!InspectorFields.isYes(item.value(of: row))), undoManager: undoManager)
                        return
                    }
                    kind = field.flatMap(ValueEditKind.init(field:))
                }
                guard let kind else { return }
                var request = Self.request(kind, of: id, in: library, undoManager: undoManager, editor: editor)
                request.needsValues = { [weak drafts] type in
                    drafts?.typeValues = TypeValuesRequest(ids: [id], type: type, undoManager: undoManager)
                }
                editor.presentEditor(request, under: rect)
            case .toggleLayout:
                drafts.toggleLayout()
            case .showLinked:
                // Linked From is in the inspector, which Customize Layout stands in for.
                drafts.endLayout()
                drafts.isPresented = true
            case .hideFromPage(let row, let id):
                guard editor.isShowing(id), let type = library.item(id)?.type else { return }
                PagePlacements.update { $0.set(false, row: row, of: type, in: library.catalogue) }
            case .moveRow(let row, let order, let id):
                guard editor.isShowing(id), let item = library.item(id) else { return }
                let rows = PageLayout.rows(
                    of: item, type: library.catalogue.itemTypes[item.type], hidden: library.hiddenPropertyKeys(of: item),
                    relationships: library.relationships(for: item.id), catalogue: library.catalogue)
                PagePlacements.update { placements in
                    let layout = PageLayout(rows: rows, placement: placements.placement(of: item.type, in: library.catalogue))
                    if let moved = layout.listing(order, moving: row) { placements.apply(moved, of: item.type, in: library.catalogue) }
                }
            }
        }
    }

    /// The editor for one of the item's values, which writes as the property row in the inspector does: through the
    /// library. The panel says why a write is refused.
    private static func request(
        _ kind: ValueEditKind, of id: ItemID, in library: any ItemLibrary, undoManager: UndoManager?, editor: EditorController
    ) -> ValueEditRequest {
        var request = ValueEditRequest(kind: kind, library: library, item: id, undoManager: undoManager)
        request.write = { value in
            guard let key = kind.field?.key else { return false }
            return library.setItemProperty(id, key: key, value: value, undoManager: undoManager)
        }
        request.open = { [weak editor] in editor?.onOpenNote($0) }
        return request
    }

    /// What the status menu offers: the catalogue's values, and the item's own if it holds one the catalogue does
    /// not list, so the menu always shows what is set.
    static func statusChoices(of item: Item, in field: ItemTypeInfo.Field) -> [String] {
        field.options(including: PagePins.statusValue(of: item, in: field))
    }

    private static func parent(in relationships: [ItemRelationship]) -> ItemRelationship? {
        relationships.first { $0.field == PagePlacement.parent }
    }

    /// A catalogue's words, looked up in the String Catalog as SwiftUI's text would look them up.
    static func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}
