import Foundation
import Marfa

/// New items typed in place (`InPlaceRow`), and the rows held where they were seen until they are left (`RowHold`).
extension Browser {
    // MARK: Starting a row

    /// Whether the open layout has a row to type a new item in: a table or a board of a place that lists items, and no
    /// search, whose results are not where an item is made. A place of files has none, since a file is never typed.
    func typesInPlace(in library: any ItemLibrary) -> Bool {
        guard showsCollection, !showsPlaceIndex, !isSearching, shown.listsItems else { return false }
        if shown.view == .own, case .type(let type) = shown.place, library.catalogue.isFileType(type) { return false }
        return viewMode == .table || viewMode == .board
    }

    /// Puts the caret in the layout's row for a new item, as New does where the layout has one: the table's last row, in
    /// the group under the pointer or the first, or the top of the board's first lane that takes a card. Answers
    /// whether it did, so New opens the line where it did not.
    @discardableResult
    func beginInPlace(in library: any ItemLibrary) -> Bool {
        guard typesInPlace(in: library), QuickAdd.isAvailable(in: library) else { return false }
        switch viewMode {
        case .table:
            let content = tableContent(in: library)
            let group = content.grouping == nil ? nil : rowHold.pointer?.group ?? content.groups.first?.id
            return beginInPlace(.table(group: group), in: library)
        case .board:
            guard let lane = boardLanes(in: library).flatMap({ shownBoardLanes($0).first(where: \.takesItems) }) else { return false }
            return beginInPlace(.lane(lane.id), in: library)
        default:
            return false
        }
    }

    /// Starts, or moves, the row for a new item to `spot`, with the keyboard.
    @discardableResult
    func beginInPlace(_ spot: InPlaceRow.Spot, in library: any ItemLibrary) -> Bool {
        guard QuickAdd.isAvailable(in: library) else { return false }
        let moved = inPlace.draft != nil && inPlace.place == shown && inPlace.spot != spot
        inPlace.begin(spot, in: shown, library: library) { inPlaceDraft(for: spot, in: library) }
        guard inPlace.draft != nil else { return false }
        if moved { inPlace.change { inPlaceValues(&$0, at: spot, in: library) } }
        inPlace.isEditing = true
        return true
    }

    /// Brings back the row's typed draft for the layout of the place shown, out of the keyboard's way, as the layout
    /// appears. A board's draft comes back in the lane its value names, or the first.
    func restoreInPlace(_ spot: InPlaceRow.Spot, in library: any ItemLibrary) {
        guard typesInPlace(in: library), inPlace.place != shown else { return }
        inPlace.restore(spot, in: shown, library: library)
    }

    /// Brings back a block typed on the calendar's week and left, at the time its draft holds.
    func restoreCalendarBlock(in library: any ItemLibrary) {
        guard viewMode == .calendar, inPlace.place != shown else { return }
        inPlace.restore(.block(start: .distantPast, end: .distantPast), in: shown, library: library)
        guard inPlace.place == shown, let draft = inPlace.draft else { return }
        guard let key = blockDateKey(of: draft.typeID, in: library),
              let start = draft.properties[key]?.string.flatMap({ ItemDate.parse($0)?.date }) else {
            // A block whose time is gone is typed again from the line, never lost.
            return handInPlaceToTextForm(in: library)
        }
        let end = draft.properties[MarfaMapping.endField]?.string.flatMap { ItemDate.parse($0)?.date } ?? start.addingTimeInterval(3600)
        inPlace.begin(.block(start: start, end: end), in: shown, library: library) { nil }
    }

    /// A new item as the place implies it: the place's own type, else the kind New Items Are names, else the last kind
    /// made, else a note (`QuickAdd.startingType`), going where the place says, with what `spot` and the view's filters
    /// imply (`inPlaceValues`). A file is never typed in a row, so it is not offered, and a block offers only a kind
    /// whose look has a date it can hold, so its item stands at the time it was drawn; none such, and there is no block.
    func inPlaceDraft(for spot: InPlaceRow.Spot, in library: any ItemLibrary) -> QuickAdd.Draft? {
        let catalogue = library.catalogue
        var offered = QuickAdd.types(in: library).map(\.id.rawValue).filter { !QuickAdd.isFile($0, in: catalogue) }
        if case .block = spot { offered = offered.filter { blockDateKey(of: $0, in: library) != nil } }
        let recent = NewItemRecents.stored(for: library.serverKey, in: defaults).kinds.first
        guard let type = QuickAdd.startingType(
            asked: nil, place: shown, chosen: NewItemType.stored(in: defaults), remembered: recent, offered: offered, in: catalogue)
        else { return nil }
        var draft = QuickAdd.Draft(typeID: type)
        draft.tier = QuickAdd.startingTier(in: shown.place)
        draft.prefilled = QuickAdd.prefill(of: type, in: catalogue)
        draft.properties = draft.prefilled
        inPlaceValues(&draft, at: spot, in: library)
        return draft
    }

    /// The field a block's time is written to for an item of `typeID`: the date field the calendar places by, else its look's
    /// date, where the kind has that field.
    private func blockDateKey(of typeID: String, in library: any ItemLibrary) -> String? {
        let key: String
        switch calendarDating(in: library) {
        case .field(let chosen): key = chosen
        case .eachType:
            guard case .field(let usual)? = looks(in: library)[TypeID(typeID)]?.date else { return nil }
            key = usual
        case .nothing: return nil
        }
        return QuickAdd.fields(of: typeID, in: library.catalogue).contains { $0.key == key } ? key : nil
    }

    /// What a row's place implies, written into `draft` as values the person did not type (`QuickAdd.Draft.prefilled`),
    /// so a row holding only them holds nothing: a field's one value that the view's filters ask for with "is", the
    /// lane's value, the group's value, and the block's time. A parent the filters ask for joins only as the item is
    /// added or handed on (`withImpliedParent`), since a parent is the person's work in a draft. A value the draft's kind
    /// cannot hold is passed over; the item is made anyway, and may then stand outside the view, held where it was typed
    /// until left.
    func inPlaceValues(_ draft: inout QuickAdd.Draft, at spot: InPlaceRow.Spot, in library: any ItemLibrary) {
        let catalogue = library.catalogue
        let keys = Set(QuickAdd.fields(of: draft.typeID, in: catalogue).map(\.key))
        for clause in tableOptions[shown]?.filter.clauses ?? [] where clause.op == .is && clause.values.count == 1 {
            guard let value = clause.values.first, !value.isEmpty else { continue }
            if let key = ItemTableColumn.fieldKey(of: clause.field), keys.contains(key) {
                if let group = FilterClause.group(of: value) {
                    set(&draft, lane: .group(group), key: key, in: catalogue)
                } else {
                    set(&draft, lane: .option(value), key: key, in: catalogue)
                }
            }
        }
        switch spot {
        case .table(let group?):
            let content = tableContent(in: library)
            guard let column = content.grouping, let key = column.field?.key else { break }
            if content.groupMode == .statusGroups {
                if case .group(let status)? = StatusBucket(id: group) { set(&draft, lane: .group(status), key: key, in: catalogue) }
            } else if !group.isEmpty, column.field?.isPicked == true {
                set(&draft, lane: .option(group), key: key, in: catalogue)
            }
        case .table(nil):
            break
        case .lane(let lane):
            set(&draft, lane: lane, key: boardLanes(in: library)?.key ?? "", in: catalogue)
        case .block(let start, let end):
            guard let key = blockDateKey(of: draft.typeID, in: library) else { break }
            draft.imply(key, .string(ItemDate.instant(start)))
            if key == MarfaMapping.startField, keys.contains(MarfaMapping.endField) {
                draft.imply(MarfaMapping.endField, .string(ItemDate.instant(end)))
            }
        }
    }

    /// `draft` with the parent the view's filters ask for with "is", where it names none and its kind may have it.
    func withImpliedParent(_ draft: QuickAdd.Draft, in library: any ItemLibrary) -> QuickAdd.Draft {
        guard draft.parentID == nil, draft.setAsideParent == nil else { return draft }
        let clause = tableOptions[shown]?.filter.clauses.first {
            $0.field == ItemTableColumn.parent.id && $0.op == .is && $0.values.count == 1
        }
        guard let value = clause?.values.first, !value.isEmpty, library.admitsCreationParent(ItemID(value), typeID: draft.typeID)
        else { return draft }
        var given = draft
        given.parentID = ItemID(value)
        return given
    }

    /// Writes into `draft` the value a card takes in `lane` (`ItemBoardLayout.move`), as a drop there would.
    private func set(_ draft: inout QuickAdd.Draft, lane: ItemBoardLane.ID, key: String, in catalogue: Catalogue) {
        let made = Item(
            id: ItemID("in-place"), type: TypeID(draft.typeID), title: draft.title, titleRule: .property("title"),
            properties: draft.properties.map { Property(key: $0.key, value: $0.value) }, version: ItemVersion(0),
            created: .now, modified: .now)
        let (writeKey, move): (String, ItemBoardLayout.Move) = if case .group(let group) = lane {
            ItemBoardLayout.move(made, toGroup: group, catalogue: catalogue)
        } else {
            (key, ItemBoardLayout.move(made, key: key, to: lane, catalogue: catalogue))
        }
        guard case .set(let value) = move else { return }
        if let value { draft.imply(writeKey, value) } else { draft.properties[writeKey] = nil; draft.prefilled[writeKey] = nil }
    }

    // MARK: Adding

    /// Adds what the row holds, as Return and leaving the row do, in one create that is one step to undo. With `next`
    /// the row starts again, empty, at the same spot; otherwise it ends. The item stands where it was typed until the
    /// row is left (`RowHold.added`). An empty row only ends. A draft the row cannot make whole, such as one missing a
    /// required value, goes to the text form with everything typed. Where the library cannot make it, everything stays
    /// as typed, and the library tells the person why.
    @discardableResult
    func addInPlace(in library: any ItemLibrary, undoManager: UndoManager?, next: Bool, now: Date = .now) async -> ItemID? {
        guard let held = inPlace.draft, let spot = inPlace.spot, !inPlace.isSaving else { return nil }
        guard held.hasContent else {
            if !next { endInPlace() }
            return nil
        }
        let typed = withImpliedParent(held, in: library)
        guard QuickAdd.canSave(typed, in: library) else {
            handInPlaceToTextForm(in: library)
            return nil
        }
        // A draft back from a quit mid-add may be in Marfa already, so it is added only once the person says so again.
        guard inPlace.mayAdd() else { return nil }
        if let parent = typed.parentID {
            let verdict = await library.newChildVerdict(under: parent)
            // Text typed while the core was asked stays as typed; nothing is made from the draft as it was.
            guard inPlace.draft == held else { return nil }
            if case .refused(let reason) = verdict {
                library.notices.tell(String(localized: "Can’t Create Item"), reason)
                return nil
            }
        }
        let made = ItemID.mint(at: now)
        guard inPlace.willCreate(made) else {
            library.notices.tell(
                String(localized: "Item Not Added"),
                String(localized: "The app couldn’t save the new item on this Mac before sending it, so nothing was added. What you typed is still there. Try again."))
            return nil
        }
        let opensGroup = undoManager?.groupingLevel == 0 && undoManager?.groupsByEvent == false
        if opensGroup { undoManager?.beginUndoGrouping() }
        let id = library.createItem(
            as: made, typeID: typed.typeID, title: typed.title, body: typed.body,
            properties: typed.properties.filter { $0.value != .null }, tags: typed.tags, parentID: typed.parentID,
            tier: typed.tier, undoManager: undoManager)
        if opensGroup { undoManager?.endUndoGrouping() }
        guard let id else {
            inPlace.notCreated()
            return nil
        }
        NewItemRecents.remember(kind: typed.typeID, tags: typed.tags, parent: typed.parentID, for: library.serverKey, in: defaults)
        newItems.append(NewItem(
            id: id, typeID: typed.typeID, library: library, caret: nil, isFile: false, collection: inPlaceCollection, opening: nil))
        rowHold.added.append(id)
        rowHold.addedIn = Self.holdGroup(of: spot)
        inPlace.added(as: id, next: next ? inPlaceDraft(for: spot, in: library) : nil, library: library)
        if !next { endInPlace() }
        finishNewItems(in: library)
        return id
    }

    /// The collection the place shows, or the one the view's filters ask for with "is", which a new item joins.
    private var inPlaceCollection: ItemID? {
        if shown.view == .own, case .collection(let id) = shown.place { return id }
        let clause = tableOptions[shown]?.filter.clauses.first {
            $0.field == ItemTableColumn.collections.id && $0.op == .is && $0.values.count == 1
        }
        return clause?.values.first.map { ItemID($0) }
    }

    /// The group a spot's added items are held in: a lane's, or the table's end.
    static func holdGroup(of spot: InPlaceRow.Spot) -> String? {
        if case .lane(let lane) = spot { ItemBoardLane.holdKey(lane) } else { nil }
    }

    /// Gives the row's draft to the text form, which asks for what the row cannot hold. What the place implied is the
    /// person's to change there, with the parent the view's filters ask for.
    private func handInPlaceToTextForm(in library: any ItemLibrary) {
        inPlace.change { draft in
            let kind = QuickAdd.prefill(of: draft.typeID, in: library.catalogue)
            draft.prefilled = draft.prefilled.filter { kind[$0.key] == $0.value }
            if let parent = withImpliedParent(draft, in: library).parentID, draft.parentID == nil { draft.setParent(parent) }
        }
        guard let entry = inPlace.entry else { return }
        inPlace.drafts.release(entry)
        let wasEditing = inPlace.isEditing
        if !openHandedNewItem(entry, in: library) {
            // The window's form holds a draft of its own; the row keeps its draft.
            _ = inPlace.drafts.take(entry, in: library.serverKey)
            inPlace.isEditing = wasEditing
            return
        }
        // The form holds the draft now, so the row lets it go without releasing the form's claim.
        inPlace.handOff()
        releaseAdded()
    }

    /// Escape in the row: an empty row goes and a typed one stays, kept, out of the keyboard's way. Either way the row is
    /// left, so what was added from it takes its place.
    func escapeInPlace() {
        inPlace.escape()
        releaseAdded()
    }

    /// Ends the row, as leaving it does once its text is added.
    func endInPlace() {
        inPlace.leave()
        releaseAdded()
    }

    /// The window goes on to another place or library, or closes: the row's draft stays kept for the next to take.
    func leaveInPlace() {
        inPlace.leave()
        rowHold = RowHold()
    }

    // MARK: Holding rows

    /// Holds the row under the pointer where it is drawn, or lets the last one go.
    func holdPointer(_ row: HeldRow?) {
        guard rowHold.pointer != row else { return }
        let moved = rowHold.releasePointer()
        rowHold.pointer = row
        if moved { rowHoldReleases += 1 }
    }

    /// The pointer went to the row `id` of a table drawn at `anchors`, or left the table's rows: the row it left goes, and
    /// the one it reached is held.
    func pointerMoved(to id: ItemID?, anchors: [ItemID: HeldRow]) {
        holdPointer(id.flatMap { anchors[$0] })
    }

    /// Holds the one row the keyboard chose where it is drawn, or lets the last one go.
    func holdKeyboard(_ row: HeldRow?) {
        guard rowHold.keyboard != row else { return }
        let moved = rowHold.releaseKeyboard()
        rowHold.keyboard = row
        if moved { rowHoldReleases += 1 }
    }

    private func releaseAdded() {
        if rowHold.releaseAdded() { rowHoldReleases += 1 }
    }
}

extension ItemBoardLane {
    /// The lane's name in a `RowHold`.
    nonisolated static func holdKey(_ id: ID) -> String { "lane:\(id)" }
}
