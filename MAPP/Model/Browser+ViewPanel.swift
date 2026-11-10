import Foundation

/// The panel that edits a view (`ViewPanel`): opening it, and what Done and Escape do. Each change shows in the window
/// as it is made and, in a saved view, is written as it is made (`Browser+ViewWrites`); Done only closes the panel,
/// except for a new view, which it makes.
extension Browser {
    // MARK: Opening and closing

    /// Whether the right sidebar holds the panel.
    var showsViewPanel: Bool { viewPanel != nil }

    /// Edit View: a view opens its own panel, and any other place that can show a table opens one with no name.
    func openViewPanel(in library: any ItemLibrary) {
        if viewPanel != nil { return }
        if case .view(let id) = item, let view = library.views.first(where: { $0.id == id }) {
            followView(in: library)
            viewPanel = ViewPanel(editing: view, notices: library.notices)
        } else if offersViewOptions {
            viewPanel = ViewPanel()
        }
    }

    /// Edit View on a row of the sidebar's Views, which opens the view first.
    func editView(_ id: ItemID, in library: any ItemLibrary, order: NoteOrder) {
        guard library.views.contains(where: { $0.id == id }) else { return }
        if viewPanel?.viewID == id, item == .view(id) { return openViewPanel(in: library) }
        closeViewPanel(in: library)
        if item != .view(id) {
            show(.view(id), in: library, order: order)
            followView(in: library)
        }
        openViewPanel(in: library)
    }

    /// New View, from what the window shows: the name starts empty, and the place goes back as it was on Escape.
    func openNewViewPanel(in library: any ItemLibrary) {
        if let panel = viewPanel {
            // A place's panel turns into the new view's; an edit of a view closes, its changes being written already.
            if panel.purpose == .place { panel.becomeNew(from: viewSnapshot(), library: library) }
            if panel.isNew || panel.purpose == .place { return }
            panel.handOff(because: .left)
            viewPanel = nil
        }
        viewPanel = ViewPanel(newFrom: viewSnapshot(), library: library)
    }

    /// Done on a view or a place closes the panel, with a name still being typed written first. On a new view it makes
    /// the view, with the name typed or the default one.
    func finishViewPanel(in library: any ItemLibrary, order: NoteOrder) async {
        guard let panel = viewPanel else { return }
        if panel.isNew { return await makeNewView(from: panel, in: library, order: order) }
        if panel.typedRename != nil { await commitViewName(of: panel, in: library) }
        if viewPanel === panel { viewPanel = nil }
    }

    /// Closes the panel for a reason that is not the person's Done: a view's changes were already written, and a new
    /// view is dropped, with the name the person typed given back, since the panel is where it lived.
    func closeViewPanel(in library: any ItemLibrary) {
        guard let panel = viewPanel else { return }
        panel.handOff(because: .left)
        if panel.isNew { return dropNewViewPanel(panel) }
        viewPanel = nil
    }

    /// Escape, the person's own: a view's or a place's panel closes, and a new view makes nothing: the place goes back
    /// as it was, and what they typed is theirs to drop.
    func escapeViewPanel(in library: any ItemLibrary) {
        guard let panel = viewPanel else { return }
        if panel.isNew {
            panel.form?.discard()
            return dropNewViewPanel(panel)
        }
        if panel.typedRename != nil { Task { await commitViewName(of: panel, in: library) } }
        viewPanel = nil
    }

    private func dropNewViewPanel(_ panel: ViewPanel) {
        viewPanel = nil
        dropUndoSteps(of: panel)
        if let snapshot = panel.snapshot { restore(snapshot) }
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
        if panel.name == panel.knownTitle { panel.name = view.title }
        panel.knownTitle = view.title
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
        let place = item
        let id: ItemID? = if case .view(let id) = place { id } else { nil }
        return ViewPanel.Snapshot(
            place: place, options: tableOptions[place], timelineDate: timelineFields[place], viewMode: viewMode,
            columns: defaults.data(forKey: ItemTableColumnLayouts.key), mac: id.map { macSettings(for: $0) },
            cards: id == nil ? placeCards[place] : nil, rows: id == nil ? placeRows[place] : nil)
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
        if case .view(let id) = snapshot.place {
            if let mac = snapshot.mac { keep(mac, for: id) }
        } else {
            placeCards[snapshot.place] = snapshot.cards
            placeRows[snapshot.place] = snapshot.rows
        }
    }

    // MARK: Making a new view

    /// Makes the view of what the window shows, under the name typed or the default one, and shows it. What the view
    /// cannot keep of the window is said once it exists. A refusal leaves the panel and the name as they are.
    func makeNewView(from panel: ViewPanel, in library: any ItemLibrary, order: NoteOrder) async {
        guard let form = panel.form, !form.isBusy else { return }
        if form.trimmedTitle.isEmpty { form.title = String(localized: "New View") }
        let window = SavedViews.window(self, in: library, order: order)
        let settings = SavedViews.newViewSettings(self, in: library)
        guard library.reachesServer else {
            library.notices.tell(String(localized: "View Not Made"), String(localized: "Making a view needs your Marfa server, which can’t be reached now. Your changes are still in the window."))
            return
        }
        guard form.canSubmit else { return }
        guard let draft = ViewDraft.draft(window, catalogue: library.catalogue, views: library.views) else { return }
        guard case .done(let view) = await form.submit(draft) else { return }
        // The view exists now, so the Mac keeps its settings whatever became of the panel meanwhile.
        ViewLayouts.update(in: defaults) { $0.set(settings, for: view.id) }
        tellUnkept(draft.unkept, of: view.id, in: library)
        guard viewPanel === panel else { return }
        viewPanel = nil
        dropUndoSteps(of: panel)
        if let snapshot = panel.snapshot { restore(snapshot, keepingLayout: true) }
        show(.view(view.id), in: library, order: order)
        followView(in: library)
    }

    // MARK: Duplicate

    /// A view of the same query, sort and group named for the copy, with the Mac settings the original keeps. It
    /// shows the copy.
    @discardableResult
    func duplicateView(_ id: ItemID, in library: any ItemLibrary, order: NoteOrder) async -> LibraryView? {
        guard library.reachesServer, let view = library.views.first(where: { $0.id == id }) else { return nil }
        let settings = LibraryViewSettings(title: String(localized: "\(view.title) Copy"), query: view.query, sort: view.sort, group: view.group)
        guard let copy = await library.createView(settings) else { return nil }
        if let kept = ViewLayouts.stored(in: defaults).settings(for: id) {
            ViewLayouts.update(in: defaults) { $0.set(kept, for: copy.id) }
        }
        show(.view(copy.id), in: library, order: order)
        followView(in: library)
        return copy
    }
}
