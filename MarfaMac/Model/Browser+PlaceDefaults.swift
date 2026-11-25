import Foundation

/// The default view of a place that is not a saved view: what a person changes there is kept in the app's settings
/// (`PlaceDefaults`, with the Properties list, the column widths and the density the place already keeps), so the place opens as they left
/// it, in every window and every launch. It cannot be renamed or deleted; Reset View puts it back.
///
/// Two windows on one place both write to the same entry, so the last change wins. A window shows what it holds until it
/// opens the place again, which reads the entry again, and so picks up the other window's change then.
extension Browser {
    /// Whether a place has a default view: every place a person can arrange, which is any but a saved view, whose choices
    /// are its own, and Types, Collections and Sources, which list places and have no layout to choose.
    nonisolated static func hasDefaultView(_ place: PlaceView) -> Bool {
        place.savedView == nil && place.listsItems
    }

    /// Whether the open place has a default view the window can change.
    var hasDefaultView: Bool { Self.hasDefaultView(shown) }

    /// The layout a place opens in until the person chooses one: a table for the Archive, which lists items by what they
    /// are and where they came from, and for the Library once it holds more than `libraryListLimit` items, which a new
    /// Marfa's few read better as a list; a list for any other.
    func naturalLayout(of place: PlaceView) -> ItemViewMode {
        if place == .archive { return .table }
        if place == .library, let library, library.count(in: .library) > Self.libraryListLimit { return .table }
        return .list
    }

    nonisolated static let libraryListLimit = 10

    // MARK: Keeping

    /// Changes what is kept for a place's default view. While a new view's panel is open nothing is kept: the panel
    /// shapes a view that does not exist yet, and the place goes back as it was when the panel ends.
    func updatePlaceDefault(_ place: PlaceView, _ change: (inout PlaceDefault) -> Void) {
        guard Self.hasDefaultView(place), viewPanel?.isNew != true else { return }
        PlaceDefaults.update(in: defaults) {
            var value = $0.default(for: place) ?? PlaceDefault()
            change(&value)
            $0.set(value, for: place)
        }
    }

    /// The types a place lists, whose fields a grouping may name though no item fills them: a type with its kinds where
    /// they show, and the types a saved view lists, with their subtypes. Empty for any other place, whose items' types are
    /// the ones it lists.
    func listedTypes(in library: any ItemLibrary) -> Set<TypeID> {
        let catalogue = library.catalogue
        if let id = shown.savedView {
            let types = library.views.first { $0.id == id }?.query.types ?? []
            return Set(types).union(types.flatMap { catalogue.descendants(of: $0) })
        }
        guard case .type(let type) = shown.place, shown.view == .own else { return [] }
        return listing.includesKinds ? catalogue.descendants(of: type).union([type]) : [type]
    }

    /// Keeps the open place's filters, sort, grouping and timeline date, which the window's funnel (`choicesChanged`) notes.
    func keepPlaceChoices(of place: PlaceView) {
        let options = tableOptions[place]
        let timeline = timelineFields[place]
        let catalogue = library?.catalogue
        updatePlaceDefault(place) {
            let stored = $0
            $0.keep(options)
            if let catalogue { $0.keepUnapplied(from: stored, in: place, catalogue: catalogue) }
            $0.timelineField = timeline
        }
    }

    /// Changes whether the open place's board draws compact cards, and keeps it.
    func setCompactBoard(_ isCompact: Bool, in place: PlaceView) {
        let before = compactBoards[place] ?? false
        guard before != isCompact else { return }
        compactBoards[place] = isCompact
        updatePlaceDefault(place) { $0.compactBoard = isCompact }
        registerUndo(String(localized: "Change View")) { browser in
            guard browser.shown.isSame(place) else { return }
            browser.setCompactBoard(before, in: place)
        }
    }

    // MARK: Pruning

    /// Forgets the entries of collections and types that no longer exist. The library says a thing is gone
    /// only once its copy has been read whole and is current: a type or an item missing while the copy fills, refreshes or
    /// is another server's says nothing, so then every entry stays. Items, and the types of the catalogue, outlive being
    /// in Recently Deleted, so an entry stays for those.
    func prunePlaceDefaults(in library: any ItemLibrary) {
        guard library.isLoaded, library.syncReport.phase == .current, library.syncReport.fill?.state == .complete else { return }
        let types = library.catalogue.itemTypes
        let gone = PlaceDefaults.stored(in: defaults).keptPlaces.filter { place in
            switch place.place {
            case .collection(let id): library.item(id) == nil
            case .type(let type): !types.isEmpty && types[type] == nil
            default: false
            }
        }
        guard !gone.isEmpty else { return }
        PlaceDefaults.update(in: defaults) { stored in gone.forEach { stored.set(nil, for: $0) } }
    }

    // MARK: Opening

    /// Opens the place as its default view was left: the choices, the layout and the Mac's settings for each layout. The
    /// choices are not a change of the person's, so no undo step is made of them. A condition on a field that no type of
    /// the place declares any more is dropped and the rest kept; a layout the place no longer offers is not taken. A place
    /// with nothing kept opens as it is, which is how a window that has held another's change forgets it.
    func followPlaceDefault(in library: any ItemLibrary) {
        guard hasDefaultView, library.isLoaded, viewPanel?.isNew != true else { return }
        prunePlaceDefaults(in: library)
        let place = shown
        let stored = PlaceDefaults.stored(in: defaults).default(for: place) ?? PlaceDefault()
        let options = stored.options(replacing: tableOptions[place], in: place, catalogue: library.catalogue)
        if options != (tableOptions[place] ?? ItemTableOptions()) { tableOptions[place] = options }
        if timelineFields[place] != stored.timelineField { timelineFields[place] = stored.timelineField }
        let compact: Bool? = stored.compactBoard ? true : nil
        if compactBoards[place] != compact { compactBoards[place] = compact }
        let cards: ViewCards? = stored.cards == ViewCards() ? nil : stored.cards
        if placeCards[place] != cards { placeCards[place] = cards }
        if placeCalendarScales[place] != stored.calendarScale { placeCalendarScales[place] = stored.calendarScale }
        let hides: Bool? = stored.hidesEmptyGroups ? true : nil
        if placeHidesEmptyGroups[place] != hides { placeHidesEmptyGroups[place] = hides }
        let properties: ViewProperties? = stored.properties.isChanged ? stored.properties : nil
        if placeProperties[place] != properties { placeProperties[place] = properties }
        if placeQuickActions[place] != stored.quickActions { placeQuickActions[place] = stored.quickActions }
        if placeOpenings[place] != stored.opening { placeOpenings[place] = stored.opening }
        if placeMaps[place] != stored.map { placeMaps[place] = stored.map }
        observedChoices[place] = ViewChoices(options: options, timelineDate: stored.timelineField)
        // A place with no layout kept opens in its own, so one place's table is not carried to the next.
        apply(layout: stored.layout ?? naturalLayout(of: place), in: library)
    }

    // MARK: Resetting

    /// Whether the open place's default view has been changed: something is kept that the place would not show by itself,
    /// or its density or columns are the person's own. A view that asks also watches the three keys (`PlaceDefaults.key`,
    /// `PlaceDensities.key`, `ItemTableColumnLayouts.key`), so it asks again when one changes. The stored data is decoded
    /// only when it differs from what the answer was last worked out from, so a menu that is drawn again decodes nothing.
    var isDefaultViewChanged: Bool {
        guard hasDefaultView else { return false }
        let place = shown
        let inputs = [PlaceDefaults.key, PlaceDensities.key, ItemTableColumnLayouts.key].map { defaults.data(forKey: $0) }
        if let known = changedMemo, known.place == place, known.inputs == inputs { return known.changed }
        let stored = PlaceDefaults.stored(in: defaults).default(for: place)
        let changed = stored?.isChanged(naturalLayout: naturalLayout(of: place)) == true
            || PlaceDensities.stored(in: defaults).density(for: place) != nil
            || ItemTableColumnLayouts.isChanged(for: place, in: inputs[2] ?? Data())
        changedMemo = (place, inputs, changed)
        return changed
    }

    /// Whether Reset View can be offered: the default view is changed, and no new view's panel is open, which shapes a
    /// view that does not exist yet and keeps nothing of the place until it ends.
    var offersResetView: Bool { viewPanel?.isNew != true && isDefaultViewChanged }

    /// Puts the open place back to what it shows by itself: no filters, sort or grouping of the person's, its own
    /// layout, properties, column widths, density and cards. One step of Undo brings the person's choices back.
    func resetView(in library: any ItemLibrary) {
        guard hasDefaultView, viewPanel?.isNew != true else { return }
        let place = shown
        let before = viewSnapshot()
        PlaceDefaults.update(in: defaults) { $0.set(nil, for: place) }
        PlaceDensities.update(in: defaults) { $0.set(nil, for: place) }
        densityRevision += 1
        defaults.set(ItemTableColumnLayouts.removing(place, in: defaults.data(forKey: ItemTableColumnLayouts.key) ?? Data()),
                     forKey: ItemTableColumnLayouts.key)
        tableOptions[place] = nil
        timelineFields[place] = nil
        compactBoards[place] = nil
        placeCards[place] = nil
        placeCalendarScales[place] = nil
        placeHidesEmptyGroups[place] = nil
        placeProperties[place] = nil
        placeQuickActions[place] = nil
        placeOpenings[place] = nil
        placeMaps[place] = nil
        observedChoices[place] = ViewChoices(options: ItemTableOptions(), timelineDate: nil)
        let natural = naturalLayout(of: place)
        if viewMode != natural, availableViewModes(in: library).contains(natural) { set(layout: natural) }
        registerResetUndo(restoring: before)
    }

    private func registerResetUndo(restoring snapshot: ViewPanel.Snapshot) {
        registerUndo(String(localized: "Reset View")) { browser in
            guard browser.shown.isSame(snapshot.place) else { return }
            let current = browser.viewSnapshot()
            browser.restore(snapshot)
            browser.registerResetUndo(restoring: current)
        }
    }

    /// Puts back what a place's default view kept, with what the window holds of it.
    func reinstate(_ stored: PlaceDefault, for place: PlaceView) {
        PlaceDefaults.update(in: defaults) { $0.set(stored, for: place) }
        compactBoards[place] = stored.compactBoard ? true : nil
        placeCalendarScales[place] = stored.calendarScale
        placeHidesEmptyGroups[place] = stored.hidesEmptyGroups ? true : nil
        placeProperties[place] = stored.properties.isChanged ? stored.properties : nil
        placeQuickActions[place] = stored.quickActions
        placeOpenings[place] = stored.opening
        placeMaps[place] = stored.map
    }
}
