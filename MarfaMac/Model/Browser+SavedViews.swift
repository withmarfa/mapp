import Foundation
import Marfa

/// Following the saved view a window shows: its order, grouping, filters and timeline date from Marfa, and its
/// layout, columns, cards and rows from this Mac (`ViewLayouts`). What the person changes is written as they change it:
/// to Marfa for what Marfa holds (`Browser+ViewWrites`), and to this Mac for what the Mac holds.
extension Browser {
    /// Whether the open place is a saved view, whose sort and group the list and the gallery take.
    var isViewPlace: Bool {
        shown.savedView != nil
    }

    static var initialDefaults: UserDefaults {
        #if DEBUG
        if TestHost.isRequested { return ThrowawayDefaults.make("MarfaMac.Browser") }
        #endif
        return .standard
    }

    /// The order, grouping and filters a view was last read with, the date its timeline showed, the types it showed as
    /// a Type filter, the version of the view they came from, which a write of them is based on, and the settings the
    /// Mac holds for it.
    struct ViewSeed: Hashable {
        let version: Int64
        var options: ItemTableOptions
        /// The filters as the view says them, which `options` may say in the window's own form (`writeChoices`).
        let viewFilter: FilterState
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
        guard let id = shown.savedView else { return }
        guard let view = library.views.first(where: { $0.id == id }) else {
            // A view deleted elsewhere falls to the first view of its row. An empty list proves nothing, since a read
            // that failed publishes one.
            if !library.views.isEmpty, !viewsBeingDeleted.contains(id) { showing = firstView(of: shown.place, in: library) }
            return
        }
        // A change of the view's filters can move it to another home, and the window goes with it.
        let home = PlaceView(Place.home(of: view.query, catalogue: library.catalogue), .saved(id))
        if showing != home { showing = home }
        // A change the store is sending lands in the window by itself (`Browser.pendingChangeLanded`).
        if pendingViewWrites.remove(id) != nil, !PendingViewChanges.isSending(id) { scheduleWrite(of: id) }
        // A new view's draft made from this view holds the window's choices and layout until it is made or dropped,
        // and the window follows the view again then (`dropNewViewPanel`).
        guard newViewPanel(from: id) == nil else { return }
        defer { noteOpened(view) }
        guard let seed = viewSeeds[id] else {
            apply(layout: ViewLayouts.stored(in: defaults).settings(for: id)?.layout, in: library)
            return self.seed(view, catalogue: library.catalogue)
        }
        apply(layout: seed.mac.layout, in: library)
        guard seed.version != view.version, !differs(id, from: seed) else { return }
        self.seed(view, catalogue: library.catalogue)
    }

    /// Takes the view as the library holds it for the window's choices, or, with `keepingWindow`, as a write `sent`
    /// returned it: the window then keeps each setting the person changed, and the next write is compared with the view.
    func seed(
        _ view: LibraryView, catalogue: Catalogue, keepingWindow: Bool = false, sent: LibraryViewChange = LibraryViewChange()
    ) {
        let place = PlaceView.saved(view.id)
        var options = ViewDraft.options(for: view, catalogue: catalogue)
        let timelineDate = ViewDraft.timelineDate(of: view)
        let collapsed = tableOptions[place]?.collapsed
        let earlier = viewSeeds[view.id]
        let mac = earlier?.mac ?? ViewLayouts.stored(in: defaults).settings(for: view.id) ?? ViewMacSettings()
        let types = ViewDraft.seededTypes(of: view.query, catalogue: catalogue)
        viewSeeds[view.id] = ViewSeed(
            version: view.version, options: options, viewFilter: options.filter, timelineDate: timelineDate, types: types,
            preview: ViewDraft.previewQuery(of: view.query, seededTypes: types, catalogue: catalogue), mac: mac)
        guard !keepingWindow else {
            // A new view's draft made from the view holds the window; Cancel shows what the view became.
            if let earlier, newViewPanel(from: view.id) == nil {
                follow(ViewChoices(options: options, timelineDate: timelineDate), of: view, in: place, over: earlier, sent: sent)
            }
            return
        }
        options.collapsed = collapsed
        tableOptions[place] = options
        timelineFields[place] = timelineDate
        observedChoices[place] = ViewChoices(options: options, timelineDate: timelineDate)
        // The view as Marfa now holds it is what Revert View goes back to for each setting this window did not change.
        if openedView?.id == view.id {
            var parts = Set(ViewChoices.Part.allCases)
            // Filters the view says as before, perhaps in other words than the window's, are no other app's change.
            if let earlier, options.filter.isSame(as: earlier.viewFilter) { parts.remove(.filters) }
            openedView?.follow(parts, of: ViewChoices(options: options, timelineDate: timelineDate), raw: view)
        }
    }

    /// Cancel of a new view's draft made from the view shows the view as opening it does: the settings this Mac stores
    /// for it, and each setting a write returned meanwhile that the person had not changed before the draft.
    func followView(_ id: ItemID, after snapshot: ViewPanel.Snapshot, in library: any ItemLibrary) {
        viewSeeds[id]?.mac = ViewLayouts.stored(in: defaults).settings(for: id) ?? ViewMacSettings()
        if let opened = snapshot.seed, let now = viewSeeds[id], now.version != opened.version,
           let view = library.views.first(where: { $0.id == id }) {
            follow(ViewChoices(options: now.options, timelineDate: now.timelineDate), of: view, in: .saved(id), over: opened, sent: LibraryViewChange())
        }
        followView(in: library)
    }

    /// Keeps the view as the window first shows it, for Revert View, until the window shows another place.
    private func noteOpened(_ view: LibraryView) {
        guard openedView?.id != view.id, viewSeeds[view.id] != nil else { return }
        var mac = macSettings(for: view.id)
        mac.layout = viewMode
        openedView = OpenedView(id: view.id, choices: choices(in: .saved(view.id)), mac: mac, raw: view)
    }

    /// Whether the person changed the view the window shows since the window opened it, which Revert View takes back.
    var isViewChanged: Bool {
        guard let opened = openedView, shown.isSame(.saved(opened.id)) else { return false }
        var mac = macSettings(for: opened.id)
        mac.layout = viewMode
        return !liveChoices.parts(differingFrom: opened.choices).isEmpty || !mac.sameChoices(as: opened.mac)
    }

    /// Whether Revert View is offered: never while a new view's draft made from the view holds the window.
    var canRevertView: Bool {
        guard let id = openedView?.id else { return false }
        return newViewPanel(from: id) == nil && isViewChanged
    }

    /// Shows the settings of a view a write returned that the person has not changed since `earlier`, the seed the
    /// write was compared with, and that the write did not send. The server may have merged another app's change to one
    /// (`views/change-stale`); left out of the window, it would read as the person's own change, and the next write would
    /// send the window's older value back over it. A setting the person changed stays as they chose it, and is written.
    private func follow(
        _ returned: ViewChoices, of view: LibraryView, in place: PlaceView, over earlier: ViewSeed, sent: LibraryViewChange
    ) {
        let held = ViewChoices(options: earlier.options, timelineDate: earlier.timelineDate)
        let dated = shown.isSame(place) ? datedList : nil
        var parts = Set(ViewChoices.Part.allCases).subtracting(choices(in: place).parts(differingFrom: held, dated: dated))
        if sent.sort != nil { parts.remove(.sort) }
        if sent.group != nil { parts.remove(.grouping) }
        if sent.query != nil { parts.subtract([.filters, .listing]) }
        // Filters the view says as before, though in other words than the window's, are not another app's change.
        if returned.options.filter.isSame(as: earlier.viewFilter) { parts.remove(.filters) }
        parts = parts.intersection(choices(in: place).parts(differingFrom: returned, dated: dated))
        guard !parts.isEmpty else { return }
        put(returned, in: place, only: parts)
        if openedView?.id == place.savedView { openedView?.follow(parts, of: returned, raw: view) }
        // Not the person's change: no step of Undo, and nothing to write.
        if var observed = observedChoices[place] {
            observed.take(parts, from: returned)
            observedChoices[place] = observed
        }
    }

    private func differs(_ id: ItemID, from seed: ViewSeed) -> Bool {
        let place = PlaceView.saved(id)
        return ViewDraft.differs(
            tableOptions[place], timelineDate: timelineFields[place], from: seed.options, seedTimelineDate: seed.timelineDate,
            dated: datedList)
    }

    /// Shows the layout without taking it for a change of the person's, which only the person's own choice is.
    func apply(layout: ItemViewMode?, in library: any ItemLibrary) {
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
        guard let id = shown.savedView, let seed = viewSeeds[id] else { return false }
        return differs(id, from: seed)
    }

    /// The query the window reads the view's items with while its filters, From or Archived Items differ from the
    /// view's own, and nil while they do not: the view's list is then the library's own reading of the saved view. A
    /// window that opened the view keeps the query of that version, whatever the view has since become elsewhere, as it
    /// keeps its filters, and reads the tiers and states the window chose.
    var viewPreview: (view: ItemID, query: LibraryViewQuery)? {
        guard let id = shown.savedView, let seed = viewSeeds[id], var query = seed.preview else { return nil }
        let options = tableOptions[shown] ?? ItemTableOptions()
        let listing = listing(in: shown)
        let viewScope = seed.options.scope ?? .all, viewArchived = seed.options.archived ?? .hidden
        guard !options.filter.isSame(as: seed.options.filter) || listing.scope != viewScope || listing.archived != viewArchived
        else { return nil }
        query.tier = listing.scope.tier
        query.states = listing.archived.states
        return (id, query)
    }

    /// The list's own order, from where the app keeps it.
    var storedOrder: ItemOrder {
        let sort = defaults.string(forKey: OrderKey.sort).flatMap(ItemSort.init(rawValue:)) ?? ItemOrder().sort
        let groups = defaults.object(forKey: OrderKey.groupsByDate) as? Bool ?? ItemOrder().groupsByDate
        return ItemOrder(sort: sort, groupsByDate: groups)
    }

    /// What the list or gallery shows while neither the person nor the view arranged it: the list's own order. Nil in
    /// every other layout, and once a sort or a column to group by orders it.
    var datedList: ViewDraft.Dated? {
        datedList(for: viewMode)
    }

    func datedList(for layout: ItemViewMode) -> ViewDraft.Dated? {
        guard !SavedViews.isArranged(self, layout: layout) else { return nil }
        let arrangement = SavedViews.datedArrangement(storedOrder)
        return ViewDraft.Dated(sort: arrangement.sort, hasSections: arrangement.hasDateSections)
    }

    // MARK: This Mac's settings for a view

    /// The settings the window uses for the saved view, or those of the draft made from it.
    func macSettings(for id: ItemID) -> ViewMacSettings {
        newViewPanel(from: id)?.mac ?? viewSeeds[id]?.mac ?? ViewLayouts.stored(in: defaults).settings(for: id) ?? ViewMacSettings()
    }

    /// The panel of a new view made from the saved view `id`, which holds this Mac's settings until the view exists.
    func newViewPanel(from id: ItemID) -> ViewPanel? {
        guard let panel = viewPanel, panel.isNew, panel.mac != nil, panel.snapshot?.place.savedView == id else { return nil }
        return panel
    }

    /// Whether the open place leaves out the groups with no items, in every layout that groups: a saved view's choice
    /// in the app's settings, else the place's default view's.
    var hidesEmptyGroups: Bool {
        guard let id = shown.savedView else { return placeHidesEmptyGroups[shown] ?? false }
        return macSettings(for: id).hidesEmptyGroups
    }

    /// Changes Hide Empty Groups. A saved view's is kept in the app's settings as it is made, and a place's in its default
    /// view. Undo takes either back.
    func setHidesEmptyGroups(_ hides: Bool) {
        if let id = shown.savedView {
            changeViewSettings(id) { $0.hidesEmptyGroups = hides }
            return
        }
        let place = shown
        let before = hidesEmptyGroups
        guard hides != before else { return }
        placeHidesEmptyGroups[place] = hides ? true : nil
        updatePlaceDefault(place) { $0.hidesEmptyGroups = hides }
        registerUndo(String(localized: "Change View")) { browser in
            guard browser.shown.isSame(place) else { return }
            browser.setHidesEmptyGroups(before)
        }
    }

    /// What the gallery draws on each card in the open place: a saved view's choice, else the place's default view's.
    var cards: ViewCards {
        if let id = shown.savedView { macSettings(for: id).cards } else { placeCards[shown] ?? ViewCards() }
    }

    /// Whether the calendar shows a week or a month in the open place: a saved view's choice in the app's settings, else the
    /// place's default view's. A week until chosen.
    var calendarScale: CalendarScale {
        if let id = shown.savedView { macSettings(for: id).calendarScale ?? .week } else { placeCalendarScales[shown] ?? .week }
    }

    /// Changes the calendar's scale. A saved view's is kept in the app's settings as it is made, and a place's in its
    /// default view. Undo takes either back.
    func changeCalendarScale(_ scale: CalendarScale, calendar: Calendar = .chosenWeekStart) {
        // A week shown from a month starts where the calendar's weeks do, as a week chosen in the card does.
        if scale == .week, let day = calendarDay { calendarDay = CalendarLayout.firstDay(ofWeekHolding: day, calendar: calendar) }
        if let id = shown.savedView {
            changeViewSettings(id) { $0.calendarScale = scale }
            return
        }
        let before = calendarScale
        guard scale != before else { return }
        let place = shown
        placeCalendarScales[place] = scale
        updatePlaceDefault(place) { $0.calendarScale = scale }
        registerUndo(String(localized: "Change Calendar")) { browser in
            guard browser.shown.isSame(place) else { return }
            browser.changeCalendarScale(before)
        }
    }

    /// Moves the calendar by seven days or by months, or back to the week that holds today with `steps` nil. A week moves
    /// from the first day shown, which a swipe may have put on any day, and from the week that holds today where none was.
    func moveCalendar(by steps: Int?, now: Date, calendar: Calendar = .chosenWeekStart) {
        calendarMoves += 1
        guard let steps else {
            calendarDay = nil
            return
        }
        let scale = calendarScale
        let from = calendarDay ?? (scale == .week ? CalendarLayout.firstDay(ofWeekHolding: now, calendar: calendar) : now)
        calendarDay = CalendarLayout.moved(from, by: steps, scale: scale, calendar: calendar)
    }

    /// How much each row of the list says in the open place: a saved view's own, else the one this Mac keeps for the
    /// place. Nil follows Settings.
    var density: Density? {
        _ = densityRevision
        if let id = shown.savedView { return macSettings(for: id).density }
        return placeDensities.density(for: shown)
    }

    /// The densities this Mac keeps for places, read each time since every window shares them and another window may have
    /// changed one. A list that draws by them also watches the key (`PlaceDensities.key`), so it is drawn again then.
    private var placeDensities: PlaceDensities {
        PlaceDensities.stored(in: defaults)
    }

    /// Changes the open place's density, where nil follows Settings. A saved view's is kept in the app's settings as it is made,
    /// like the view's others, and a place's is kept for the place. Undo takes either back.
    func changeDensity(_ density: Density?) {
        if let id = shown.savedView {
            changeViewSettings(id) { $0.density = density }
            return
        }
        let before = self.density
        let place = shown
        guard density != before else { return }
        store(density, for: place)
        registerUndo(String(localized: "Change Density")) { browser in
            guard browser.shown.isSame(place) else { return }
            browser.changeDensity(before)
        }
    }

    /// Keeps a place's density, which a list reading it is told of.
    func store(_ density: Density?, for place: PlaceView) {
        PlaceDensities.update(in: defaults) { $0.set(density, for: place) }
        densityRevision += 1
    }

    /// Changes what the gallery draws on each card. A saved view's change is kept in the app's settings as it is made, and a
    /// place's in its default view. Undo takes either back.
    func changeCards(_ change: (inout ViewCards) -> Void) {
        if let id = shown.savedView {
            changeViewSettings(id) { change(&$0.cards) }
        } else {
            let before = placeCards[shown] ?? ViewCards()
            var cards = before
            change(&cards)
            guard cards != before else { return }
            setPlaceCards(cards, before: before, in: shown)
        }
    }

    private func setPlaceCards(_ cards: ViewCards, before: ViewCards, in place: PlaceView) {
        placeCards[place] = cards == ViewCards() ? nil : cards
        updatePlaceDefault(place) { $0.cards = cards }
        registerUndo(String(localized: "Change Cards")) { browser in
            guard browser.shown.isSame(place) else { return }
            browser.setPlaceCards(before, before: cards, in: place)
        }
    }

    /// Changes this Mac's settings for a view, or for the new view's draft made from it while one is open, and keeps
    /// them at once. Undo puts back only the settings this step changed, in the settings it changed: a step of the view
    /// stays the view's when a draft opens later.
    func changeViewSettings(_ id: ItemID, _ change: (inout ViewMacSettings) -> Void) {
        changeViewSettings(id, draft: newViewPanel(from: id), change)
    }

    private func changeViewSettings(_ id: ItemID, draft: ViewPanel?, _ change: (inout ViewMacSettings) -> Void) {
        guard let step = writeViewSettings(id, draft: draft, change) else { return }
        registerUndo(String(localized: "Change View"), owner: draft ?? self) { browser in
            guard browser.shown.isSame(.saved(id)) else { return }
            browser.changeViewSettings(id, draft: draft) { $0.undo(step) }
        }
    }

    /// Makes the change to the view's settings as stored now, never to the window's copy, so a choice another Mac made
    /// meanwhile stays, or to the `draft`'s (`ViewPanel.mac`). Nil where nothing changed; the window then still shows
    /// the stored settings, which may already hold the choice.
    @discardableResult
    private func writeViewSettings(
        _ id: ItemID, draft: ViewPanel?, _ change: (inout ViewMacSettings) -> Void
    ) -> (before: ViewMacSettings, after: ViewMacSettings)? {
        let before = draft?.mac ?? ViewLayouts.stored(in: defaults).settings(for: id) ?? ViewMacSettings()
        var after = before
        change(&after)
        if draft == nil { viewSeeds[id]?.mac = after }
        guard !after.sameChoices(as: before) else { return nil }
        if let draft {
            draft.mac = after
        } else {
            ViewLayouts.update(in: defaults) { $0.set(after, for: id) }
            if openedView?.id == id { openedView?.wrote(from: before, to: after) }
        }
        return (before, after)
    }

    /// A layout command changes the draft while one is open.
    func chooseLayout(_ layout: ItemViewMode) {
        guard let panel = viewPanel, let old = panel.draftLayout else {
            viewMode = layout
            return
        }
        guard old != layout else { return }
        panel.draftLayout = layout
        registerUndo(String(localized: "Change Layout")) { browser in
            browser.chooseLayout(old)
        }
    }

    /// Takes the person's own change of layout, which is kept in the app's settings at once. Undo goes back to the layout
    /// the window showed.
    func recordLayout(from old: ItemViewMode) {
        guard !isApplyingLayout else { return }
        guard let id = shown.savedView else {
            let layout = viewMode
            updatePlaceDefault(shown) { $0.layout = layout }
            registerPlaceLayoutUndo(in: shown, from: old, to: layout)
            return
        }
        let layout = viewMode
        guard let step = writeViewSettings(id, draft: nil, { $0.layout = layout }) else { return }
        registerLayoutUndo(of: id, from: old, to: layout, stored: step)
    }

    /// A place that is not a view keeps its layout in its default view, and Undo puts the earlier one back.
    private func registerPlaceLayoutUndo(in place: PlaceView, from old: ItemViewMode, to new: ItemViewMode) {
        registerUndo(String(localized: "Change Layout")) { browser in
            guard browser.shown.isSame(place) else { return }
            browser.set(layout: old)
            browser.updatePlaceDefault(place) { $0.layout = old }
            browser.registerPlaceLayoutUndo(in: place, from: new, to: old)
        }
    }

    /// A step of the view's layout is undone in its settings. An open draft keeps the window's layout until it closes.
    private func registerLayoutUndo(
        of id: ItemID, from old: ItemViewMode, to new: ItemViewMode,
        stored step: (before: ViewMacSettings, after: ViewMacSettings)
    ) {
        registerUndo(String(localized: "Change Layout"), owner: self) { browser in
            guard browser.shown.isSame(.saved(id)) else { return }
            if browser.newViewPanel(from: id) == nil { browser.set(layout: old) }
            guard let back = browser.writeViewSettings(id, draft: nil, { $0.undo(step) }) else { return }
            browser.registerLayoutUndo(of: id, from: new, to: old, stored: back)
        }
    }

    /// Keeps the table's column widths as the person drags them, in a new view's draft while one made from the view is
    /// open.
    func keepWidths(_ widths: Data, of id: ItemID) {
        if let draft = newViewPanel(from: id) {
            draft.mac?.widths = widths
            return
        }
        ViewLayouts.update(in: defaults) {
            var settings = $0.settings(for: id) ?? ViewMacSettings()
            guard settings.widths != widths else { return }
            settings.widths = widths
            $0.set(settings, for: id)
        }
        viewSeeds[id]?.mac.widths = widths
    }

    // MARK: Putting the window back to the view

    /// Puts back each setting this window changed since it opened the view, and writes it to Marfa whole, as Marfa held
    /// it then, with what the window cannot show (`OpenedView.raw`). A setting another app changed since, as Marfa holds
    /// it, stays and the person is told. One step of Undo brings the person's changes back.
    func revertView(in library: any ItemLibrary) {
        guard let id = openedView?.id, shown.isSame(.saved(id)), canRevertView else { return }
        // A change the window has not yet passed through the funnel is still its own.
        choicesChanged()
        guard let opened = openedView, let now = library.views.first(where: { $0.id == id }) else { return }
        let macKept = revertMacSettings(of: opened, in: library)
        let settings = OpenedView.settings(of: opened.changed)
        let kept = settings.filter { !opened.holdsWhatItLeft($0, in: now) }
        let reverted = settings.subtracting(kept)
        var reverting = opened.opening(reverted)
        if !kept.isEmpty {
            // The window shows the other app's value, and the write leaves Marfa's as it is.
            let current = ViewChoices(options: ViewDraft.options(for: now, catalogue: library.catalogue), timelineDate: ViewDraft.timelineDate(of: now))
            let parts = kept.reduce(into: Set<ViewChoices.Part>()) { $0.formUnion(OpenedView.parts(of: $1)) }
            put(current, in: shown, only: parts)
            openedView?.choices.take(parts, from: current)
            openedView?.changed.subtract(parts)
            for setting in kept { openedView?.take(setting, of: now) }
            if kept.contains(.sort) { reverting.sort = now.sort }
            if kept.contains(.group) { reverting.group = now.group.map { .set($0) } ?? .clear }
            if kept.contains(.query) { reverting.query = now.query }
        }
        openedView?.reverting = reverting
        put(opened.choices, in: shown, only: reverted.reduce(into: []) { $0.formUnion(OpenedView.parts(of: $1)) })
        choicesChanged()
        // The steps of one event are one step of Undo.
        undoManager?.setActionName(String(localized: "Revert View"))
        tellKept(kept, macKept: macKept, in: library)
    }

    /// Puts back each of this Mac's settings for the view that this window changed, as it was when the window opened
    /// the view, where it is still stored as this window wrote it. One changed since on another Mac stays, the window
    /// shows it, and it is no longer this window's to put back. Whether one stayed.
    private func revertMacSettings(of opened: OpenedView, in library: any ItemLibrary) -> Bool {
        let id = opened.id
        let storedSettings = ViewLayouts.stored(in: defaults).settings(for: id) ?? ViewMacSettings()
        let stored = storedSettings.leaves, opening = opened.mac.leaves
        let reverted = Set(opened.macWritten.filter { (stored[$0.key] ?? .null) == $0.value }.keys)
        let layoutPath: ViewMacSettings.Path = ["layout"]
        let layout = reverted.contains(layoutPath) ? opened.mac.layout : opened.macWritten[layoutPath] != nil ? storedSettings.layout : nil
        if let layout, layout != viewMode, availableViewModes(in: library).contains(layout) {
            // This window's own is put back as a change of the person's, so Undo shows it again; another Mac's is only shown.
            if reverted.contains(layoutPath) { viewMode = layout } else { set(layout: layout) }
        }
        let others = reverted.subtracting([layoutPath])
        if !others.isEmpty {
            changeViewSettings(id, draft: nil) { settings in
                var leaves = settings.leaves
                for path in others { leaves[path] = opening[path] }
                if let back = ViewMacSettings(leaves: leaves) { settings = back }
            }
        }
        // The window now opens on what is stored: what it put back, and what another Mac chose.
        let now = ViewLayouts.stored(in: defaults).settings(for: id) ?? ViewMacSettings()
        viewSeeds[id]?.mac = now
        openedView?.mac = now
        openedView?.mac.layout = viewMode
        openedView?.macWritten = [:]
        return reverted.count < opened.macWritten.count
    }

    private func tellKept(_ kept: Set<PendingViewChanges.Setting>, macKept: Bool, in library: any ItemLibrary) {
        guard !kept.isEmpty || macKept else { return }
        var lines = PendingViewChanges.Setting.allCases.filter(kept.contains).map { setting in
            switch setting {
            case .sort: String(localized: "Sort was changed in another app, so it was kept.")
            case .group: String(localized: "Grouping was changed in another app, so it was kept.")
            case .query: String(localized: "Filters or From were changed in another app, so they were kept.")
            }
        }
        if macKept { lines.append(String(localized: "Some layout settings were changed on another Mac, so they were kept.")) }
        library.notices.tell(String(localized: "View Partly Reverted"), lines.joined(separator: " "))
    }

    /// The change that writes the window's choices to the view it shows, the version it is based on, and what of
    /// the window it leaves out.
    func viewUpdate(_ window: ViewDraft.Window, in library: any ItemLibrary) -> ViewUpdate? {
        guard let id = shown.savedView, let seed = viewSeeds[id], let view = library.views.first(where: { $0.id == id }) else {
            return nil
        }
        let update = ViewDraft.change(
            window, options: tableOptions[shown], seed: seed.options, seedTimelineDate: seed.timelineDate, seededTypes: seed.types,
            view: view, catalogue: library.catalogue, replaced: replacedGroups[id] ?? [:])
        var change = update.change
        var unkept = update.unkept
        // A setting Revert View put back is written as Marfa held it, while the window still shows it as it opened.
        if let opened = openedView, opened.id == id, let reverting = opened.reverting {
            let differing = choices(in: shown).parts(differingFrom: opened.choices, dated: datedList)
            if let sort = reverting.sort, !differing.contains(.sort) {
                change.sort = sort == view.sort ? nil : sort
                unkept.removeAll { if case .sort = $0 { true } else { false } }
            }
            if let group = reverting.group, !differing.contains(.grouping) {
                let same = switch group {
                case .set(let group): view.group == group
                case .clear: view.group == nil
                }
                change.group = same ? nil : group
                unkept.removeAll { unkept in
                    switch unkept {
                    case .group, .groupMode: true
                    default: false
                    }
                }
            }
            if let query = reverting.query, differing.isDisjoint(with: [.filters, .listing]) {
                change.query = query == view.query ? nil : query
                unkept.removeAll { unkept in
                    switch unkept {
                    case .filter, .mixedFilters, .tooManyFilters, .refused: true
                    default: false
                    }
                }
            }
        }
        return ViewUpdate(view: view, change: change, baseVersion: seed.version, unkept: unkept)
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

    /// Delete View…, from the View menu, the palette or a pill: asks first, since a view has no bin. The View panel closes
    /// so the question is not hidden behind it.
    func askToDeleteView(_ id: ItemID, in library: any ItemLibrary) {
        guard library.views.contains(where: { $0.id == id }) else {
            return library.notices.tell(String(localized: "Can’t Delete View"), Self.deletedElsewhere)
        }
        closeViewPanel(in: library)
        deletingView = id
    }

    /// Deletes the view for good after confirmation and clears its saved layout.
    func deleteView(_ id: ItemID, in library: any ItemLibrary) async {
        deletingView = nil
        viewsBeingDeleted.insert(id)
        defer { viewsBeingDeleted.remove(id) }
        guard await library.deleteView(id) else { return }
        if viewPanel?.viewID == id { viewPanel = nil }
        forgetView(id)
        if shown.savedView == id { showing = firstView(of: shown.place, in: library) }
    }
}
