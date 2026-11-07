import Foundation

/// The panel that edits a view (`ViewPanel`): opening it, what its actions offer, and what Save and Cancel do. Nothing
/// of a view changes until Save, on Marfa or on this Mac; the window shows each change meanwhile.
extension Browser {
    /// What Save keeps of a view: the part Marfa holds, which needs the server, and the part this Mac holds.
    struct ViewSavePlan {
        let view: LibraryView
        let change: LibraryViewChange
        let baseVersion: Int64
        /// What the person is asked about first, when anything is.
        let confirmation: ViewPanel.Confirmation
        /// The Mac's settings to keep, when the person changed any.
        let mac: ViewMacSettings?

        var changesMarfa: Bool { !change.isEmpty }
        var isEmpty: Bool { change.isEmpty && mac == nil }
        var needsConfirmation: Bool { !confirmation.unkept.isEmpty || !confirmation.unchanged.isEmpty }
    }

    /// What the panel's actions offer: Done when nothing changed, Cancel and Save when something did, with Save
    /// dimmed when it cannot be taken.
    enum ViewPanelState: Equatable {
        case unchanged
        case ready
        /// Why Save is dimmed, in words for the panel; nil where the reason is plain, as a name not yet typed.
        case blocked(String?)
    }

    enum ViewSaveOutcome: Equatable {
        case saved
        /// The view changed elsewhere; the window shows it as it is now.
        case changedElsewhere
        /// The server no longer has the view.
        case gone
        case offline
        case refused(String)
    }

    // MARK: Opening and closing

    /// Edit View: a view opens its own panel, and any other place that can show a table opens one with no name.
    func openViewPanel(in library: any ItemLibrary) {
        guard viewPanel == nil else { return }
        if case .view(let id) = item, let view = library.views.first(where: { $0.id == id }) {
            followView(in: library)
            viewPanel = ViewPanel(editing: view)
        } else if offersViewOptions {
            viewPanel = ViewPanel()
        }
    }

    /// Edit View on a row of the sidebar's Views, which opens the view first.
    func editView(_ id: ItemID, in library: any ItemLibrary, order: NoteOrder) {
        guard library.views.contains(where: { $0.id == id }), viewPanel?.viewID != id || item != .view(id) else { return }
        if item != .view(id) {
            closeViewPanel(in: library)
            show(.view(id), in: library, order: order)
            followView(in: library)
        }
        viewPanel = nil
        openViewPanel(in: library)
    }

    /// New View, from what the window shows: the name starts empty, and the place goes back as it was on Cancel.
    func openNewViewPanel(in library: any ItemLibrary) {
        if let panel = viewPanel {
            // A place's panel turns into the new view's; an edit of a view is put aside by keeping its changes held.
            if panel.purpose == .place { panel.becomeNew(from: viewSnapshot(), library: library) }
            if panel.isNew || panel.purpose == .place { return }
            viewPanel = nil
        }
        viewPanel = ViewPanel(newFrom: viewSnapshot(), library: library)
    }

    /// Closes the panel with nothing undone: a view's changes stay held in its place until Revert or Save.
    func closeViewPanel(in library: any ItemLibrary) {
        guard let panel = viewPanel else { return }
        if panel.isNew { return cancelViewPanel(in: library) }
        viewPanel = nil
    }

    /// Cancel: a view goes back to the view as saved, and a new view's place goes back as it was.
    func cancelViewPanel(in library: any ItemLibrary) {
        guard let panel = viewPanel else { return }
        viewPanel = nil
        switch panel.purpose {
        case .edit(let id): viewRefused(id, in: library)
        case .new:
            panel.form?.discard()
            if let snapshot = panel.snapshot { restore(snapshot) }
        case .place: break
        }
    }

    /// The place changed under the panel: a new view is cancelled, and a view's changes stay held where they were made.
    func viewPanelPlaceChanged() {
        guard let panel = viewPanel else { return }
        viewPanel = nil
        if panel.isNew {
            panel.form?.discard()
            if let snapshot = panel.snapshot { restore(snapshot) }
        }
    }

    /// Follows the library: a view deleted elsewhere closes its panel and says so, and one renamed elsewhere shows
    /// its new name unless the person is typing their own.
    func reconcileViewPanel(in library: any ItemLibrary) {
        guard let panel = viewPanel, let id = panel.viewID else { return }
        guard let view = library.views.first(where: { $0.id == id }) else {
            viewPanel = nil
            forgetView(id)
            library.notices.tell(String(localized: "View Deleted"), String(localized: "The view was deleted elsewhere, so its panel closed."))
            return
        }
        if panel.name == panel.knownTitle { panel.name = view.title }
        panel.knownTitle = view.title
    }

    // MARK: Putting a place back

    func viewSnapshot() -> ViewPanel.Snapshot {
        let place = item
        let id: ItemID? = if case .view(let id) = place { id } else { nil }
        return ViewPanel.Snapshot(
            place: place, options: tableOptions[place], timelineDate: timelineFields[place], viewMode: viewMode,
            columns: defaults.data(forKey: ItemTableColumnLayouts.key), working: id.flatMap { viewWorking[$0] })
    }

    /// Puts the place back. A new view that was saved keeps the layout the person chose for it.
    func restore(_ snapshot: ViewPanel.Snapshot, keepingLayout: Bool = false) {
        tableOptions[snapshot.place] = snapshot.options
        timelineFields[snapshot.place] = snapshot.timelineDate
        if !keepingLayout, snapshot.viewMode != viewMode { set(layout: snapshot.viewMode) }
        if let columns = snapshot.columns {
            defaults.set(columns, forKey: ItemTableColumnLayouts.key)
        } else {
            defaults.removeObject(forKey: ItemTableColumnLayouts.key)
        }
        if case .view(let id) = snapshot.place { viewWorking[id] = snapshot.working }
    }

    // MARK: What the actions offer

    /// The change that saves the window's choices and name to the view the panel edits.
    func viewSavePlan(name: String, window: ViewDraft.Window, in library: any ItemLibrary) -> ViewSavePlan? {
        guard case .view(let id) = item, let update = viewUpdate(window, in: library) else { return nil }
        var change = update.change
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != update.view.title { change.title = name }
        let baseline = viewSeeds[id]?.mac
        let mac = viewWorking[id].flatMap { held in baseline.map { held.sameChoices(as: $0) } == true ? nil : held }
        // What a save leaves out matters only when the save writes the query, sort or group.
        let confirmation = update.change.isEmpty
            ? ViewPanel.Confirmation(unkept: [], unchanged: [])
            : ViewPanel.Confirmation(unkept: update.unkept, unchanged: update.change.query == nil ? [] : update.unchanged)
        return ViewSavePlan(view: update.view, change: change, baseVersion: update.baseVersion, confirmation: confirmation, mac: mac)
    }

    func viewPanelState(window: ViewDraft.Window, in library: any ItemLibrary) -> ViewPanelState {
        guard let panel = viewPanel else { return .unchanged }
        switch panel.purpose {
        case .place:
            return .unchanged
        case .new:
            if panel.trimmedName.isEmpty { return .blocked(nil) }
            return library.reachesServer ? .ready : .blocked(Self.needsServer)
        case .edit:
            guard let plan = viewSavePlan(name: panel.shownName, window: window, in: library) else { return .unchanged }
            if panel.trimmedName.isEmpty { return .blocked(nil) }
            if plan.isEmpty { return .unchanged }
            return plan.changesMarfa && !library.reachesServer ? .blocked(Self.needsServer) : .ready
        }
    }

    private static var needsServer: String {
        String(localized: "Saving the name, filters, sort or group of a view needs your Marfa server. Changes to the layout and columns can be saved without it.")
    }

    // MARK: Save

    /// Keeps what the panel's view or new view holds. A save that would leave something out asks first, once.
    func saveViewPanel(
        window: ViewDraft.Window, newView: ViewMacSettings, confirmed: Bool = false, in library: any ItemLibrary, order: NoteOrder
    ) async {
        guard let panel = viewPanel, !panel.isSaving else { return }
        panel.failure = nil
        switch panel.purpose {
        case .place:
            return
        case .edit:
            guard !panel.trimmedName.isEmpty else { return }
            guard let plan = viewSavePlan(name: panel.shownName, window: window, in: library) else {
                // No plan with a name means the view is gone, which the panel reports and closes on.
                reconcileViewPanel(in: library)
                return
            }
            if plan.needsConfirmation, !confirmed {
                panel.confirmation = plan.confirmation
                return
            }
            panel.confirmation = nil
            panel.isSaving = true
            defer { panel.isSaving = false }
            switch await save(plan, in: library) {
            case .saved, .gone:
                if viewPanel === panel { viewPanel = nil }
            case .changedElsewhere:
                panel.name = library.views.first { $0.id == plan.view.id }?.title ?? panel.name
                panel.knownTitle = panel.name
                panel.failure = String(localized: "This view changed elsewhere, so it now shows the view as it is. Make your changes again.")
            case .offline:
                panel.failure = Self.needsServer
            case .refused(let message):
                panel.failure = message
            }
        case .new:
            guard let form = panel.form, form.canSubmit,
                  let draft = ViewDraft.draft(window, catalogue: library.catalogue, views: library.views) else { return }
            let confirmation = ViewPanel.Confirmation(unkept: draft.unkept, unchanged: [])
            if !confirmation.unkept.isEmpty, !confirmed {
                panel.confirmation = confirmation
                return
            }
            panel.confirmation = nil
            panel.isSaving = true
            defer { panel.isSaving = false }
            guard case .done(let view) = await form.submit(draft), viewPanel === panel else {
                if viewPanel === panel { panel.failure = String(localized: "The view wasn’t saved. Your name is still here.") }
                return
            }
            ViewLayouts.update(in: defaults) { $0.set(newView, for: view.id) }
            viewPanel = nil
            if let snapshot = panel.snapshot { restore(snapshot, keepingLayout: true) }
            show(.view(view.id), in: library, order: order)
            followView(in: library)
        }
    }

    /// Writes a view's changes: Marfa's part first, and this Mac's only once Marfa has taken its part, so a refusal
    /// leaves nothing half saved. A change of this Mac's alone needs no server.
    func save(_ plan: ViewSavePlan, in library: any ItemLibrary) async -> ViewSaveOutcome {
        let id = plan.view.id
        var view = plan.view
        if plan.changesMarfa {
            guard library.reachesServer else { return .offline }
            switch await library.changeView(id, plan.change, baseVersion: plan.baseVersion) {
            case .success(let changed):
                view = changed
            case .failure(let failure):
                switch failure.kind {
                case .conflict:
                    viewRefused(id, in: library)
                    return .changedElsewhere
                case .gone:
                    return .gone
                case .offline:
                    return .offline
                case .notPermitted, .refused:
                    return .refused(failure.message)
                }
            }
        }
        if let mac = plan.mac {
            ViewLayouts.update(in: defaults) {
                var kept = mac
                kept.widths = $0.settings(for: id)?.widths
                $0.set(kept, for: id)
            }
        }
        viewUpdated(view, in: library)
        return .saved
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
