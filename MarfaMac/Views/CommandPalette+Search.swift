import SwiftUI

extension CommandPalette {
    /// Everything that can change what the palette lists, other than the query.
    struct Basis: Equatable {
        let library: ObjectIdentifier
        let content: Int
        let membership: Int
        let mode: Browser.Palette
        let returnFocus: Browser.Pane
        let selection: Set<ItemID>
        let filters: PaletteFilters
        /// What a typed search keeps and leaves out, which the items it lists follow.
        let narrowing: SearchNarrowing
        let typed: Bool
    }

    /// What is held across runs of the body: the items' titles for a basis, and how the titles ranked for a query.
    /// The commands are never held, since they read the editor, the browser and the host, which change while the
    /// palette is open and are not part of the basis.
    final class Listing {
        var items: (basis: Basis, items: [Item], titles: [String], leftOut: [Item], leftOutTitles: [String])?
        var leftOutMatches: (key: Ranking, items: [Item])?
        var ranking: (key: Ranking, picks: [PaletteMatch.Pick], scores: [Int])?
    }

    struct Ranking: Equatable {
        let basis: Basis
        let query: String
        let fixedTitles: [String]
    }

    private var basis: Basis {
        Basis(library: ObjectIdentifier(library), content: library.contentRevision, membership: library.membershipRevision,
              mode: mode, returnFocus: returnFocus, selection: browser.selection, filters: filterState.filters,
              narrowing: askedNarrowing, typed: isTyped)
    }

    var isTyped: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// What the search keeps and leaves out: the Type filter, a type following its Include Subtypes choice, and what
    /// this library leaves out of search.
    private var narrowing: SearchNarrowing {
        let filters = filterState.filters
        let stacked = Set(browser.stackedTypes.map { TypeID($0) })
        return SearchNarrowing(
            types: filters.types, typesWithSubtypes: stacked.intersection(filters.types),
            excludesTypes: filters.negated.contains(.type), leaveOut: libraries?.searchLeaveOut ?? SearchLeaveOut(),
            includesArchived: includesArchived, includesInbox: includesInbox)
    }

    /// The search a query and its narrowing stand for, so a change of either starts the answer again.
    struct SearchAsk: Hashable {
        let query: String
        let narrowing: SearchNarrowing
        let showsLeftOut: Bool
    }

    var searchAsk: SearchAsk { SearchAsk(query: query, narrowing: narrowing, showsLeftOut: showsLeftOut) }

    /// A search is not held by `listing`: its answer arrives later, and `searched` follows it (`watchSearch`).
    func shown() -> [Section] {
        mode == .search ? found : matching(basis)
    }

    /// Says how many more items matched in what is left out of search, or nil where none did.
    var leftOutLine: String? {
        guard isTyped, !showsLeftOut else { return nil }
        if mode != .search {
            // The titles the palette matches itself: what is left out and answers them, counted in full.
            return SearchLeftOutLine.text(
                for: listing.leftOutMatches?.items ?? [], isCapped: false, narrowing: narrowing, catalogue: library.catalogue,
                sources: library.sources)
        }
        guard !leftOut.isPending else { return nil }
        return SearchLeftOutLine.text(
            for: leftOutItems, isCapped: leftOut.isCapped, narrowing: narrowing, catalogue: library.catalogue, sources: library.sources)
    }

    /// The active items the filters let through, most recently edited first, and their titles. Once words are typed, an
    /// item left out of search is not listed: the ones that would answer them are in `leftOut`, which the line at the
    /// foot counts. Worked out once for a basis, which holds the filters and the narrowing, and not for each keystroke
    /// or hover.
    private func filteredItems(_ basis: Basis) -> (items: [Item], titles: [String], leftOut: [Item], leftOutTitles: [String]) {
        if let held = listing.items, held.basis == basis { return (held.items, held.titles, held.leftOut, held.leftOutTitles) }
        let typed = basis.narrowing
        let catalogue = library.catalogue
        let recent = browser.paletteIndex(in: library).recent
        var kept = recent
        var out: [Item] = []
        if basis.typed {
            (kept, out) = typed.split(recent, in: catalogue)
        } else {
            kept = recent.filter { typed.admitsType($0.type, in: catalogue) }
        }
        let items = basis.filters.afterSearch.apply(to: kept, now: library.now())
        let leftOutItems = basis.filters.afterSearch.apply(to: out, now: library.now())
        let titles = items.map(\.title)
        let leftOutTitles = leftOutItems.map(\.title)
        listing.items = (basis, items, titles, leftOutItems, leftOutTitles)
        return (items, titles, leftOutItems, leftOutTitles)
    }

    /// The commands, places and items that answer the query, in sections. The commands are built each time, since
    /// what they offer changes under an open palette. The titles are ranked first and an entry is built only for each
    /// of the best `PaletteMatch.listLimit` items, never for every item in the library.
    private func matching(_ basis: Basis) -> [Section] {
        let commands = commands
        let fixed = commands + places
        let fixedTitles = fixed.map(\.title)
        let (recent, itemTitles, leftOutItems, leftOutTitles) = filteredItems(basis)
        let typed = isTyped
        let key = Ranking(basis: basis, query: query, fixedTitles: fixedTitles)
        let picks: [PaletteMatch.Pick]
        let scores: [Int]
        if let held = listing.ranking, held.key == key {
            (picks, scores) = (held.picks, held.scores)
        } else {
            let scored = titles.scoredPicks(fixed: fixedTitles, items: typed ? itemTitles : [], query)
            picks = scored.map(\.pick)
            scores = scored.map(\.score)
            listing.ranking = (key, picks, scores)
        }
        if typed, !leftOutItems.isEmpty {
            if listing.leftOutMatches?.key != key {
                listing.leftOutMatches = (key, titles.ranked(leftOutTitles, query).map { leftOutItems[$0] })
            }
        } else {
            listing.leftOutMatches = nil
        }
        let sections = PaletteSections.forCommands(picks: picks, scores: scores, typed: typed, groups: commands.map(\.group), recentCount: recent.count)
        return sections.map { section in
            Section(kind: section.kind, rows: section.rows.map { pick in
                switch pick {
                case .fixed(let index): fixed[index]
                case .item(let index): itemEntry(recent[index])
                case .searchItems: searchItemsEntry
                }
            })
        }
    }

    func refreshSearch() {
        guard mode == .search, isTyped else {
            setSearched(.none, leftOut: .none)
            return
        }
        setSearched(library.search(query, narrowedBy: askedNarrowing), leftOut: askedLeftOut)
    }

    /// The search as asked: with what is left out, unless Show asked once for everything.
    private var askedNarrowing: SearchNarrowing {
        var asked = narrowing
        if showsLeftOut { asked.leaveOut = SearchLeaveOut() }
        return asked
    }

    /// What is left out and also matches, read only while a line would say so.
    private var askedLeftOut: SearchResults {
        showsLeftOut ? .none : library.searchLeftOut(query, narrowedBy: narrowing)
    }

    private func setSearched(_ results: SearchResults, leftOut found: SearchResults) {
        searched = results
        leftOut = found
        applyFilters(to: results, leftOut: found)
    }

    func applyFilters(to results: SearchResults, leftOut found: SearchResults) {
        let rest = filterState.filters.afterSearch
        searchedItems = searchOrder.ordered(rest.apply(to: results.items, now: library.now()))
        leftOutItems = rest.apply(to: found.items, now: library.now())
    }

    /// Keeps `searched` current for the query: the library's answer arrives later through its observed state, so each
    /// run reads it under observation and waits for the next change.
    func watchSearch() async {
        guard mode == .search, isTyped else { return }
        let words = query
        let asked = askedNarrowing
        let counted = showsLeftOut
        let leaving = narrowing
        while !Task.isCancelled {
            let (changes, signal) = AsyncStream.makeStream(of: Void.self)
            let (results, found) = withObservationTracking {
                (library.search(words, narrowedBy: asked), counted ? SearchResults.none : library.searchLeftOut(words, narrowedBy: leaving))
            } onChange: {
                signal.yield()
                signal.finish()
            }
            setSearched(results, leftOut: found)
            for await _ in changes { break }
        }
    }

    /// What the palette says when it lists nothing. A search from a copy that is filling or behind never says nothing
    /// matches, since what matches may not have arrived (the rule `SearchEmptyState` follows in the window).
    enum EmptyAnswer: Equatable { case noResults, stillLooking }

    static func emptyAnswer(searching: Bool, results: SearchResults) -> EmptyAnswer {
        searching && results.isIncomplete ? .stillLooking : .noResults
    }

    /// The most a search lists.
    static let searchLimit = 50

    /// What a search lists: the best matches, in the order the library ranked them. Sorting them by date would
    /// push a strong old match out past the limit.
    static func listed(_ items: [Item]) -> [Item] {
        Array(items.prefix(searchLimit))
    }

    /// Items whose text or title has what was typed, best match first, with the items named by the words typed
    /// apart from those that hold them in the text; or the most recently edited before anything is typed.
    private var found: [Section] {
        let results = isTyped ? searched : nil
        let items = results == nil ? Array(filteredItems(basis).items.prefix(12)) : Self.listed(searchedItems)
        let now = library.now()
        let entries = items.map { item in
            // An excerpt that is the title says nothing the title does not, so the preview stands.
            let excerpt = results?.excerpts[item.id].flatMap { $0.plainText == item.name ? nil : $0 }
            return Entry(
                id: "note:\(item.id)", title: item.displayTitle, detail: library.placeLabel(of: item),
                snippet: item.preview.isEmpty ? about(item) : item.preview, excerpt: excerpt,
                date: DateDisplay.text(of: item.modified, place: .list, format: dateFormat, now: now),
                icon: .type(library.catalogue.icon(for: item.type)), item: item.id, takesFocus: true
            ) {
                reveal(item)
            }
        }
        return PaletteSections.forSearch(rows: entries, typed: isTyped) { entry in
            PaletteMatch.matchRange(in: entry.title, query) != nil
        }
    }

    /// A search row's second line for an item with no text of its own: its type, or Inbox, and the collections it is
    /// in, so every row in Search Items has two lines.
    private func about(_ item: Item) -> String {
        let place = library.placeLabel(of: item)
        let collections = item.collectionIDs.compactMap { library.item($0)?.displayTitle }
        guard !collections.isEmpty else { return place }
        return String(localized: "\(place) in \(collections.formatted(.list(type: .and)))", comment: "A search row's second line: an item's type, then the collections it is in.")
    }

    static let searchItemsID = "command:searchItemsFor"

    /// The last row under Items: the same words, searched in the text of every item.
    private var searchItemsEntry: Entry {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Entry(id: Self.searchItemsID, title: String(localized: "Search Items for “\(typed)”"), icon: .symbol("magnifyingglass"),
                     shortcut: keys(.searchItems), takesFocus: true) {
            browser.paletteSeed = typed
            browser.palette = .search
        }
    }

    /// An item by title, with its type.
    private func itemEntry(_ item: Item) -> Entry {
        Entry(id: "note:\(item.id)", title: item.displayTitle, detail: library.placeLabel(of: item),
              icon: .type(library.catalogue.icon(for: item.type)), item: item.id, takesFocus: true) {
            reveal(item)
        }
    }

    func reveal(_ item: Item) {
        browser.reveal(item, in: library, order: order)
    }
}
