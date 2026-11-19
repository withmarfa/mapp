import Foundation

/// The default view of a place that is not a saved view: what a person changes there is kept on this Mac (`PlaceDefaults`,
/// with the columns and density the place already keeps), so the place opens as they left it, in every window and every
/// launch. It cannot be renamed or deleted; Reset View puts it back.
///
/// Two windows on one place both write to the same entry, so the last change wins. A window shows what it holds until it
/// opens the place again, which reads the entry again, and so picks up the other window's change then.
extension Browser {
    /// Whether a place has a default view: every place a person can arrange, which is any but a saved view, whose choices
    /// are its own, and the indexes of collections and sources, whose table is arranged by `IndexPreferences`.
    nonisolated static func hasDefaultView(_ place: SidebarItem) -> Bool {
        switch place {
        case .view, .collections, .sources: false
        default: true
        }
    }

    /// Whether the open place has a default view the window can change.
    var hasDefaultView: Bool { !showsSettings && Self.hasDefaultView(item) }

    /// The layout a place opens in until the person chooses one: Items spans the window, any other place lists.
    nonisolated static func naturalLayout(of place: SidebarItem) -> ItemViewMode {
        place == .allItems ? .gallery : .list
    }

    // MARK: Keeping

    /// Changes what is kept for a place's default view. While a new view's panel is open nothing is kept: the panel
    /// shapes a view that does not exist yet, and the place goes back as it was when the panel ends.
    func updatePlaceDefault(_ place: SidebarItem, _ change: (inout PlaceDefault) -> Void) {
        guard Self.hasDefaultView(place), viewPanel?.isNew != true else { return }
        PlaceDefaults.update(in: defaults) {
            var value = $0.default(for: place) ?? PlaceDefault()
            change(&value)
            $0.set(value, for: place)
        }
    }

    /// Keeps the open place's filters, sort, grouping and timeline date, which the window's funnel (`choicesChanged`) notes.
    func keepPlaceChoices(of place: SidebarItem) {
        let options = tableOptions[place]
        let timeline = timelineFields[place]
        updatePlaceDefault(place) {
            $0.keep(options)
            $0.timelineField = timeline
        }
    }

    /// Changes whether the open place's board draws compact cards, and keeps it.
    func setCompactBoard(_ isCompact: Bool, in place: SidebarItem) {
        compactBoards[place] = isCompact
        updatePlaceDefault(place) { $0.compactBoard = isCompact }
    }

    // MARK: Opening

    /// Opens the place as its default view was left: the choices, the layout and the Mac's settings for each layout. The
    /// choices are not a change of the person's, so no undo step is made of them. A condition on a field that no type of
    /// the place declares any more is dropped and the rest kept; a layout the place no longer offers is not taken. A place
    /// with nothing kept opens as it is, which is how a window that has held another's change forgets it.
    func followPlaceDefault(in library: any ItemLibrary) {
        guard hasDefaultView, library.isLoaded else { return }
        let place = item
        let stored = PlaceDefaults.stored(in: defaults).default(for: place) ?? PlaceDefault()
        let options = stored.options(replacing: tableOptions[place], in: place, catalogue: library.catalogue)
        if options != (tableOptions[place] ?? ItemTableOptions()) { tableOptions[place] = options }
        if timelineFields[place] != stored.timelineField { timelineFields[place] = stored.timelineField }
        let compact: Bool? = stored.compactBoard ? true : nil
        if compactBoards[place] != compact { compactBoards[place] = compact }
        let cards: ViewCards? = stored.cards == ViewCards() ? nil : stored.cards
        if placeCards[place] != cards { placeCards[place] = cards }
        if placeCalendarScales[place] != stored.calendarScale { placeCalendarScales[place] = stored.calendarScale }
        observedChoices[place] = ViewChoices(options: options, timelineDate: stored.timelineField)
        apply(layout: stored.layout, in: library)
    }

    // MARK: Resetting

    /// Whether the open place's default view has been changed: something is kept that the place would not show by itself,
    /// or its density or columns are the person's own. This reads the defaults each time, so a view that asks also
    /// watches their keys (`PlaceDefaults.key`, `PlaceDensities.key`, `ItemTableColumnLayouts.key`).
    var isDefaultViewChanged: Bool {
        guard hasDefaultView else { return false }
        let place = item
        if PlaceDefaults.stored(in: defaults).default(for: place)?.isChanged(naturalLayout: Self.naturalLayout(of: place)) == true {
            return true
        }
        if PlaceDensities.stored(in: defaults).density(for: place) != nil { return true }
        return ItemTableColumnLayouts.isChanged(for: place, in: defaults.data(forKey: ItemTableColumnLayouts.key) ?? Data())
    }

    /// Puts the open place back to what it shows by itself: no filters, sort or grouping of the person's, its own
    /// layout, columns, density and cards. One step of Undo brings the person's choices back.
    func resetView(in library: any ItemLibrary) {
        guard hasDefaultView, viewPanel?.isNew != true else { return }
        let place = item
        let before = viewSnapshot()
        PlaceDefaults.update(in: defaults) { $0.set(nil, for: place) }
        PlaceDensities.update(in: defaults) { $0.set(nil, for: place) }
        densityRevision += 1
        defaults.set(ItemTableColumnLayouts.removing(place, in: defaults.data(forKey: ItemTableColumnLayouts.key) ?? Data()), forKey: ItemTableColumnLayouts.key)
        tableOptions[place] = nil
        timelineFields[place] = nil
        compactBoards[place] = nil
        placeCards[place] = nil
        placeCalendarScales[place] = nil
        observedChoices[place] = ViewChoices(options: ItemTableOptions(), timelineDate: nil)
        let natural = Self.naturalLayout(of: place)
        if viewMode != natural, availableViewModes(in: library).contains(natural) { set(layout: natural) }
        registerResetUndo(restoring: before)
    }

    private func registerResetUndo(restoring snapshot: ViewPanel.Snapshot) {
        registerUndo(String(localized: "Reset View")) { browser in
            guard browser.item == snapshot.place else { return }
            let current = browser.viewSnapshot()
            browser.restore(snapshot)
            browser.registerResetUndo(restoring: current)
        }
    }

    /// Puts back what a place's default view kept, with what the window holds of it.
    func reinstate(_ stored: PlaceDefault, for place: SidebarItem) {
        PlaceDefaults.update(in: defaults) { $0.set(stored, for: place) }
        compactBoards[place] = stored.compactBoard ? true : nil
        placeCalendarScales[place] = stored.calendarScale
    }
}
