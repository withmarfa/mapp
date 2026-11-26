import AppKit
import SwiftUI

/// The page draws the item's head (`PageHead`) above the text, so the two scroll as one surface, and this carries out
/// what the person does there: the title is saved as the item's property, every value opens in the panel under it
/// (`ValueEditPresenter`), a row's name opens the row's menu, and the kicker's type opens Change Type. Applied to the
/// editor's view, whose container the panel's frames arrive in.
struct ItemPageHeader: ViewModifier {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @AppStorage(InterfaceKey.textSize) private var interfaceTextSize = InterfaceStyle.defaultTextSize
    @AppStorage(PagePlacements.key) private var placements = PagePlacements()
    @AppStorage(PageKey.titleLines) private var titleLines = TitleLines.standard
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    @AppStorage(PageKey.showsCoordinates) private var showsCoordinates = false
    @AppStorage(PageKey.pinsProperties) private var pinsProperties = false
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
                editor.showHeader(Self.heldHeader(of: editor, in: library, drafts: drafts))
            }
            .onChange(of: interfaceTextSize) { editor.refreshHeader() }
            .onChange(of: titleLines) { editor.refreshHeader() }
            .onChange(of: dateFormat) { editor.refreshHeader() }
            .onChange(of: showsCoordinates) { editor.refreshHeader() }
            .onChange(of: pinsProperties) { editor.refreshHeader() }
            // The page is drawn from the defaults as they are when it is read, so a change made anywhere, in the
            // inspector, in Settings or from the page's own menu, needs it read again.
            .onChange(of: placements) { editor.refreshHeader() }
            #if DEBUG
            // A chip knob in the Tuning panel changes the open page's head at once. Reading the looks here makes the
            // view depend on them, and the head reads them again as it is rebuilt.
            .onChange(of: Tuning.shared.chipLooks) { editor.refreshHeader() }
            #endif
            .onDisappear { drafts.saveTitle(of: item.id, in: library, undoManager: undoManager) }
    }

    /// The header of the item the editor holds, which changes only once the text before it is handed over, so the head
    /// never names one item over another's text.
    static func heldHeader(of editor: EditorController, in library: any ItemLibrary, drafts: DetailsPresentation) -> () -> PageHeader? {
        { [weak editor] in
            guard let id = editor?.heldItemID else { return nil }
            return Cost.measure(.pageHeader) {
                header(
                    of: id, in: library, drafts: drafts, footLimits: editor?.footLimits ?? [:],
                    refreshMap: { [weak editor] in editor?.refreshHeader() })
            }
        }
    }

    /// What the page's head shows for the item, read from the library and the window's drafts as they are now.
    static func header(
        of id: ItemID, in library: any ItemLibrary, drafts: DetailsPresentation, placements: PagePlacements = .stored(),
        pinsProperties: Bool = PinsProperties.stored(), titleLines: Int = TitleLines.stored(), dateFormat: DateFormat = .stored(),
        showsCoordinates: Bool = ShowsCoordinates.stored(), footLimits: PageFoot.Limits = [:],
        refreshMap: (@MainActor () -> Void)? = nil
    ) -> PageHeader? {
        guard let item = library.headerItem(id) else { return nil }
        let draft = drafts.draft(for: item.id, key: "title")
        let head = PageHead(
            of: item, in: library, placements: placements, pinsProperties: pinsProperties, dateFormat: dateFormat, showsCoordinates: showsCoordinates)
        let relationships = library.relationships(for: item.id)
        let status = library.catalogue.itemTypes[item.type]?.statusField
        let foot = PageFoot.of(
            item, in: library, relationships: relationships,
            showsLinkedFrom: placements.placement(of: item.type, in: library.catalogue).linkedFromPlace == .page, limits: footLimits,
            format: dateFormat, now: library.now())
        let hasText = library.catalogue.itemTypes[item.type]?.bodyKey != nil
        // A collection with no text, as a folder a connector keeps has, offers nothing to type into: an editor with
        // nothing in it would only invite typing that the connector puts back. The body is read only for a collection,
        // and only for whether its text is empty, which changes when that emptiness does, not at every edit.
        let showsText = hasText && !(library.catalogue.isCollection(item.type) && library.textIsEmpty(item.id))
        return PageHeader(
            item: item.id.rawValue,
            // Focus hides the head only, and the toolbar then names the item from the start.
            focused: drafts.isFocused(on: item.id),
            title: item.title,
            draft: draft.isDirty ? draft.text : nil,
            titleRejected: draft.rejected,
            titleRefusal: library.titleRefusal,
            editable: library.canSetTitle(of: item),
            showsTitle: item.titleRule != .firstLine,
            textLeads: showsText && item.titleRule == .firstLine && PageHeaderKind.of(item.type, in: library.catalogue) == .highlight,
            kicker: PageHeader.Kicker(head.kicker),
            status: status.flatMap { field in
                guard let value = PageHead.statusValue(of: item, in: field) else { return nil }
                // With nothing to pick from, the pill only shows the status the item has.
                return PageHeader.Pin(
                    label: ItemTypeInfo.Field.label(ofOption: value), enabled: item.allows(.fields) && field.isPicked,
                    mark: .init(StatusSymbol(group: field.statusGroup(of: value))))
            },
            parent: Self.parent(in: relationships).flatMap { parent in
                guard let target = parent.targets.first else { return nil }
                let icon = target.itemID.flatMap { PageHead.typeIcon(of: $0, in: library) }
                return PageHeader.Pin(
                    label: target.title, enabled: true, icon: .init(name: icon), tone: TypeTone(icon: icon).rawValue,
                    item: target.itemID?.rawValue)
            },
            pins: head.pins,
            rows: head.rows,
            showMore: head.showMore,
            foot: foot,
            map: Self.map(of: item, in: library, refresh: refreshMap),
            showsText: showsText,
            interfaceTextSize: UserDefaults.standard.object(forKey: InterfaceKey.textSize) as? Int ?? InterfaceStyle.defaultTextSize,
            titleLines: titleLines,
            chips: .init()
        )
    }

    /// A place's map: its pictures, or none yet, for the point the place holds. Nil for an item that is no place or has no
    /// point, which draws nothing, not an empty box. Without a way to be told when the pictures are made, none is asked of
    /// MapKit.
    private static func map(of item: Item, in library: any ItemLibrary, refresh: (@MainActor () -> Void)?) -> PageHeader.Map? {
        guard PageHeaderKind.of(item.type, in: library.catalogue) == .place,
              let location = ItemLocation.of(library.catalogue.itemTypes[item.type]),
              case .point(let point) = location.reading(of: item) else { return nil }
        let pictures = refresh.flatMap { PlaceMapImages.shared.pictures(for: point, whenMade: $0) }
        return PageHeader.Map(light: pictures?.light, dark: pictures?.dark, label: item.displayTitle)
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
                guard item.allows(.links) else {
                    if let target = Self.parent(in: library.relationships(for: id))?.targets.first?.itemID { editor.follow(target) }
                    return
                }
                editor.presentEditor(Self.request(.relation(PagePlacement.parent), of: id, in: library, undoManager: undoManager, editor: editor), under: rect)
            case .edit(let row, let id, let rect):
                Self.openValue(of: row, in: id, under: rect, library: library, drafts: drafts, undoManager: undoManager, editor: editor)
            case .fieldMenu(let row, let editsValue, let id, let rect):
                Self.openFieldMenu(
                    row: row, editsValue: editsValue, of: id, under: rect, library: library, drafts: drafts, undoManager: undoManager, editor: editor)
            case .changeType(let id, let rect):
                guard editor.isShowing(id), library.offersTypeChange(for: [id]) else { return }
                var request = Self.request(.type, of: id, in: library, undoManager: undoManager, editor: editor)
                request.needsValues = { type in
                    drafts.typeValues = TypeValuesRequest(ids: [id], type: type, undoManager: undoManager)
                }
                editor.presentEditor(request, under: rect)
            case .hideFromPage(let row, let id):
                guard editor.isShowing(id), let type = library.item(id)?.type else { return }
                PagePlacements.update { $0.set(false, row: row, of: type, in: library.catalogue) }
            case .moveRow(let row, let order, let id):
                guard editor.isShowing(id), let type = library.item(id)?.type, row != PagePlacement.when else { return }
                // The order is every row this item lists, folded ones too, as the drag left them. The type's saved order
                // takes it for those rows and keeps the place of every row the item does not list.
                PagePlacements.update { $0.setDraggedOrder(order.filter { $0 != PagePlacement.when && !$0.hasPrefix(PropertyRow.otherPrefix) }, of: type) }
            }
        }
    }

    /// Opens the panel for one of the item's values under `rect`.
    private static func openValue(
        of row: String, in id: ItemID, under rect: CGRect, library: any ItemLibrary, drafts: DetailsPresentation,
        undoManager: UndoManager?, editor: EditorController
    ) {
        guard editor.isShowing(id), let item = library.item(id) else { return }
        let catalogue = library.catalogue
        let kind: ValueEditKind?
        switch row {
        case PagePlacement.tags:
            kind = item.allows(.tags) ? .tags : nil
        case EventTime.rowID:
            kind = EventTime.of(item.type, in: catalogue).flatMap { item.allows(.fields) ? ValueEditKind.eventTime($0) : nil }
        case ItemLocation.rowID:
            // A Location with no point and no way to set one has nothing to open.
            let location = ItemLocation.of(catalogue.itemTypes[item.type])
            kind = location.flatMap { item.allows(.fields) || $0.hasPoint(item) ? ValueEditKind.location($0) : nil }
        default:
            // A link the item may hold, or a field of its type.
            if let link = library.relationFields(of: id).first(where: { $0.field == row }) {
                kind = link.editability == .editable ? .relation(row) : nil
            } else {
                kind = item.allows(.fields) ? catalogue.itemTypes[item.type]?.fields.first { $0.key == row }.flatMap(ValueEditKind.init(field:)) : nil
            }
        }
        guard let kind else { return }
        var request = Self.request(kind, of: id, in: library, undoManager: undoManager, editor: editor)
        request.needsValues = { [weak drafts] type in
            drafts?.typeValues = TypeValuesRequest(ids: [id], type: type, undoManager: undoManager)
        }
        editor.presentEditor(request, under: rect)
    }

    /// Opens the menu a row's name asks for, under the name, and carries out what the person chooses. How the row shows
    /// and where is the Mac's own choice for the type, stored at once; a change to the type goes through the library,
    /// which refuses it in words.
    private static func openFieldMenu(
        row: String, editsValue: Bool, of id: ItemID, under rect: CGRect, library: any ItemLibrary, drafts: DetailsPresentation,
        undoManager: UndoManager?, editor: EditorController
    ) {
        guard editor.isShowing(id), let item = library.item(id) else { return }
        let catalogue = library.catalogue
        let type = catalogue.itemTypes[item.type]
        let pinsProperties = PinsProperties.stored()
        let placement = PagePlacements.stored().placement(of: item.type, in: catalogue)
        let head = PageHead(of: item, in: library, pinsProperties: pinsProperties)
        // The rows a move works among: every row the page lists, the When of an event aside, which stays first.
        let order = head.order.filter { $0 != PagePlacement.when }
        let placing = row == PagePlacement.when ? nil : order.firstIndex(of: row).map { index in
            FieldMenu.Placing(
                shows: placement.shows(row), canMoveUp: index > 0, canMoveDown: index < order.count - 1,
                isPinned: pinsProperties ? head.pins.contains { $0.id == row } : nil,
                canPin: head.pins.count < PagePlacement.pinLimit)
        } ?? (head.pins.contains { $0.id == row }
            ? FieldMenu.Placing(shows: placement.shows(row), canMoveUp: false, canMoveDown: false, isPinned: true)
            : nil)
        let menu = FieldMenu(
            row: row, type: type, placing: placing, catalogue: catalogue, editsValue: editsValue, reachesServer: library.reachesServer)
        guard !menu.sections.isEmpty || menu.lockText != nil else { return }
        let (popup, keeping) = FieldMenuPresenter.build(menu, typeLabel: type?.label ?? "") { [weak editor] command in
            guard let editor, editor.isShowing(id) else { return }
            switch command {
            case .editValue:
                openValue(of: row, in: id, under: rect, library: library, drafts: drafts, undoManager: undoManager, editor: editor)
            case .rename, .editChoices:
                guard let type else { return }
                drafts.fieldEdit = FieldEditRequest(kind: command == .rename ? .rename : .choices, type: type, key: row)
            case .remove:
                let title = String(localized: "Couldn’t Remove the Field")
                guard let type else {
                    library.notices.tell(title, FieldEditRefusal.unknownField.message)
                    return
                }
                let plan: FieldEditPlan
                do throws(FieldEditRefusal) {
                    plan = try type.plan(.remove(key: row), in: catalogue)
                } catch {
                    library.notices.tell(title, error.message)
                    return
                }
                FieldRemoval.confirm(plan, typeLabel: type.label, on: NSApp.keyWindow) {
                    Task {
                        if let failure = await library.editField(plan) {
                            library.notices.tell(title, failure.message)
                        }
                    }
                }
            case .showWhenSet, .alwaysShow, .hide:
                let shows: RowShows = command == .showWhenSet ? .whenSet : command == .alwaysShow ? .always : .hidden
                PagePlacements.update { $0.setShows(shows, row: row, of: item.type) }
            case .pin:
                PagePlacements.update { $0.pin(row, of: item.type, in: catalogue) }
            case .unpin:
                PagePlacements.update { $0.unpin(row, of: item.type, in: catalogue) }
            case .moveUp, .moveDown:
                PagePlacements.update { $0.move(row, by: command == .moveUp ? -1 : 1, in: order, of: item.type) }
            }
        }
        editor.popUp(popup, under: rect, keeping: keeping)
    }

    /// The editor for one of the item's values, which writes as a form row does: through the
    /// library. The panel says why a write is refused.
    private static func request(
        _ kind: ValueEditKind, of id: ItemID, in library: any ItemLibrary, undoManager: UndoManager?, editor: EditorController
    ) -> ValueEditRequest {
        var request = ValueEditRequest(kind: kind, library: library, item: id, undoManager: undoManager)
        request.write = { value in
            guard let key = kind.field?.key else { return false }
            return library.setItemProperty(id, key: key, value: value, undoManager: undoManager)
        }
        request.open = { [weak editor] in editor?.follow($0) }
        return request
    }

    /// What the status menu offers: the catalogue's values, and the item's own if it holds one the catalogue does
    /// not list, so the menu always shows what is set.
    static func statusChoices(of item: Item, in field: ItemTypeInfo.Field) -> [String] {
        field.options(including: PageHead.statusValue(of: item, in: field))
    }

    private static func parent(in relationships: [ItemRelationship]) -> ItemRelationship? {
        relationships.first { $0.field == PagePlacement.parent }
    }
}
