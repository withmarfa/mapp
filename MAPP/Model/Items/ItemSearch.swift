import Foundation

/// The words around what a search found, as the copy cut them from one item. The copy marks each match, so the app
/// never matches anything itself; it only keeps the runs to their lines and their reach.
nonisolated struct SearchExcerpt: Hashable, Sendable {
    nonisolated struct Run: Hashable, Sendable {
        var text: String
        var isMatch: Bool
    }

    /// The longest stretch of text kept on either side of a match, and the longest match, in characters. The copy
    /// cuts an excerpt to a few words, but a word can be as long as a pasted address or a block of code.
    static let reach = 120

    var runs: [Run]
    /// The item as it was when the excerpt was cut. The item has since changed if these differ from it, and the
    /// excerpt then describes text that is no longer there.
    var version: ItemVersion
    var modified: Date

    var plainText: String { runs.map(\.text).joined() }

    /// Whether the excerpt was cut from this very state of `item`.
    func describes(_ item: Item) -> Bool { item.version == version && item.modified == modified }

    /// Takes the runs the copy cut (`SearchHit.excerpt`), with each stretch of white space, a line break among
    /// them, read as one space so an excerpt keeps to its lines, and no space at either end. Nil where they hold
    /// no text.
    init?(runs given: [Run], version: ItemVersion, modified: Date) {
        self.version = version
        self.modified = modified
        var runs: [Run] = []
        // No space opens an excerpt.
        var endsInSpace = true
        for run in given {
            var text = ""
            for character in run.text {
                if character.isWhitespace {
                    guard !endsInSpace else { continue }
                    text.append(" ")
                    endsInSpace = true
                } else {
                    text.append(character)
                    endsInSpace = false
                }
            }
            guard !text.isEmpty else { continue }
            if let last = runs.last, last.isMatch == run.isMatch {
                runs[runs.count - 1].text += text
            } else {
                runs.append(Run(text: text, isMatch: run.isMatch))
            }
        }
        if let last = runs.last, last.text.hasSuffix(" ") {
            runs[runs.count - 1].text.removeLast()
            if runs[runs.count - 1].text.isEmpty { runs.removeLast() }
        }
        guard !runs.isEmpty else { return nil }
        self.runs = Self.bounded(runs)
    }

    /// Shortens what runs past `reach`, keeping the words nearest each match: the end of the text before the first
    /// one, the start of the text after the last, and both ends of the text between two.
    private static func bounded(_ runs: [Run]) -> [Run] {
        runs.enumerated().map { index, run in
            var run = run
            let count = run.text.count
            if run.isMatch {
                if count > reach { run.text = run.text.prefix(reach) + "…" }
            } else if index == 0, index == runs.count - 1 {
                if count > reach { run.text = run.text.prefix(reach) + "…" }
            } else if index == 0 {
                if count > reach { run.text = "…" + run.text.suffix(reach) }
            } else if index == runs.count - 1 {
                if count > reach { run.text = run.text.prefix(reach) + "…" }
            } else if count > 2 * reach {
                run.text = run.text.prefix(reach) + "…" + run.text.suffix(reach)
            }
            return run
        }
    }
}

/// Where a search looks.
nonisolated enum SearchScope: Hashable, Sendable {
    /// Every item that is not in the bin.
    case everywhere
    /// What the place lists, matched by the copy itself.
    case place(SidebarItem)
    /// What a type's place lists while it includes its subtypes: the type's items and theirs.
    case typeWithSubtypes(TypeID)

    /// Whether searching `place` alone finds anything different from searching everywhere: the places that stand
    /// for a query. Recents is a count of the latest edits, Recently Deleted is outside every search, the indexes
    /// list no items, and one favorite is a single item, so none of them can be searched alone; All Items is
    /// everywhere.
    static func narrows(_ place: SidebarItem) -> Bool {
        switch place {
        case .inbox, .favorites, .itemType, .collection, .source, .files, .view: true
        case .allNotes, .recents, .recentlyDeleted, .sources, .collections, .favoriteItem: false
        }
    }
}

/// What a source is asked to search.
nonisolated enum SearchTarget: Hashable, Sendable {
    /// The items `query` allows, narrowed by `filter` where one is given: an expression in the server's listing
    /// grammar, which the copy answers and `query` cannot.
    case items(ItemQuery, filter: String? = nil)
    /// What a saved view lists.
    case view(ItemID)
}

/// What a source found, best match first.
nonisolated struct SourceSearch: Hashable, Sendable {
    var hits: [ItemID] = []
    /// The excerpt of each hit that has one.
    var excerpts: [ItemID: SearchExcerpt] = [:]
    /// The copy is still being filled, or no longer reaches the server's changes, so it may hold more than it
    /// searched.
    var isIncomplete = false
    /// The copy found more than it listed.
    var isCapped = false
}

/// What the person sees of a search.
nonisolated struct SearchResults: Sendable {
    /// The most the copy lists for one search.
    static let limit = 500
    static let none = SearchResults()

    var items: [Item] = []
    /// The excerpt of each item that has one still true of it.
    var excerpts: [ItemID: SearchExcerpt] = [:]
    var isIncomplete = false
    /// The copy found more than it listed.
    var isCapped = false
    /// This search has not been answered yet, so what is listed is what an earlier one found and an empty list
    /// says nothing.
    var isPending = false

    /// How many results the list shows where the copy found more than it listed, for the notice that says so.
    var cappedCount: Int? { isCapped && !items.isEmpty ? items.count : nil }
}
