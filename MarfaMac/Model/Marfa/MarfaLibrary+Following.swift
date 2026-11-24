import Foundation

/// Following the source: what the library does with each step the source says, from a loaded snapshot to a write's
/// answer. Each step is taken in at once, so each revision moves at most once for it.
extension MarfaLibrary {
    func take(_ change: SourceChange) async {
        let interval = Telemetry.begin(.library, change.kind, ("items", change.itemCount))
        defer { interval.end() }
        switch change {
        case .loaded(let snapshot):
            forgetAnsweredEdits(of: Set(newestEdits.keys))
            load(snapshot)
        case .changed(let changes):
            forgetAnsweredEdits(of: Set(changes.upserted.map(\.id)).union(changes.removed))
            take(changes)
        case .answered(let id, let outcome, let holding):
            textSaves.removeValue(forKey: id)?.end()
            propertyWrites[id] = nil
            propertyMarks[id] = nil
            read(id)
            answered(id, outcome)
            stateWriteAnswered(id, outcome)
            settle(id)
            propertyAnswered(id, outcome, holding: holding)
        case .taken(let id):
            textSaves.removeValue(forKey: id)?.end()
            propertyWrites[id] = nil
            if let mark = propertyMarks.removeValue(forKey: id) { remember(taken: mark) }
            if let edit = propertyEdits[id] { edit.take(holding: { item(edit.item)?.value(of: $0) }) }
            took(id)
            stateWriteTaken(id)
            read(id)
            settle(id)
        case .catalogue(let catalogue):
            self.catalogue = holdingChosenIcons(catalogue)
            reindex()
        case .views(let views):
            take(views)
        case .counts(let rowsOnly):
            counts.refresh(rowsOnly: rowsOnly)
        case .unavailable(let failure):
            // The window keeps showing the library while its copy is open, so an ended sign-in is told with the way
            // to Settings, where the person signs in again or disconnects the library.
            if failure.kind == .denied {
                notices.tell(String(localized: "Signed Out of Your Marfa Server"), failure.message, action: .openSettings(.connection))
            } else {
                notices.tell(failure.title ?? String(localized: "Can’t Read This Library"), failure.message)
            }
        }
    }

    /// Keeps the records the views already observe, so a second load tells each of them what changed.
    private func load(_ snapshot: SourceSnapshot) {
        catalogue = holdingChosenIcons(snapshot.catalogue)
        take(snapshot.views)
        let present = Set(snapshot.items.map(\.id))
        var renamed = false
        for (id, record) in records where !present.contains(id) {
            // The index is rebuilt below. The other ends are told now, so a link this item held is read again.
            noteLinks(touching: record.item)
            record.isHeld = false
            records[id] = nil
        }
        for item in snapshot.items {
            if let record = records[item.id] {
                let old = record.item
                guard old != item else { continue }
                if old.title != item.title || old.name != item.name { renamed = true }
                record.item = item
                if old.edgesOut != item.edgesOut {
                    noteLinks(touching: old)
                    noteLinks(touching: item)
                }
            } else {
                records[item.id] = ItemRecord(item)
                if !item.edgesOut.isEmpty { noteLinks(touching: item) }
            }
        }
        hold(Array(snapshot.bodies.values))
        if renamed { namesRevision += 1 }
        reindex()
        isLoaded = true
        LaunchTrace.shared.mark(.firstLoaded)
    }

    /// One step of the source, taken in at once, so each revision moves at most once for it.
    private func take(_ changes: ItemChanges) {
        var changed = false
        var moved = false
        var renamed = false
        for id in changes.removed {
            guard let record = records.removeValue(forKey: id) else { continue }
            index.remove(record.item)
            record.isHeld = false
            noteLinks(touching: record.item)
            changed = true
            moved = true
        }
        for item in changes.upserted {
            if let record = records[item.id] {
                let old = record.item
                guard old != item else { continue }
                if old.title != item.title || old.name != item.name { renamed = true }
                // The index is current before the stamps move, so a reader told by a stamp sees the new edges.
                index.remove(old)
                index.insert(item, catalogue: catalogue)
                record.item = item
                if old.edgesOut != item.edgesOut {
                    noteLinks(touching: old)
                    noteLinks(touching: item)
                }
                if Self.placesDiffer(old, item) { moved = true }
            } else {
                records[item.id] = ItemRecord(item)
                index.insert(item, catalogue: catalogue)
                if !item.edgesOut.isEmpty { noteLinks(touching: item) }
                moved = true
            }
            changed = true
        }
        hold(changes.bodies)
        if changed { contentRevision += 1 }
        if moved { membershipRevision += 1 }
        if renamed { namesRevision += 1 }
    }

    /// Tells every item an edge of `item` touches, this item included, that the edge came, went or changed.
    /// The item's own record moves its stamp when its `edgesOut` changes; this also reaches the other ends, whose
    /// own items did not.
    private func noteLinks(touching item: Item) {
        var ids: Set<ItemID> = [item.id]
        for edge in item.edgesOut {
            ids.insert(edge.from)
            if case .item(let other) = edge.to { ids.insert(other) }
        }
        for id in ids { records[id]?.noteLink() }
    }

    /// A view changed elsewhere may list other items, so its last list is dropped. The others keep theirs until
    /// read again, since a read begun before is dropped.
    func take(_ views: [LibraryView]) {
        let current = Set(views)
        viewed = viewed.filter { id, _ in self.views.contains { $0.id == id && current.contains($0) } }
            .mapValues { Search(revision: -1, hits: $0.hits, running: false) }
        // A search of a view lists what the view held, which may have changed.
        for key in searches.keys where key.isOfView { searches[key]?.revision = -1 }
        if self.views != views { self.views = views }
        viewsGeneration += 1
        viewsFailing.formIntersection(views.map(\.id))
        // A preview does not depend on the view it was asked for, only on its fallback, so it is kept unless the view is gone.
        let ids = Set(views.map(\.id))
        previews = previews.filter { ids.contains($0.key.view) }
        previewOrder.removeAll { previews[$0] == nil }
        lastPreview = lastPreview.filter { ids.contains($0.key) }
        newestPreviewRead = newestPreviewRead.filter { ids.contains($0.key) }
        previewsFailing.formIntersection(ids)
        viewRevision += 1
    }

    func reindex() {
        let interval = Telemetry.begin(.library, "reindex", ("items", records.count))
        defer { interval.end() }
        index = MarfaItemIndex()
        for record in records.values { index.insert(record.item, catalogue: catalogue) }
        contentRevision += 1
        membershipRevision += 1
    }

    private static func placesDiffer(_ old: Item, _ new: Item) -> Bool {
        old.state != new.state || old.tier != new.tier || old.tags != new.tags || old.type != new.type
            || old.source != new.source || old.edgesOut != new.edgesOut
    }

    private func answered(_ id: WriteID, _ outcome: WriteOutcome) {
        let refusal = refusals.removeValue(forKey: id)
        let textWrite = textWrites.removeValue(forKey: id)
        let typed = textWrite?.typed
        let run = undoRuns.removeValue(forKey: id)
        if case .refused(let problem) = outcome, let run, MarfaEngine.isHeldRefusal(problem.code) {
            giveBack(run, problem, title: refusal?.title, text: typed ?? refusal?.text)
        } else if case .refused(let problem) = outcome, problem.code == MarfaEngine.withdrawnCode {
            // The person withdrew it themselves.
        } else if case .refused(let problem) = outcome, let refusal {
            let message = problem.message ?? String(localized: "The Marfa server refused this change.")
            if problem.code == MarfaEngine.closedCode {
                notices.notKept(refusal.title, text: typed ?? refusal.text)
            } else if problem.notQueued, let text = typed ?? refusal.unqueuedText {
                // Nothing queued it, so the text is in no write the person could copy it from, and the page is
                // about to show the text the library holds.
                notices.notKept(refusal.title, text: text, reason: message)
            } else if let typed {
                // The refused write stays listed, but the page is about to show the text the library holds.
                notices.notKept(refusal.title, text: typed, reason: String(localized: "\(message) The change is also listed in Settings."))
            } else {
                notices.tell(refusal.title, message)
            }
        }
        if let created = creating.removeValue(forKey: id), case .refused = outcome, records[created] == nil {
            refusedCreations.insert(created)
        }
        settleReplacement(id, outcome)
        guard let item = textWrite?.item else { return }
        unsettledText[item]?.remove(id)
        guard unsettledText[item]?.isEmpty == true else { return }
        unsettledText[item] = nil
        // Text still waiting was typed over what the copy holds, so that stays aside for it; it may go now.
        if waitingText[item] != nil { return waitEnded(item) }
        // The server may have merged the text, or kept its own and put the person's on a copy: the source tells
        // what the copy holds in the change that follows the answer, and this is what it held before that.
        if let body = sourceText.removeValue(forKey: item) { hold([body]) }
    }

    /// The write is in the copy and read again, or was answered before that: a change waiting for it may go on.
    private func settle(_ write: WriteID) {
        guard unsettled.remove(write) != nil else { return }
        for index in waiters.indices { waiters[index].pending.remove(write) }
        let done = waiters.filter { $0.pending.isEmpty }
        waiters.removeAll { $0.pending.isEmpty }
        for waiter in done { waiter.resume.resume() }
    }

    /// Lets every waiting change go on, as when the source's changes have ended.
    func endWaits() {
        unsettled = []
        let all = waiters
        waiters = []
        for waiter in all { waiter.resume.resume() }
    }

    /// Whether the source took the write, so it will be taken or answered.
    func isFollowed(_ write: WriteID) -> Bool { refusals[write] != nil }

    /// A write a step sends after its first writes were made. The engine holds it like them while the copy catches up,
    /// but one it gives back is told as refused and puts no step back, since the step was made.
    func leaveOutOfGiveBack(_ write: WriteID) { undoRuns[write] = nil }
}
