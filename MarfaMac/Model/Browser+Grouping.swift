import Foundation

/// One Group by for every layout and place (`GroupOffer`): what it offers, what the layout shows, and the changes the View
/// panel and the View menu make. A choice is the place's grouping (`ItemTableOptions.grouping`), kept in a place's default
/// view or written to a saved view by the window's funnel (`choicesChanged`).
extension Browser {
    /// What Group by offers in the open place and layout.
    func groupOffer(in library: any ItemLibrary, layout: ItemViewMode? = nil) -> GroupOffer {
        let mode = layout ?? viewMode
        let content = tableContent(in: library)
        if let held = groupOfferMemo, held.content === content, held.layout == mode { return held.offer }
        let offer = Cost.measure(.groupOffer) {
            GroupOffer.make(
                columns: content.columns, types: listedTypes(in: library).union(content.made.types), rows: content.allRows,
                catalogue: library.catalogue,
                layout: mode)
        }
        groupOfferMemo = GroupOfferMemo(content: content, layout: mode, offer: offer)
        return offer
    }

    struct GroupOfferMemo {
        let content: ItemTableContent
        let layout: ItemViewMode
        let offer: GroupOffer
    }

    /// How the open layout groups, as Group by shows it ticked: a board's lanes (`boardGrouping`); a list or gallery
    /// nobody has arranged in the starting order Settings > Lists gives, its date by day; otherwise the place's grouping,
    /// where a place's own is by its status's groups.
    func shownGrouping(in library: any ItemLibrary, layout: ItemViewMode? = nil) -> ItemTableOptions.Grouping {
        let layout = layout ?? viewMode
        if layout == .board { return boardGrouping(in: library) ?? .none }
        if let dated = groupingOrder(for: layout) {
            guard dated.hasSections, let column = dated.sort.first?.column else { return .none }
            return .column(column.id, by: .bucket(.day))
        }
        let content = tableContent(in: library)
        switch tableOptions[shown]?.grouping ?? .automatic {
        // A place's own grouping by status is the table's; an arranged list or gallery groups only as asked.
        case .automatic: return layout == .table ? content.grouping.map { .column($0.id, by: .statusGroups) } ?? .none : .none
        case .none: return .none
        case .column(let id, let mode): return content.grouping?.id == id ? .column(id, by: mode) : .none
        }
    }

    /// The grouping a board makes its lanes of: the place's own where the board can show it, else the status or the
    /// first field offered (`GroupOffer.fallback`), which leaves the place's choice as it is for the layouts that can.
    func boardGrouping(in library: any ItemLibrary) -> ItemTableOptions.Grouping? {
        Self.boardGrouping(in: groupOffer(in: library, layout: .board), stored: tableOptions[shown]?.grouping)
    }

    nonisolated private static func boardGrouping(in offer: GroupOffer, stored: ItemTableOptions.Grouping?) -> ItemTableOptions.Grouping? {
        if let stored, case .column = stored, offer.entry(for: stored) != nil {
            return stored
        }
        return offer.fallback
    }

    /// Groups the open place as Group by's `grouping` says. A place's list or gallery that showed the starting order keeps
    /// the order it showed, now as the place's own. A saved view's sort stays as the view holds it, since a grouping is
    /// written alone and a sort the Mac cannot show (by source, say) must not be replaced.
    func chooseGrouping(_ grouping: ItemTableOptions.Grouping, layout: ItemViewMode? = nil) {
        var options = tableOptions[shown] ?? ItemTableOptions()
        if shown.savedView == nil, let dated = groupingOrder(for: layout ?? viewMode), options.sort == nil { options.sort = dated.sort }
        options.group(by: grouping)
        tableOptions[shown] = options
    }

    /// Sorts the open place. A list or gallery that showed the starting order Settings gives keeps its sections by date
    /// where the new sort is by one of the list's own dates, now as that date by day.
    func chooseSort(_ sort: [ItemTableComparator]) {
        var options = tableOptions[shown] ?? ItemTableOptions()
        if let dated = groupingOrder(for: viewMode), options.sort == nil, dated.hasSections, let column = sort.first?.column,
           [ItemTableColumn.created.id, ItemTableColumn.edited.id].contains(column.id) {
            options.group(by: .column(column.id, by: .bucket(.day)))
        }
        options.sort = sort
        tableOptions[shown] = options
    }

    private func groupingOrder(for layout: ItemViewMode) -> ViewDraft.Dated? {
        if layout == .digest, listShape?.arranged != true {
            let order = SavedViews.datedArrangement(DigestLayout.order)
            return ViewDraft.Dated(sort: order.sort, hasSections: order.hasDateSections)
        }
        return datedList(for: layout)
    }

    /// Folds every group of the list or table, or opens them all. The window's own, kept with the place's options.
    func collapseAllGroups(in library: any ItemLibrary) {
        tableOptions[shown, default: .init()].collapsed = Set(tableContent(in: library).groups.map(\.id))
    }

    /// Folds or opens one group of the list or table.
    func toggleGroup(_ key: String, in library: any ItemLibrary) {
        var collapsed = tableContent(in: library).collapsed
        if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
        tableOptions[shown, default: .init()].collapsed = collapsed
    }

    /// How many items the arranged list holds, hidden and folded groups included, since those leave the list and not
    /// the place; nil where the list is in its starting order, which hides nothing.
    func listedCount(in library: any ItemLibrary) -> Int? {
        if let shape = listShape {
            if let table = readyTable(in: library) {
                return shape.arranged && !ordersByRelevance ? table.rows.count : table.keptItems.count
            }
        } else {
            guard listsArchive else { return nil }
            if let items = isSearching ? items(in: library) : requestPlaceItems(in: library) { return items.count }
        }
        return library.count(in: shown, favoritesScope: listing.scope)
    }

    /// Whether the arranged list is grouped and every group holding items is hidden, which says so rather than that
    /// the place is empty.
    func listHidesEveryGroup(in library: any ItemLibrary) -> Bool {
        guard let shape = listShape, shape.arranged, !ordersByRelevance, shape.options.grouping.columnID != nil else { return false }
        return readyTable(in: library)?.hidesEveryGroup == true
    }

    /// Whether the list beside the page draws no item, so the page column says why: the place lists none after its
    /// filters, or every group holding items is hidden.
    func listDrawsNoItem(in library: any ItemLibrary, order: ItemOrder) -> Bool? {
        guard let arrangement = readyArrangement(in: library, order: order, now: library.now()) else { return nil }
        return arrangement.ids.isEmpty || listHidesEveryGroup(in: library)
    }

    func expandAllGroups() {
        tableOptions[shown, default: .init()].collapsed = []
    }

    /// The groups of the open layout in order, hidden ones too, as the View panel's Group lists them: a board's lanes, else the
    /// groups of the list or table.
    func groupRows(in library: any ItemLibrary) -> [GroupRow] {
        if viewPanelLayout == .board {
            return boardLanes(in: library)?.all.map { GroupRow(key: $0.groupKey, title: $0.title, count: $0.items.count, status: $0.symbol) } ?? []
        }
        let content = tableContent(in: library)
        let field = content.grouping.flatMap { $0.isStatus ? $0.field : nil }
        return content.allGroups.map { group in
            // A status's groups carry its marks, as the board's lanes and the table's headers do; No Status has none.
            let status: StatusSymbol? = switch (field, group.value) {
            case (nil, _), (_, nil): nil
            case (_, let key?) where content.groupMode == .statusGroups: StatusGroup(rawValue: key).map { StatusSymbol(group: $0) }
            case (let field?, let word?): StatusSymbol(group: field.statusGroup(of: word))
            }
            return GroupRow(key: group.id, title: group.title, count: group.rows.count, status: status)
        }
    }

    /// One group as the View panel's Group lists it: its key, its name, how many items it holds and a status's mark.
    struct GroupRow {
        let key: String
        let title: String
        let count: Int
        var status: StatusSymbol?
    }

    /// Moves a group to where another stands, as a drag onto its row (`Reordering.moving(_:onto:in:)`): Marfa's
    /// `group.order` in a saved view, the place's own otherwise.
    func moveGroup(_ key: String, onto other: String, in library: any ItemLibrary) {
        adoptBoardGrouping(in: library)
        let drawn = groupRows(in: library).map(\.key).filter { $0 != GroupKey.notApplicable }
        // A large board's lanes are drawn from earlier work while another Mac's order may already be the place's own, so
        // the order moved is the place's current one with any lane it does not name after.
        let current = (tableOptions[shown]?.groupOrder ?? []).filter(drawn.contains)
        let order = current.isEmpty ? drawn : current + drawn.filter { !current.contains($0) }
        let moved = Reordering.moving(key, onto: other, in: order)
        guard moved != order else { return }
        tableOptions[shown, default: .init()].groupOrder = moved
    }

    /// Shows or hides one group. Its items stay in the place and count in it (`device/view-group-hidden`).
    func setGroup(_ key: String, hidden: Bool, in library: any ItemLibrary) {
        adoptBoardGrouping(in: library)
        var hiddenGroups = tableOptions[shown]?.hiddenGroups ?? []
        if hidden { hiddenGroups.insert(key) } else { hiddenGroups.remove(key) }
        tableOptions[shown, default: .init()].hiddenGroups = hiddenGroups.isEmpty ? nil : hiddenGroups
    }
}

// MARK: The board

extension Browser {
    /// A board's lanes: every lane in order, hidden ones too, the field a card moved between them changes, and whether
    /// they are Marfa's status groups, which each card reads by its own type's status.
    nonisolated struct BoardLanes: Sendable {
        var all: [ItemBoardLane]
        var key: String
        var byStatusGroups: Bool
        /// Whether the lanes are the place's own grouping, whose hidden groups then apply.
        var isOwn: Bool
        var mixesTypes: Bool
        var isEmpty: Bool
        var positions: [ItemID: Int]
    }

    /// What a board's lanes are made by, besides the items and the table.
    nonisolated struct BoardChoice: Equatable, Sendable {
        let grouping: ItemTableOptions.Grouping?
        let groupOrder: [String]?
        let asMarfa: Bool
        /// Lanes by date may say Today.
        let clock: ClockDay
    }

    /// The open board's lanes, by `boardGrouping`: a choice or status by its words with every option a lane and a card
    /// moved between them taking the word, status groups as the board of mixed types has them, and any other grouping by
    /// its groups, of which only Not Set takes a card. The place's order applies where the lanes are its own grouping.
    /// A large place's are worked out off the main actor (`placed`).
    func boardLanes(in library: any ItemLibrary) -> BoardLanes? {
        _ = placeWorkLanded
        guard let content = readyTable(in: library) else {
            return boardWork.held.flatMap {
                $0.key.derived.library == ObjectIdentifier(library) && $0.key.derived.place == shown ? $0.value : nil
            }
        }
        let options = tableOptions[shown]
        let (catalogue, calendar, now) = (library.catalogue, content.calendar, library.now())
        let choice = BoardChoice(
            grouping: options?.grouping, groupOrder: options?.groupOrder, asMarfa: isViewPlace,
            clock: ClockDay(now: now, calendar: library.calendar()))
        // The cards follow the place's sort where the person or the view set one, else their titles.
        let rows = options?.sort?.isEmpty == false ? content.rows : nil
        let kept = content.kept
        let (columns, allRows) = (content.columns, content.allRows)
        let types = listedTypes(in: library).union(content.made.types)
        return placed(boardWork, choice: choice, table: content, in: library) { items in
            let offer = GroupOffer.make(columns: columns, types: types, rows: allRows, catalogue: catalogue, layout: .board)
            guard let grouping = Self.boardGrouping(in: offer, stored: choice.grouping),
                  case .column(let id, let mode) = grouping,
                  let column = columns.first(where: { $0.id == id && $0.groups(by: mode) }) else {
                return BoardLanes(all: [], key: "", byStatusGroups: false, isOwn: false, mixesTypes: false, isEmpty: items.isEmpty, positions: [:])
            }
            let own = choice.grouping == grouping
            let order = rows.map { Dictionary($0.enumerated().map { ($1.item.id, $0) }, uniquingKeysWith: { first, _ in first }) }
            let key = column.field?.key ?? ""
            let lanes: [ItemBoardLane]
            if mode == .statusGroups {
                lanes = ItemBoardLayout.lanes(items: items, key: key, catalogue: catalogue, order: order, statusGroups: true, asMarfa: choice.asMarfa)
            } else if mode == .value, let field = column.field, ItemBoardLayout.isCompatible(field) {
                lanes = ItemBoardLayout.lanes(items: items, key: key, catalogue: catalogue, order: order, asMarfa: choice.asMarfa)
            } else {
                let groups = ItemTableLayout.groups(
                    of: kept, by: column, mode: mode, catalogue: catalogue, declared: true, asMarfa: choice.asMarfa, calendar: calendar, now: now)
                lanes = ItemBoardLayout.lanes(of: groups, mode: mode, order: order)
            }
            let all = ItemBoardLayout.arranged(lanes, order: own ? choice.groupOrder : nil, hidden: nil, hidesEmpty: false)
            var positions: [ItemID: Int] = [:]
            for lane in all {
                for (index, item) in lane.items.enumerated() { positions[item.id] = index }
            }
            return BoardLanes(
                all: all, key: key, byStatusGroups: mode == .statusGroups, isOwn: own,
                mixesTypes: Set(items.lazy.map(\.type)).count > 1, isEmpty: items.isEmpty, positions: positions)
        }
    }

    /// The lanes the board shows: less the hidden ones, and the empty ones where Hide Empty Groups is on.
    func shownBoardLanes(_ lanes: BoardLanes) -> [ItemBoardLane] {
        let hidden = lanes.isOwn ? tableOptions[shown]?.hiddenGroups : nil
        // The lane a card is typed into stays while the card is open, though Hide Empty Groups would leave it out.
        let typing: ItemBoardLane.ID? = if inPlace.place == shown, case .lane(let id)? = inPlace.spot { id } else { nil }
        return ItemBoardLayout.arranged(lanes.all, order: nil, hidden: hidden, hidesEmpty: hidesEmptyGroups, keeping: typing)
    }

    /// A board showing a grouping the place does not hold (`boardGrouping`'s fallback) takes it as the place's own before
    /// its lanes are ordered or hidden, so the order names the lanes it was made on.
    private func adoptBoardGrouping(in library: any ItemLibrary) {
        guard viewPanelLayout == .board, let shown = boardGrouping(in: library), shown != tableOptions[self.shown]?.grouping else { return }
        chooseGrouping(shown, layout: .board)
    }
}
