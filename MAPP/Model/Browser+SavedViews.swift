import Foundation

/// Following the saved view a window shows: its order, grouping, filters and timeline date from Marfa, and its
/// layout, columns, cards and rows from this Mac (`ViewLayouts`). What the person changes is written as they change it:
/// to Marfa for what Marfa holds (`Browser+ViewWrites`), and to this Mac for what the Mac holds.
extension Browser {
    /// The order, grouping and filters a view was last read with, the date its timeline showed, the types it showed as
    /// a Type filter, the version of the view they came from, which a write of them is based on, and the settings the
    /// Mac holds for it.
    struct ViewSeed: Hashable {
        let version: Int64
        let options: ItemTableOptions
        let timelineDate: String?
        let types: [String]?
        /// What to read the view's items with while the window's filters differ from these (`previewQuery`); nil where
        /// the view's own list stands for them.
        let preview: LibraryViewQuery?
        /// What this Mac holds for the view, as the window shows it.
        var mac: ViewMacSettings
    }

    /// Shows a view's own order, grouping and filters the first time the window opens it, and again when the view
    /// changes, unless the window holds choices Marfa has not taken (a write that failed): those stay, and the next
    /// write carries them. Every layout shows them, and the view opens in the layout this Mac keeps for it.
    func followView(in library: any ItemLibrary) {
        guard case .view(let id) = item, let view = library.views.first(where: { $0.id == id }) else { return }
        if pendingViewWrites.remove(id) != nil { scheduleWrite(of: id) }
        guard let seed = viewSeeds[id] else {
            apply(layout: ViewLayouts.stored(in: defaults).settings(for: id)?.layout, in: library)
            return self.seed(view, catalogue: library.catalogue)
        }
        apply(layout: seed.mac.layout, in: library)
        guard seed.version != view.version, !differs(id, from: seed) else { return }
        self.seed(view, catalogue: library.catalogue)
    }

    /// Takes the view as the library holds it for the window's choices, or, with `keepingWindow`, only for the
    /// version and options the next write is compared with.
    func seed(_ view: LibraryView, catalogue: Catalogue, keepingWindow: Bool = false) {
        let place = SidebarItem.view(view.id)
        var options = ViewDraft.options(for: view, catalogue: catalogue)
        let timelineDate = ViewDraft.timelineDate(of: view)
        let collapsed = tableOptions[place]?.collapsed
        let mac = viewSeeds[view.id]?.mac ?? ViewLayouts.stored(in: defaults).settings(for: view.id) ?? ViewMacSettings()
        let types = ViewDraft.seededTypes(of: view.query, catalogue: catalogue)
        viewSeeds[view.id] = ViewSeed(
            version: view.version, options: options, timelineDate: timelineDate, types: types,
            preview: ViewDraft.previewQuery(of: view.query, seededTypes: types, catalogue: catalogue), mac: mac)
        guard !keepingWindow else { return }
        options.collapsed = collapsed
        tableOptions[place] = options
        timelineFields[place] = timelineDate
        observedChoices[place] = ViewChoices(options: options, timelineDate: timelineDate)
    }

    private func differs(_ id: ItemID, from seed: ViewSeed) -> Bool {
        let place = SidebarItem.view(id)
        return ViewDraft.differs(
            tableOptions[place], timelineDate: timelineFields[place], from: seed.options, seedTimelineDate: seed.timelineDate,
            dated: datedList?.sort)
    }

    /// Shows the layout without taking it for a change of the person's, which only the person's own choice is.
    private func apply(layout: ItemViewMode?, in library: any ItemLibrary) {
        guard let layout, layout != viewMode, availableViewModes(in: library).contains(layout) else { return }
        set(layout: layout)
    }

    func set(layout: ItemViewMode) {
        isApplyingLayout = true
        defer { isApplyingLayout = false }
        viewMode = layout
    }

    /// Whether the window's filters, order, grouping or timeline date differ from those Marfa holds for the view it
    /// shows, which is so only while a write has not been taken (the server could not be reached, or refused it).
    var hasViewChanges: Bool {
        guard case .view(let id) = item, let seed = viewSeeds[id] else { return false }
        return differs(id, from: seed)
    }

    /// The query the window reads the view's items with while its filters differ from the view's own, and nil while
    /// they do not: the view's list is then the library's own reading of the saved view. A window that opened the
    /// view keeps the query of that version, whatever the view has since become elsewhere, as it keeps its filters.
    var viewPreview: (view: ItemID, query: LibraryViewQuery)? {
        guard case .view(let id) = item, let seed = viewSeeds[id], let query = seed.preview,
              (tableOptions[item] ?? ItemTableOptions()).filterChoices != seed.options.filterChoices else { return nil }
        return (id, query)
    }

    /// The list's own order, from where the app keeps it.
    var storedOrder: NoteOrder {
        let sort = defaults.string(forKey: OrderKey.sort).flatMap(NoteSort.init(rawValue:)) ?? NoteOrder().sort
        let groups = defaults.object(forKey: OrderKey.groupsByDate) as? Bool ?? NoteOrder().groupsByDate
        return NoteOrder(sort: sort, groupsByDate: groups)
    }

    /// What the list or gallery shows while neither the person nor the view arranged it: the list's own order. Nil in
    /// every other layout, and once a sort or a column to group by orders it.
    var datedList: ViewDraft.Dated? {
        guard !SavedViews.isArranged(self) else { return nil }
        let arrangement = SavedViews.datedArrangement(storedOrder)
        return ViewDraft.Dated(sort: arrangement.sort, hasSections: arrangement.grouping == .date)
    }

    // MARK: This Mac's settings for a view

    /// The layout, columns, empty groups, cards and density the window shows for a view, which are what the Mac holds.
    func macSettings(for id: ItemID) -> ViewMacSettings {
        viewSeeds[id]?.mac ?? ViewLayouts.stored(in: defaults).settings(for: id) ?? ViewMacSettings()
    }

    /// Whether the board leaves out a lane with no items: a saved view's choice.
    var hidesEmptyGroups: Bool {
        guard case .view(let id) = item else { return false }
        return macSettings(for: id).hidesEmptyGroups
    }

    /// What the gallery draws on each card in the open place: a saved view's choice, else the window's own for the place.
    var cards: ViewCards {
        if case .view(let id) = item { macSettings(for: id).cards } else { placeCards[item] ?? ViewCards() }
    }

    /// How much each row of the list says in the open place: a saved view's own, else the one this Mac keeps for the
    /// place. Nil follows Settings.
    var density: Density? {
        _ = densityRevision
        if case .view(let id) = item { return macSettings(for: id).density }
        return placeDensities.density(for: item)
    }

    /// The densities this Mac keeps for places, read once and kept until one changes.
    private var placeDensities: PlaceDensities {
        if let densityMemo { return densityMemo }
        let read = PlaceDensities.stored(in: defaults)
        densityMemo = read
        return read
    }

    /// Changes the open place's density, where nil follows Settings. A saved view's is kept on this Mac as it is made,
    /// like the view's other Mac settings, and a place's is kept for the place. Undo takes either back.
    func changeDensity(_ density: Density?) {
        if case .view(let id) = item {
            changeViewSettings(id) { $0.density = density }
            return
        }
        let before = self.density
        let place = item
        guard density != before else { return }
        store(density, for: place)
        registerUndo(String(localized: "Change Density")) { browser in
            guard browser.item == place else { return }
            browser.changeDensity(before)
        }
    }

    /// Keeps a place's density, which a list reading it is told of.
    func store(_ density: Density?, for place: SidebarItem) {
        PlaceDensities.update(in: defaults) { $0.set(density, for: place) }
        densityMemo = nil
        densityRevision += 1
    }

    /// Changes what the gallery draws on each card. A saved view's change is kept on this Mac as it is made, and a
    /// place's lasts as long as the window. Undo takes either back.
    func changeCards(_ change: (inout ViewCards) -> Void) {
        if case .view(let id) = item {
            changeViewSettings(id) { change(&$0.cards) }
        } else {
            let before = placeCards[item] ?? ViewCards()
            var cards = before
            change(&cards)
            guard cards != before else { return }
            setPlaceCards(cards, before: before, in: item)
        }
    }

    private func setPlaceCards(_ cards: ViewCards, before: ViewCards, in place: SidebarItem) {
        placeCards[place] = cards == ViewCards() ? nil : cards
        registerUndo(String(localized: "Change Cards")) { browser in
            guard browser.item == place else { return }
            browser.setPlaceCards(before, before: cards, in: place)
        }
    }

    /// Changes this Mac's settings for a view, and keeps them at once. Undo puts the earlier ones back.
    func changeViewSettings(_ id: ItemID, _ change: (inout ViewMacSettings) -> Void) {
        let before = macSettings(for: id)
        var settings = before
        change(&settings)
        guard !settings.sameChoices(as: before) else { return }
        keep(settings, for: id)
        registerUndo(String(localized: "Change View")) { browser in
            guard browser.item == .view(id) else { return }
            browser.changeViewSettings(id) { $0.take(choicesOf: before) }
        }
    }

    /// Stores a view's settings on this Mac, keeping the widths the table recorded.
    func keep(_ settings: ViewMacSettings, for id: ItemID) {
        var kept = settings
        ViewLayouts.update(in: defaults) {
            kept.widths = $0.settings(for: id)?.widths
            $0.set(kept, for: id)
        }
        viewSeeds[id]?.mac = kept
    }

    /// Takes the person's own change of layout, which a view keeps on this Mac at once. Undo goes back to the layout
    /// the window showed.
    func recordLayout(from old: ItemViewMode) {
        guard !isApplyingLayout else { return }
        guard case .view(let id) = item else {
            registerPlaceLayoutUndo(in: item, from: old, to: viewMode)
            return
        }
        let before = macSettings(for: id)
        var settings = before
        settings.layout = viewMode
        guard settings != before else { return }
        keep(settings, for: id)
        registerLayoutUndo(of: id, from: old, to: viewMode, mac: before)
    }

    /// A place that is not a view holds its layout only in the window, and Undo puts the earlier one back.
    private func registerPlaceLayoutUndo(in place: SidebarItem, from old: ItemViewMode, to new: ItemViewMode) {
        registerUndo(String(localized: "Change Layout")) { browser in
            guard browser.item == place else { return }
            browser.set(layout: old)
            browser.registerPlaceLayoutUndo(in: place, from: new, to: old)
        }
    }

    private func registerLayoutUndo(of id: ItemID, from old: ItemViewMode, to new: ItemViewMode, mac before: ViewMacSettings) {
        registerUndo(String(localized: "Change Layout")) { browser in
            guard browser.item == .view(id) else { return }
            let after = browser.macSettings(for: id)
            browser.set(layout: old)
            browser.keep(before, for: id)
            browser.registerLayoutUndo(of: id, from: new, to: old, mac: after)
        }
    }

    /// Keeps the table's column widths as the person drags them.
    func keepWidths(_ widths: Data?, of id: ItemID) {
        ViewLayouts.update(in: defaults) {
            var settings = $0.settings(for: id) ?? ViewMacSettings()
            guard settings.widths != widths else { return }
            settings.widths = widths
            $0.set(settings, for: id)
        }
    }

    // MARK: Putting the window back to the view

    /// Puts the window back to the view as the library holds it, dropping a choice Marfa has not taken.
    func revertView(in library: any ItemLibrary) {
        guard case .view(let id) = item else { return }
        viewRefused(id, in: library)
    }

    /// The change that writes the window's choices to the view it shows, the version it is based on, and what of
    /// the window it leaves out.
    func viewUpdate(_ window: ViewDraft.Window, in library: any ItemLibrary) -> ViewUpdate? {
        guard case .view(let id) = item, let seed = viewSeeds[id], let view = library.views.first(where: { $0.id == id }) else {
            return nil
        }
        let update = ViewDraft.change(
            window, options: tableOptions[item], seed: seed.options, seedTimelineDate: seed.timelineDate, seededTypes: seed.types,
            view: view, catalogue: library.catalogue)
        return ViewUpdate(view: view, change: update.change, baseVersion: seed.version, unkept: update.unkept)
    }

    struct ViewUpdate {
        let view: LibraryView
        let change: LibraryViewChange
        let baseVersion: Int64
        /// What of the window the view will not keep.
        let unkept: [ViewDraft.Unkept]
    }

    /// A write refused because the view changed elsewhere, or a revert, puts the window back to the view as the
    /// library holds it (its next version when that arrives), in the layout the Mac keeps for it.
    func viewRefused(_ id: ItemID, in library: any ItemLibrary) {
        viewSeeds[id] = nil
        followView(in: library)
    }

    /// Forgets a view this window deleted, and what the Mac kept for it. Only a delete from here forgets the Mac's
    /// settings: a view missing from a list proves nothing, since a read that failed publishes an empty one.
    func forgetView(_ id: ItemID) {
        viewSeeds[id] = nil
        ViewLayouts.update(in: defaults) { $0.forget(id) }
    }

    /// Deletes the view for good, once the person confirmed. Nothing of it stays on this Mac, and its panel closes
    /// with nothing said: the person did this.
    func deleteView(_ id: ItemID, in library: any ItemLibrary) async {
        deletingView = nil
        viewsBeingDeleted.insert(id)
        defer { viewsBeingDeleted.remove(id) }
        guard await library.deleteView(id) else { return }
        if viewPanel?.viewID == id { viewPanel = nil }
        forgetView(id)
    }
}
