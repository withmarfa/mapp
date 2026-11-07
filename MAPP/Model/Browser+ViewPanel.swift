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

    /// Whether the right sidebar holds the panel.
    var showsViewPanel: Bool { viewPanel?.isQuiet == false }

    /// Edit View: a view opens its own panel, and any other place that can show a table opens one with no name.
    func openViewPanel(in library: any ItemLibrary) {
        if let viewPanel {
            viewPanel.isQuiet = false
            return
        }
        if case .view(let id) = item, let view = library.views.first(where: { $0.id == id }) {
            followView(in: library)
            viewPanel = ViewPanel(editing: view, notices: library.notices)
        } else if offersViewOptions {
            viewPanel = ViewPanel()
        }
    }

    /// Edit View on a row of the sidebar's Views, which opens the view first.
    func editView(_ id: ItemID, in library: any ItemLibrary, order: NoteOrder) {
        guard library.views.contains(where: { $0.id == id }), viewPanel?.viewID != id || item != .view(id) else { return }
        closeViewPanel(in: library)
        if item != .view(id) {
            show(.view(id), in: library, order: order)
            followView(in: library)
        }
        openViewPanel(in: library)
    }

    /// New View, from what the window shows: the name starts empty, and the place goes back as it was on Cancel.
    func openNewViewPanel(in library: any ItemLibrary) {
        if let panel = viewPanel {
            // A place's panel turns into the new view's; an edit of a view is put aside by keeping its changes held.
            if panel.purpose == .place { panel.becomeNew(from: viewSnapshot(), library: library) }
            if panel.isNew || panel.purpose == .place { return }
            panel.handOff(because: .left)
            viewPanel = nil
        }
        viewPanel = ViewPanel(newFrom: viewSnapshot(), library: library)
    }

    /// Closes the panel with nothing undone: a view's changes stay held in its place until Revert or Save. A name the
    /// person typed and nothing kept is given back, since the panel is where it lived.
    func closeViewPanel(in library: any ItemLibrary) {
        guard let panel = viewPanel else { return }
        panel.handOff(because: .left)
        if panel.isNew { return dropNewViewPanel(panel) }
        viewPanel = nil
    }

    /// Cancel, the person's own: a view goes back to the view as saved, and a new view's place goes back as it was.
    /// What they typed is theirs to drop. A save under way is not interrupted.
    func cancelViewPanel(in library: any ItemLibrary) {
        guard let panel = viewPanel, !panel.isSaving else { return }
        switch panel.purpose {
        case .edit(let id):
            viewPanel = nil
            viewRefused(id, in: library)
        case .new:
            panel.form?.discard()
            dropNewViewPanel(panel)
        case .place:
            viewPanel = nil
        }
    }

    private func dropNewViewPanel(_ panel: ViewPanel) {
        viewPanel = nil
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
            columns: defaults.data(forKey: ItemTableColumnLayouts.key), working: id.flatMap { viewWorking[$0] },
            cards: id == nil ? placeCards[place] : nil)
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
        if case .view(let id) = snapshot.place { viewWorking[id] = snapshot.working } else { placeCards[snapshot.place] = snapshot.cards }
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
                // No plan means the library does not hold the view, so there is nothing to save to.
                closeGoneViewPanel(panel, in: library)
                return
            }
            if plan.needsConfirmation, !confirmed {
                panel.confirmation = plan.confirmation
                return
            }
            panel.confirmation = nil
            panel.isSaving = true
            let outcome = await save(plan, in: library)
            panel.isSaving = false
            switch outcome {
            case .saved:
                if viewPanel === panel { viewPanel = nil }
            case .gone:
                closeGoneViewPanel(panel, in: library)
            case .changedElsewhere:
                // The name the person typed stays; one they did not type shows the view's new name.
                let typed = panel.typedRename != nil
                if let current = library.views.first(where: { $0.id == plan.view.id })?.title {
                    if !typed { panel.name = current }
                    panel.knownTitle = current
                }
                panel.failure = typed
                    ? String(localized: "This view changed elsewhere, so it now shows the view as it is. Your name is still here; make your other changes again.")
                    : String(localized: "This view changed elsewhere, so it now shows the view as it is. Make your changes again.")
                panel.settleAfterUnsavedEnd()
            case .offline:
                panel.failure = Self.needsServer
                panel.settleAfterUnsavedEnd()
            case .refused(let message):
                panel.failure = message
                panel.settleAfterUnsavedEnd()
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
            let outcome = await form.submit(draft)
            panel.isSaving = false
            guard case .done(let view) = outcome else {
                if viewPanel === panel { panel.failure = String(localized: "The view wasn’t saved. Your name is still here.") }
                return
            }
            // The view exists now, so the Mac keeps its settings whatever became of the panel meanwhile.
            ViewLayouts.update(in: defaults) { $0.set(newView, for: view.id) }
            guard viewPanel === panel else { return }
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
