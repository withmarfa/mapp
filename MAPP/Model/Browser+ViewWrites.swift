import Foundation

/// What Marfa holds of a place's choices: its filters, order, grouping and the date its timeline shows. Two are equal
/// where a view would be written the same, so a folded group or a page size is not a choice.
struct ViewChoices: Equatable {
    var options: ItemTableOptions
    var timelineDate: String?

    static func == (lhs: ViewChoices, rhs: ViewChoices) -> Bool {
        !ViewDraft.differs(lhs.options, timelineDate: lhs.timelineDate, from: rhs.options, seedTimelineDate: rhs.timelineDate)
    }
}

/// How a change the person makes to a place becomes one step of the window's Undo, and, in a saved view, a write to
/// Marfa as it is made.
///
/// The funnel is `choicesChanged()`: the window calls it whenever the place's choices may have changed, whoever changed
/// them. It compares them with the last it saw, registers an undo step for the difference and, in a saved view, writes
/// the difference to Marfa (`writeChoices`). Undo puts the earlier choices back through the same funnel, so the earlier
/// value is written back and Redo comes for free.
///
/// - A write Marfa refuses, or that cannot reach it, leaves the window as the person chose and the view as it was: the
///   next write carries the difference, since every write is the window's choices against the version last read.
/// - Undo puts a step back only where the window still shows what the step made, so a view that changed elsewhere in
///   the meantime is never overwritten without the person being told.
extension Browser {
    /// What the open place's choices are now.
    var liveChoices: ViewChoices {
        ViewChoices(options: tableOptions[item] ?? ItemTableOptions(), timelineDate: timelineFields[item])
    }

    /// Registers a step of the window's Undo.
    func registerUndo(_ name: String, _ undo: @escaping @MainActor (Browser) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { browser in MainActor.assumeIsolated { undo(browser) } }
        undoManager.setActionName(name)
    }

    /// The window moved to another place, whose choices an Undo must not touch.
    func placeChanged() {
        undoManager?.removeAllActions(withTarget: self)
    }

    /// Notes a change of the open place's choices: one undo step, and in a saved view a write. The task that writes,
    /// where there is one.
    @discardableResult
    func choicesChanged() -> Task<Void, Never>? {
        let place = item
        let current = liveChoices
        guard let before = observedChoices[place] else {
            observedChoices[place] = current
            return nil
        }
        guard current != before else { return nil }
        observedChoices[place] = current
        registerChoiceUndo(in: place, from: before, to: current)
        guard case .view(let id) = place, viewPanel?.isNew != true else { return nil }
        return scheduleWrite(of: id)
    }

    private func registerChoiceUndo(in place: SidebarItem, from before: ViewChoices, to after: ViewChoices) {
        registerUndo(String(localized: "Change View")) { browser in
            guard browser.item == place, browser.liveChoices == after else {
                browser.library?.notices.tell(
                    String(localized: "Can’t Undo"),
                    String(localized: "This view has changed since, so that change was left as it is."))
                return
            }
            browser.put(before, in: place)
            browser.choicesChanged()
        }
    }

    /// Puts the order, grouping, filters and timeline date back, and leaves the rest of the place's options.
    func put(_ choices: ViewChoices, in place: SidebarItem) {
        var options = tableOptions[place] ?? ItemTableOptions()
        if options.grouping != choices.options.grouping { options.collapsed = nil }
        options.grouping = choices.options.grouping
        options.sort = choices.options.sort
        options.filters = choices.options.filters
        options.negated = choices.options.negated
        tableOptions[place] = options
        timelineFields[place] = choices.timelineDate
    }

    // MARK: Writing a view

    /// Writes the window's choices to the view, one write at a time, and again if they changed while one was under way.
    @discardableResult
    func scheduleWrite(of id: ItemID) -> Task<Void, Never>? {
        guard !writingViews.contains(id) else {
            rewritingViews.insert(id)
            return nil
        }
        return Task { await writeChoices(of: id) }
    }

    /// Writes the window's choices against the version of the view last read.
    func writeChoices(of id: ItemID) async {
        guard let library, !writingViews.contains(id) else { return }
        writingViews.insert(id)
        defer { writingViews.remove(id) }
        repeat {
            rewritingViews.remove(id)
            await writeOnce(id, in: library)
        } while rewritingViews.contains(id)
    }

    /// Writes again what the window holds and Marfa has not taken, as Save View asks.
    func writeViewAgain() {
        guard case .view(let id) = item else { return }
        scheduleWrite(of: id)
    }

    private func writeOnce(_ id: ItemID, in library: any ItemLibrary) async {
        guard item == .view(id), viewPanel?.isNew != true else { return }
        guard let update = viewUpdate(SavedViews.window(self, in: library), in: library), !update.change.isEmpty else { return }
        guard library.reachesServer else {
            if toldOffline.insert(id).inserted {
                library.notices.tell(
                    String(localized: "View Not Saved"),
                    String(localized: "Your Marfa server can’t be reached, so the view is as it was. The window keeps your change, and the next change saves it once the server is back."))
            }
            return
        }
        let sent = liveChoices
        switch await library.changeView(id, update.change, baseVersion: update.baseVersion) {
        case .success(let view):
            toldOffline.remove(id)
            // The window keeps what it shows: the view is the window's only where the view can hold it all.
            seed(view, catalogue: library.catalogue, keepingWindow: true)
            if liveChoices != sent { rewritingViews.insert(id) }
            tellUnkept(update.unkept, of: id, in: library)
        case .failure(let failure):
            // The library has told the person why. A view changed elsewhere shows as it is now; any other refusal
            // leaves the window as the person chose.
            switch failure.kind {
            case .conflict:
                undoManager?.removeAllActions(withTarget: self)
                viewRefused(id, in: library)
            case .offline, .gone, .notPermitted, .refused:
                break
            }
        }
    }

    /// Says once what a write left out of the view, as it did in the dialog before a Save.
    func tellUnkept(_ unkept: [ViewDraft.Unkept], of id: ItemID, in library: any ItemLibrary) {
        let left = unkept.filter { if case .search = $0 { false } else { true } }
        let told = toldUnkept[id] ?? []
        let fresh = left.filter { !told.contains($0) }
        toldUnkept[id] = Set(left)
        guard !fresh.isEmpty else { return }
        library.notices.tell(
            String(localized: "View Not Fully Saved"),
            String(localized: "The view can’t keep:\n") + fresh.map { "• " + SavedViews.describe($0) }.joined(separator: "\n"))
    }

    // MARK: Naming a view

    /// Writes the name the person typed, once they commit it with Return or leave the field. An empty name goes back to the view's.
    func commitViewName(of panel: ViewPanel? = nil, in library: any ItemLibrary) async {
        guard let panel = panel ?? viewPanel, let id = panel.viewID, let view = library.views.first(where: { $0.id == id }) else { return }
        let name = panel.trimmedName
        guard !name.isEmpty else {
            panel.name = view.title
            return
        }
        guard name != view.title else { return }
        if await writeName(name, of: id, expecting: view.title, in: library) {
            registerNameUndo(of: id, restoring: view.title, from: name)
        }
    }

    private func registerNameUndo(of id: ItemID, restoring old: String, from new: String) {
        registerUndo(String(localized: "Rename View")) { browser in
            browser.viewPanel?.name = old
            browser.registerNameUndo(of: id, restoring: new, from: old)
            guard let library = browser.library else { return }
            Task { await browser.writeName(old, of: id, expecting: new, in: library) }
        }
    }

    /// Writes a title, where the view still has the one this change was made from.
    @discardableResult
    private func writeName(_ name: String, of id: ItemID, expecting title: String, in library: any ItemLibrary) async -> Bool {
        while writingViews.contains(id) { try? await Task.sleep(for: .milliseconds(20)) }
        writingViews.insert(id)
        defer { writingViews.remove(id) }
        guard let view = library.views.first(where: { $0.id == id }), let seed = viewSeeds[id] else { return false }
        guard view.title == title else {
            library.notices.tell(String(localized: "Can’t Rename"), String(localized: "This view was renamed elsewhere, so its name was left as it is."))
            return false
        }
        guard library.reachesServer else {
            library.notices.tell(String(localized: "View Not Renamed"), String(localized: "Your Marfa server can’t be reached, so the view keeps its name. Rename it again once it is back."))
            return false
        }
        var change = LibraryViewChange()
        change.title = name
        switch await library.changeView(id, change, baseVersion: seed.version) {
        case .success(let changed):
            self.seed(changed, catalogue: library.catalogue, keepingWindow: true)
            viewPanel?.knownTitle = changed.title
            return true
        case .failure(let failure):
            if failure.kind == .conflict { viewRefused(id, in: library) }
            return false
        }
    }
}
