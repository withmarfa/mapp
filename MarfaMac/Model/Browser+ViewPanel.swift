import Foundation

/// The View panel (`ViewPanel`): opening it, and what Create View, Escape and a click outside do. Each change shows in
/// the window as it is made and, in a saved view, is written as it is made (`Browser+ViewWrites`), so closing the panel
/// only closes it, except for a new view, which Create View makes.
extension Browser {
    // MARK: Opening and closing

    /// Whether the window shows the panel.
    var showsViewPanel: Bool { viewPanel != nil }

    /// View…: a view opens its own panel, and any other place that can show a table opens one with no name.
    func openViewPanel(in library: any ItemLibrary) {
        if viewPanel != nil { return }
        if let id = shown.savedView, let view = library.views.first(where: { $0.id == id }) {
            followView(in: library)
            viewPanel = ViewPanel(editing: view, notices: library.notices)
        } else if offersViewOptions {
            viewPanel = ViewPanel()
        }
    }

    /// View… on a row of the sidebar's Views, which opens the view first.
    func editView(_ id: ItemID, in library: any ItemLibrary, order: ItemOrder) {
        guard library.views.contains(where: { $0.id == id }) else { return }
        if viewPanel?.viewID == id, shown.isSame(.saved(id)) { return openViewPanel(in: library) }
        closeViewPanel(in: library)
        if !shown.isSame(.saved(id)) {
            show(.saved(id), in: library, order: order)
            followView(in: library)
        }
        openViewPanel(in: library)
    }

    /// New View, from what the window shows: the name starts as the one suggested, and the place goes back as it was on
    /// Escape. While searching, it starts from the search.
    func openNewViewPanel(in library: any ItemLibrary) {
        if let panel = viewPanel {
            if panel.isNew { return }
            // A place's panel turns into the new view's; an edit of a view closes, its changes being written already.
            if panel.purpose == .place {
                panel.becomeNew(from: viewSnapshot(), library: library)
            } else {
                panel.handOff(because: .left)
                viewPanel = nil
            }
        }
        if viewPanel == nil { viewPanel = ViewPanel(newFrom: viewSnapshot(), library: library) }
        viewPanel?.handOffText = { [weak self] in self?.newViewHandOff(in: library) }
        if newViewStarts(in: library).first == .search { chooseStart(.search, in: library) }
        viewPanel?.suggest(suggestedViewName(in: library))
        viewPanel?.startingValues = newViewValues()
    }

    /// Create View on a new view makes it, with the name typed or the default one. On a view or a place it closes the
    /// panel, with a name still being typed written first.
    @discardableResult
    func finishViewPanel(in library: any ItemLibrary, order: ItemOrder) async -> LibraryView? {
        guard let panel = viewPanel else { return nil }
        if panel.isNew { return await makeNewView(from: panel, in: library, order: order) }
        if panel.typedRename != nil {
            panel.leave(because: .left)
            await commitViewName(of: panel, in: library)
        }
        if viewPanel === panel { viewPanel = nil }
        return nil
    }

    /// Closes the panel for a reason that is not the person's own choice: a view's changes were already written, and a
    /// new view is dropped, with the name the person typed given back, since the panel is where it lived.
    func closeViewPanel(in library: any ItemLibrary) {
        guard let panel = viewPanel else { return }
        panel.handOff(because: .left)
        if panel.isNew { return dropNewViewPanel(panel) }
        viewPanel = nil
    }

    /// Escape, the person's own: a view's or a place's panel closes, and a new view makes nothing: the place goes back
    /// as it was, and what they typed is theirs to drop. A view's name still being typed is written, and given back
    /// where it cannot be (`dismissViewPanel`).
    func escapeViewPanel(in library: any ItemLibrary) {
        guard let panel = viewPanel else { return }
        if panel.isNew {
            panel.form?.discard()
            return dropNewViewPanel(panel)
        }
        dismissViewPanel(in: library)
    }

    /// A click outside the panel: a new view is dropped with its name given back, and a view's or a place's panel closes.
    /// A view's name still being typed is written, and given back if the write fails, is refused or finds the view gone,
    /// since nothing else holds it once the panel has closed.
    func dismissViewPanel(in library: any ItemLibrary) {
        guard let panel = viewPanel else { return }
        if panel.isNew { return closeViewPanel(in: library) }
        viewPanel = nil
        guard panel.typedRename != nil else { return }
        panel.leave(because: .left)
        Task { await commitViewName(of: panel, in: library) }
    }

    private func dropNewViewPanel(_ panel: ViewPanel) {
        viewPanel = nil
        dropUndoSteps(of: panel)
        guard let snapshot = panel.snapshot else { return }
        restore(snapshot)
        // A search set aside for a starting point's list comes back, unless the window has moved on.
        if shown.isSame(snapshot.place) { restoreSetAsideSearch(of: panel) }
    }

    /// The place changed under the panel: a new view is cancelled, and a view's changes stay held where they were made.
    /// A name typed is given back, since the change is not the person's Cancel.
    func viewPanelPlaceChanged() {
        guard let panel = viewPanel else { return }
        panel.handOff(because: .left)
        if panel.isNew { dropNewViewPanel(panel) } else { viewPanel = nil }
    }

    /// Follows the library: a view that a list that was read does not hold closes its panel and says so, and one
    /// renamed elsewhere shows its new name unless the person is typing their own. An empty list proves nothing,
    /// since a read that failed publishes one, and Mac settings are never forgotten for an absence.
    func reconcileViewPanel(in library: any ItemLibrary) {
        guard let panel = viewPanel, let id = panel.viewID, !viewsBeingDeleted.contains(id) else { return }
        guard let view = library.views.first(where: { $0.id == id }) else {
            if !library.views.isEmpty { closeGoneViewPanel(panel, in: library) }
            return
        }
        panel.follow(view)
    }

    /// The view the panel edits is gone: the panel closes, and the person is told, or is given back the name they typed.
    private func closeGoneViewPanel(_ panel: ViewPanel, in library: any ItemLibrary) {
        if viewPanel === panel { viewPanel = nil }
        if !panel.handOffBecauseGone() {
            library.notices.tell(String(localized: "View Deleted"), String(localized: "The view was deleted elsewhere, so its panel closed."))
        }
    }

    // MARK: Putting a place back

    func viewSnapshot() -> ViewPanel.Snapshot {
        let place = shown
        let id: ItemID? = if let id = place.savedView { id } else { nil }
        return ViewPanel.Snapshot(
            place: place, options: tableOptions[place], timelineDate: timelineFields[place], viewMode: viewMode,
            columns: defaults.data(forKey: ItemTableColumnLayouts.key), mac: id.map { macSettings(for: $0) },
            cards: id == nil ? placeCards[place] : nil, density: id == nil ? density : nil,
            placeDefault: id == nil && Self.hasDefaultView(place) ? PlaceDefaults.stored(in: defaults).default(for: place) ?? PlaceDefault() : nil)
    }

    /// Puts the place back. A new view that was made keeps the layout the person chose for it.
    func restore(_ snapshot: ViewPanel.Snapshot, keepingLayout: Bool = false) {
        tableOptions[snapshot.place] = snapshot.options
        timelineFields[snapshot.place] = snapshot.timelineDate
        observedChoices[snapshot.place] = ViewChoices(options: snapshot.options ?? ItemTableOptions(), timelineDate: snapshot.timelineDate)
        if !keepingLayout, snapshot.viewMode != viewMode { set(layout: snapshot.viewMode) }
        if let columns = snapshot.columns {
            defaults.set(columns, forKey: ItemTableColumnLayouts.key)
        } else {
            defaults.removeObject(forKey: ItemTableColumnLayouts.key)
        }
        if let id = snapshot.place.savedView {
            if let mac = snapshot.mac { keep(mac, for: id) }
        } else {
            placeCards[snapshot.place] = snapshot.cards
            store(snapshot.density, for: snapshot.place)
            if let stored = snapshot.placeDefault { reinstate(stored, for: snapshot.place) }
        }
    }

    // MARK: Making a new view

    /// Makes the view of what the window shows, under the name typed or the one suggested, and shows it. What the view
    /// cannot keep of the window is said once it exists. A name another view has, a server that can't be reached and a
    /// refusal each leave the panel, the name and the window as they are, with the reason in the panel.
    @discardableResult
    func makeNewView(from panel: ViewPanel, in library: any ItemLibrary, order: ItemOrder) async -> LibraryView? {
        guard let form = panel.form, !form.isBusy, !panel.choosesNoSource else { return nil }
        if form.trimmedTitle.isEmpty { form.title = suggestedViewName(in: library) }
        if viewNamed(form.trimmedTitle, in: library) != nil {
            panel.problem = .clash(form.trimmedTitle)
            return nil
        }
        // A view is never queued: offline, it waits in the panel for Create View once the server is back.
        guard library.reachesServer else {
            panel.problem = .offline
            return nil
        }
        let window = SavedViews.window(self, in: library, order: order)
        var settings = SavedViews.newViewSettings(self, in: library)
        let held: Bool? = if let id = shown.savedView { macSettings(for: id).quickActions } else { placeQuickActions[shown] }
        settings.quickActions = panel.quickActions ?? held
        guard form.canSubmit else { return nil }
        guard var draft = ViewDraft.draft(window, catalogue: library.catalogue, views: library.views) else { return nil }
        // A starting point's own order is written as it is, never left to the order a layout or a search gives.
        if let start = panel.start, let own = start.sort, tableOptions[shown]?.sort == own.window { draft.sort = own.saved }
        panel.problem = nil
        guard case .done(let view) = await form.submit(draft) else {
            panel.problem = .refused
            return nil
        }
        // The view exists now, so the Mac keeps its settings whatever became of the panel meanwhile.
        ViewLayouts.update(in: defaults) { $0.set(settings, for: view.id) }
        // New View's panel named what the view would not keep (`ViewPanelUnkept`), so it is not told again.
        toldUnkept[view.id] = Set(draft.unkept.filter { !$0.isSaidWhereMade })
        guard viewPanel === panel else { return view }
        viewPanel = nil
        dropUndoSteps(of: panel)
        if let snapshot = panel.snapshot { restore(snapshot, keepingLayout: true) }
        show(.saved(view.id), in: library, order: order)
        followView(in: library)
        return view
    }

    /// A starting point's tile: one the person already has opens theirs, at once while the new view holds nothing of
    /// theirs. Otherwise the view it would open is returned, for the person to confirm discarding the new view first.
    func pickStart(_ start: NewViewStart, in library: any ItemLibrary, order: ItemOrder) -> PlaceView? {
        guard let theirs = existingView(for: start, in: library) else {
            chooseStart(start, in: library)
            return nil
        }
        if let panel = viewPanel, isNewViewTouched(panel) { return theirs }
        openExistingView(theirs, in: library, order: order)
        return nil
    }

    /// A starting point the person already has opens theirs, and the new view is dropped as Cancel drops it.
    func openExistingView(_ place: PlaceView, in library: any ItemLibrary, order: ItemOrder) {
        escapeViewPanel(in: library)
        show(place, in: library, order: order)
        followView(in: library)
    }

    // MARK: Duplicate

    /// A view of the same query, sort and group named for the copy, with the Mac settings the original keeps. It
    /// shows the copy.
    @discardableResult
    func duplicateView(_ id: ItemID, in library: any ItemLibrary, order: ItemOrder) async -> LibraryView? {
        guard let view = library.views.first(where: { $0.id == id }) else {
            library.notices.tell(String(localized: "Can’t Duplicate View"), Self.deletedElsewhere)
            return nil
        }
        guard library.reachesServer else { return nil }
        let settings = LibraryViewSettings(title: String(localized: "\(view.title) Copy"), query: view.query, sort: view.sort, group: view.group)
        guard let copy = await library.createView(settings) else { return nil }
        if let kept = ViewLayouts.stored(in: defaults).settings(for: id) {
            ViewLayouts.update(in: defaults) { $0.set(kept, for: copy.id) }
        }
        show(.saved(copy.id), in: library, order: order)
        followView(in: library)
        return copy
    }
}

// MARK: Quick Actions and Open Items

extension Browser {
    /// Whether the open place's rows offer their quick actions: a saved view's choice on this Mac, else the place's
    /// default view's, else the place's own (`ViewMacSettings.showsQuickActions`).
    var showsQuickActions: Bool {
        let chosen: Bool? = if let panel = viewPanel, panel.isNew, let new = panel.quickActions { new }
            else if let id = shown.savedView { macSettings(for: id).quickActions } else { placeQuickActions[shown] }
        return ViewMacSettings.showsQuickActions(chosen, in: shown, scope: listing.scope)
    }

    /// Turns the open place's quick actions on or off. A saved view's choice is kept in the app's settings, and a place's
    /// in its default view. Undo takes either back.
    func setShowsQuickActions(_ shows: Bool) {
        // A new view's choice is the panel's until the view exists.
        if let panel = viewPanel, panel.isNew {
            panel.quickActions = shows
        } else if let id = shown.savedView {
            changeViewSettings(id) { $0.quickActions = shows }
        } else if shows != showsQuickActions {
            setPlaceQuickActions(shows, in: shown)
        }
    }

    private func setPlaceQuickActions(_ shows: Bool?, in place: PlaceView) {
        let before = placeQuickActions[place]
        placeQuickActions[place] = shows
        updatePlaceDefault(place) { $0.quickActions = shows }
        registerUndo(String(localized: "Change View")) { browser in
            guard browser.shown.isSame(place) else { return }
            browser.setPlaceQuickActions(before, in: place)
        }
    }

    /// Where the open place opens its items, where the person chose: a saved view's choice on this Mac, else the
    /// place's default view's. Nil follows Settings.
    var chosenOpening: ItemOpening? {
        if let id = shown.savedView { macSettings(for: id).opening } else { placeOpenings[shown] }
    }

    /// Where Open, Return and a double-click open an item in the open place.
    func itemOpening(defaults: UserDefaults = .standard) -> ItemOpening {
        chosenOpening ?? ItemOpening.stored(in: defaults)
    }

    /// Changes where the open place opens its items; nil follows Settings. Undo takes it back.
    func setOpening(_ opening: ItemOpening?) {
        if let id = shown.savedView {
            changeViewSettings(id) { $0.opening = opening }
        } else if opening != chosenOpening {
            setPlaceOpening(opening, in: shown)
        }
    }

    private func setPlaceOpening(_ opening: ItemOpening?, in place: PlaceView) {
        let before = placeOpenings[place]
        placeOpenings[place] = opening
        updatePlaceDefault(place) { $0.opening = opening }
        registerUndo(String(localized: "Change View")) { browser in
            guard browser.shown.isSame(place) else { return }
            browser.setPlaceOpening(before, in: place)
        }
    }
}
