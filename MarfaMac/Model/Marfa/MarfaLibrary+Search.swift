import Foundation

/// Link answers and search, which the copy answers beside the views: until a search returns, its last results stand.
extension MarfaLibrary {
    /// What the core says each link target names (`Items.linkCandidates`), from the copy alone and read as a link in
    /// `itemID` when given, so an answer is whatever saving that link there would do. Nil where the core cannot ask,
    /// such as for an item the copy does not hold.
    func linkAnswers(of targets: [String], in itemID: ItemID?) async -> [LinkAnswer]? {
        guard !targets.isEmpty else { return [] }
        return try? await source.linkAnswers(of: targets, in: itemID)
    }

    /// Answers from the copy's own search, which runs beside the views: until it returns, the last results stand,
    /// and the views are told when the new ones arrive. A newer search cancels the one it replaces, and an older
    /// answer is not shown. A change to the items runs the search again, and so does a change in how the copy is
    /// filling after a search that found it incomplete, so the notice follows the latest answer.
    func search(_ query: String, in scope: SearchScope) -> SearchResults {
        search(SearchKey(query: query.trimmingCharacters(in: .whitespacesAndNewlines), scope: scope))
    }

    /// A search of every item with what `narrowing` keeps and leaves out applied inside the copy's call, so the most
    /// a search lists is counted after them.
    func search(_ query: String, narrowedBy narrowing: SearchNarrowing) -> SearchResults {
        search(SearchKey(query: query.trimmingCharacters(in: .whitespacesAndNewlines), scope: .everywhere, narrowing: narrowing))
    }

    /// What the same search finds among the items `narrowing` leaves out, at most `SearchResults.leftOutLimit` of
    /// them, one more call to the copy with the leave-out in place of its exclusion. Nothing is found where nothing
    /// is left out.
    func searchLeftOut(_ query: String, narrowedBy narrowing: SearchNarrowing) -> SearchResults {
        guard !narrowing.leaveOut.isEmpty else { return .none }
        return search(SearchKey(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines), scope: .everywhere, narrowing: narrowing, asksLeftOut: true))
    }

    private func search(_ key: SearchKey) -> SearchResults {
        guard !key.query.isEmpty else { return .none }
        _ = searchRevision
        let revision = contentRevision
        let fill = syncReport.fill
        let held = searches[key]
        let outdated = held.map { run in
            !run.running && (run.revision != revision || (run.found.isIncomplete && run.fill != fill))
        } ?? true
        if outdated { startSearch(key, at: revision, fill: fill) }
        let answered = held?.answered ?? false
        // Until the answer arrives the last one stands, cut to what this narrowing admits, so a changed Type shows
        // nothing of another type and the list does not empty and fill.
        let ids = answered ? held?.found.hits ?? [] : key.asksLeftOut ? [] : lastFound.filter { id in
            guard let item = records[id]?.item else { return false }
            return key.narrowing.admits(item, in: catalogue)
        }
        var results = SearchResults(isIncomplete: held?.found.isIncomplete ?? false, isCapped: held?.found.isCapped ?? false)
        results.isPending = !answered
        for id in ids {
            guard let record = records[id], record.isHeld, record.item.state != .trashed else { continue }
            // The copy's filter for what is left out cannot say a type's own items from its subtypes'.
            if key.asksLeftOut, !key.narrowing.admitsType(record.item.type, in: catalogue) { continue }
            results.items.append(record.item)
            // An excerpt quotes the item as it was searched, so one for an item since edited would show text that
            // is no longer there.
            if answered, let excerpt = held?.found.excerpts[id], excerpt.describes(record.item) { results.excerpts[id] = excerpt }
        }
        return results
    }

    /// The copy's way of narrowing to a place or a view, or nil where the place stands for no query: the search
    /// then covers everything, as `SearchScope.narrows` says.
    private func target(for key: SearchKey) throws -> SearchTarget? {
        guard key.scope == .everywhere, !key.narrowing.isEmpty else { return target(for: key.scope) }
        let expression = key.asksLeftOut
            ? try key.narrowing.leftOutOfSearch(in: catalogue) : try key.narrowing.kept(in: catalogue)
        guard !expression.matchesNothing else { return nil }
        var query = Self.searchScope
        query.types = expression.types
        query.states = key.narrowing.searchedStates
        query.tier = key.narrowing.searchedTier
        return .items(query, filter: expression.filter, limit: key.asksLeftOut ? SearchResults.leftOutLimit : SearchResults.limit)
    }

    private func target(for scope: SearchScope) -> SearchTarget {
        switch scope {
        case .everywhere: .items(Self.searchScope)
        case .view(let id): views.contains(where: { $0.id == id }) ? .view(id) : .items(Self.searchScope)
        case .query(let query): Self.target(of: query)
        }
    }

    private static func target(of query: LibraryViewQuery) -> SearchTarget {
        let narrowed = ItemQuery(types: Set(query.types), beneath: query.beneath, states: query.states ?? [], tier: query.tier)
        return .items(narrowed, filter: query.filter)
    }

    /// A search that fails keeps the results already shown for the same words and place and says why, rather than
    /// showing that nothing was found, and shows nothing where it has none; it is not asked again until the items
    /// change. A newer search with the same place, narrowing and leave-out choice cancels this one. The revision
    /// and fill are stored with the answer, so a cancelled refresh stays as old as the answer it kept. An answer
    /// from an earlier run is dropped.
    private func startSearch(_ key: SearchKey, at revision: Int, fill: LibraryFill?) {
        let turn = supersede(key)
        let channel = SearchChannel(key)
        let replaced = searches.keys.filter { other in
            other != key && SearchChannel(other) == channel && searches[other]?.running == true
        }
        for other in replaced {
            _ = supersede(other)
            if var run = searches[other], run.answered {
                run.running = false
                searches[other] = run
            } else {
                searches[other] = nil
                searchOrder.removeAll { $0 == other }
            }
        }
        var epoch: Int?
        if !key.asksLeftOut {
            shownEpoch += 1
            epoch = shownEpoch
        }
        if var run = searches[key] {
            run.running = true
            searches[key] = run
        } else {
            searches[key] = SearchRun(revision: revision, running: true, fill: fill)
        }
        searchOrder.removeAll { $0 == key }
        searchOrder.append(key)
        while searchOrder.count > 16 {
            let dropped = searchOrder.removeFirst()
            _ = supersede(dropped)
            searches[dropped] = nil
            searchTasks[dropped] = nil
        }
        let asked: Result<SearchTarget?, any Error> = Result { try target(for: key) }
        let task = Task { [weak self, source] in
            let found: Result<SourceSearch?, any Error>
            do {
                // A narrowing that admits nothing is answered without asking the copy.
                if let target = try asked.get() {
                    found = .success(try await source.search(key.query, in: target))
                } else {
                    found = .success(nil)
                }
            } catch {
                found = .failure(error)
            }
            guard let self, searchTurns[key] == turn else { return }
            switch found {
            case .success(let answer):
                guard !Task.isCancelled else { return }
                // Nothing is asked of a narrowing that admits nothing, so how the copy stands is the only word on
                // whether more would match once it is whole.
                let result = answer ?? SourceSearch(isIncomplete: syncReport.fill.map { $0.state != .complete } ?? false)
                searches[key] = SearchRun(revision: revision, found: result, running: false, answered: true, fill: fill)
                if let epoch, epoch == shownEpoch { lastFound = result.hits }
            case .failure(let error) where error is CancellationError:
                return
            case .failure(let error):
                // Only this search's own earlier answer is kept; another's hits would be shown as this one's. A failure
                // says nothing of completeness, so the notice follows how the copy stands now.
                var kept = searches[key].flatMap { $0.answered ? $0.found : nil } ?? SourceSearch()
                kept.isIncomplete = syncReport.fill.map { $0.state != .complete } ?? false
                searches[key] = SearchRun(revision: revision, found: kept, running: false, answered: true, fill: fill)
                if !key.asksLeftOut { notices.tell(String(localized: "Can’t Search"), Self.searchFailure(error)) }
            }
            searchRevision += 1
        }
        searchTasks[key] = task
    }

    /// Forgets a search still running, so its answer cannot replace the one just asked.
    private func supersede(_ key: SearchKey) -> Int {
        searchTurn += 1
        searchTurns[key] = searchTurn
        searchTasks[key]?.cancel()
        return searchTurn
    }

    private static func searchFailure(_ error: any Error) -> String {
        (error as? SearchNarrowing.Refusal)?.message ?? error.localizedDescription
    }

    /// Searches that replace one another: the same place, the same narrowing, and the same choice of whether they
    /// ask for what was left out.
    private nonisolated struct SearchChannel: Hashable {
        var scope: SearchScope
        var narrowing: SearchNarrowing
        var asksLeftOut: Bool

        init(_ key: SearchKey) {
            scope = key.scope
            narrowing = key.narrowing
            asksLeftOut = key.asksLeftOut
        }
    }
}
