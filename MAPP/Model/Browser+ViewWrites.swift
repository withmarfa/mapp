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
    var liveChoices: ViewChoices { choices(in: item) }

    /// What a place's choices are now, whether or not the window shows it.
    func choices(in place: SidebarItem) -> ViewChoices {
        ViewChoices(options: tableOptions[place] ?? ItemTableOptions(), timelineDate: timelineFields[place])
    }

    /// Registers a step of the window's Undo. While a new view's panel is open the step belongs to the panel, so that
    /// dropping the panel removes these steps and no earlier one (`dropUndoSteps`).
    func registerUndo(_ name: String, _ undo: @escaping @MainActor (Browser) -> Void) {
        guard let undoManager else { return }
        let target: AnyObject = viewPanel.flatMap { $0.isNew ? $0 : nil } ?? self
        undoManager.registerUndo(withTarget: target) { [weak self] _ in
            MainActor.assumeIsolated { if let self { undo(self) } }
        }
        undoManager.setActionName(name)
    }

    /// Removes the steps made while a new view's panel was open, which describe choices the place no longer has.
    func dropUndoSteps(of panel: ViewPanel) {
        undoManager?.removeAllActions(withTarget: panel)
    }

    /// The server can be reached again, so a later stretch without it is told again.
    func reachabilityChanged(in library: any ItemLibrary) {
        if library.reachesServer { toldOffline.removeAll() }
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
        guard let library else { return }
        guard !writingViews.contains(id) else {
            rewritingViews.insert(id)
            return
        }
        writingViews.insert(id)
        rewritingViews.insert(id)
        await writeUntilSettled(id, in: library)
        unlockView(id)
    }

    /// Writes again for as long as the window's choices changed during a write.
    private func writeUntilSettled(_ id: ItemID, in library: any ItemLibrary) async {
        while rewritingViews.remove(id) != nil {
            await writeOnce(id, in: library)
        }
    }

    /// Waits for the write under way on a view to end, then holds the view: one write at a time, in the order asked.
    /// The holder ends with `unlockView`.
    private func lockView(_ id: ItemID) async {
        guard writingViews.contains(id) else {
            writingViews.insert(id)
            return
        }
        await withCheckedContinuation { viewWaiters[id, default: []].append($0) }
    }

    /// Hands the view to the next that waits, or frees it.
    private func unlockView(_ id: ItemID) {
        guard var waiting = viewWaiters[id], !waiting.isEmpty else {
            writingViews.remove(id)
            return
        }
        let next = waiting.removeFirst()
        viewWaiters[id] = waiting.isEmpty ? nil : waiting
        next.resume()
    }

    /// Writes again what the window holds and Marfa has not taken, as Save View asks.
    func writeViewAgain() {
        guard case .view(let id) = item else { return }
        scheduleWrite(of: id)
    }

    private func writeOnce(_ id: ItemID, in library: any ItemLibrary) async {
        guard viewPanel?.isNew != true else { return }
        // The window's choices are the open place's: a view that is not open writes them when it is shown again.
        guard item == .view(id) else {
            pendingViewWrites.insert(id)
            return
        }
        guard let update = viewUpdate(SavedViews.window(self, in: library), in: library) else { return }
        if update.change.isEmpty {
            // A change the view cannot hold is the person's to hear of, though there is nothing to write.
            tellUnkept(update.unkept, of: id, in: library)
            return
        }
        guard library.reachesServer else {
            if toldOffline.insert(id).inserted {
                library.notices.tell(
                    String(localized: "View Not Saved"),
                    String(localized: "Your Marfa server can’t be reached, so the view is as it was. The window keeps your change, and the next change saves it once the server is back."))
            }
            return
        }
        let place = SidebarItem.view(id)
        let sent = choices(in: place)
        switch await library.changeView(id, update.change, baseVersion: update.baseVersion) {
        case .success(let view):
            // The window keeps what it shows: the view is the window's only where the view can hold it all.
            seed(view, catalogue: library.catalogue, keepingWindow: true)
            if choices(in: place) != sent { rewritingViews.insert(id) }
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
        guard name != view.title, panel.renaming != name else { return }
        // A rename queued ahead of this one either lands first or fails, so the view then has either title.
        let expected = Set([view.title] + [panel.renaming].compactMap { $0 })
        panel.renaming = name
        let kept = await writeName(name, of: id, expecting: expected, in: library)
        panel.finishRename(name: name, kept: kept)
        if kept { registerNameUndo(of: id, restoring: view.title, from: name) }
    }

    private func registerNameUndo(of id: ItemID, restoring old: String, from new: String) {
        registerUndo(String(localized: "Rename View")) { browser in
            browser.viewPanel?.name = old
            browser.registerNameUndo(of: id, restoring: new, from: old)
            guard let library = browser.library else { return }
            Task { await browser.writeName(old, of: id, expecting: [new], in: library) }
        }
    }

    /// Writes a title, where the view still has the one this change was made from.
    @discardableResult
    private func writeName(_ name: String, of id: ItemID, expecting titles: Set<String>, in library: any ItemLibrary) async -> Bool {
        await lockView(id)
        let kept = await writeNameLocked(name, of: id, expecting: titles, in: library)
        // A choice changed while the name was written is written now, so it is never left behind.
        await writeUntilSettled(id, in: library)
        unlockView(id)
        return kept
    }

    private func writeNameLocked(_ name: String, of id: ItemID, expecting titles: Set<String>, in library: any ItemLibrary) async -> Bool {
        guard let view = library.views.first(where: { $0.id == id }), let seed = viewSeeds[id] else { return false }
        guard titles.contains(view.title) else {
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
