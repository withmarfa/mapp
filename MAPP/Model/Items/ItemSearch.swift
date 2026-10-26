import Foundation

/// The words around what a search found, as the copy cut them from one item. The copy marks each match, so the app
/// never matches anything itself; it only reads the marks.
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

    /// Reads the copy's excerpt: HTML in which the text is escaped and each match sits in `<mark>` tags. Nil where
    /// it holds no text.
    init?(html: String, version: ItemVersion, modified: Date) {
        self.version = version
        self.modified = modified
        var runs: [Run] = []
        var text = ""
        var isMatch = false
        // Runs of white space, a line break among them, read as one space, so an excerpt keeps to its lines.
        var endsInSpace = true

        func flush() {
            guard !text.isEmpty else { return }
            if let last = runs.last, last.isMatch == isMatch {
                runs[runs.count - 1].text += text
            } else {
                runs.append(Run(text: text, isMatch: isMatch))
            }
            text = ""
        }
        func append(_ character: Character) {
            if character.isWhitespace {
                guard !endsInSpace else { return }
                text.append(" ")
                endsInSpace = true
            } else {
                text.append(character)
                endsInSpace = false
            }
        }

        var index = html.startIndex
        while index < html.endIndex {
            let character = html[index]
            if character == "<", let close = html[index...].firstIndex(of: ">") {
                let name = html[html.index(after: index)..<close].trimmingCharacters(in: .whitespaces).lowercased()
                if name == "mark" || name == "/mark" {
                    flush()
                    isMatch = name == "mark"
                }
                index = html.index(after: close)
            } else if character == "&", let end = html[index...].prefix(12).firstIndex(of: ";"),
                      let decoded = Self.entity(html[html.index(after: index)..<end]) {
                decoded.forEach(append)
                index = html.index(after: end)
            } else {
                append(character)
                index = html.index(after: index)
            }
        }
        flush()
        // White space at either end is no part of an excerpt.
        if let first = runs.first, first.text.hasPrefix(" ") {
            runs[0].text.removeFirst()
            if runs[0].text.isEmpty { runs.removeFirst() }
        }
        if let last = runs.last, last.text.hasSuffix(" ") {
            runs[runs.count - 1].text.removeLast()
            if runs[runs.count - 1].text.isEmpty { runs.removeLast() }
        }
        guard !runs.isEmpty else { return nil }
        self.runs = Self.bounded(runs)
    }

    /// The escapes the copy writes, and any other numeric reference.
    private static func entity(_ name: Substring) -> String? {
        switch name {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        default:
            guard name.hasPrefix("#") else { return nil }
            let digits = name.dropFirst()
            let value = digits.hasPrefix("x") || digits.hasPrefix("X")
                ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
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
    var isCapped = false
    /// This search has not been answered yet, so what is listed is what an earlier one found and an empty list
    /// says nothing.
    var isPending = false
}
