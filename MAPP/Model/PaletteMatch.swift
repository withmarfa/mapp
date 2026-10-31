import Foundation

/// How well a title answers what was typed, ignoring case and accents: best when the title starts with it, then
/// when one of its words does, then when it holds it anywhere, and last when it holds its letters in order, so "nn"
/// finds New Note. The command palette, Link to Note and the page's `[[` suggestions all rank by it.
nonisolated enum PaletteMatch {
    /// What was typed, folded once for scoring many titles.
    struct Query: Sendable {
        fileprivate let characters: [Character]
        fileprivate let letters: [Character]

        init(_ text: String) {
            let folded = PaletteMatch.fold(text.trimmingCharacters(in: .whitespaces))
            characters = Array(folded)
            letters = folded.filter { !$0.isWhitespace }
        }

        var isEmpty: Bool { characters.isEmpty }
    }

    /// Keeps each title folded, so a list ranked again on every keystroke folds only what was typed.
    final class Titles {
        private var folded: [String: [Character]] = [:]

        /// The indices of the titles that answer the query, best first and otherwise in the order given.
        func ranked(_ titles: [String], _ query: String) -> [Int] {
            PaletteMatch.ranked(titles, Query(query)) { title in
                if let kept = folded[title] { return kept }
                let characters = Array(PaletteMatch.fold(title))
                folded[title] = characters
                return characters
            }
        }

        /// What the palette lists for a query, by title alone: with nothing typed, every fixed title and no item;
        /// otherwise every fixed title that answers it and the best `limit` items, in rank order, equal matches with the fixed ones first.
        func picks(fixed: [String], items: [String], _ query: String, limit: Int = PaletteMatch.listLimit) -> [Pick] {
            guard !PaletteMatch.Query(query).isEmpty else { return fixed.indices.map(Pick.fixed) }
            var itemsLeft = limit
            return ranked(fixed + items, query).compactMap { index in
                if index < fixed.count { return .fixed(index) }
                guard itemsLeft > 0 else { return nil }
                itemsLeft -= 1
                return .item(index - fixed.count)
            }
        }
    }

    /// Where a ranked title came from: the fixed list (commands and places) or the items.
    enum Pick: Equatable, Sendable {
        case fixed(Int)
        case item(Int)
    }

    /// The most items a typed query lists. Entries are built for these only, never for every item in the library.
    static let listLimit = 50

    /// Lower is better; nil when the title does not answer the query at all. An empty query matches everything
    /// equally.
    static func score(_ title: String, _ query: String) -> Int? {
        score(folded: Array(fold(title)), Query(query))
    }

    /// The same score, for a title already folded and read as characters.
    static func score(folded title: [Character], _ query: Query) -> Int? {
        guard !query.isEmpty else { return 0 }
        let wanted = query.characters
        if title.count >= wanted.count {
            if title.starts(with: wanted) { return 0 }
            var start = 1
            let last = title.count - wanted.count
            while start <= last {
                if title[start] == wanted[0], title[start...].starts(with: wanted) {
                    return title[start - 1].isLetter ? 2 : 1
                }
                start += 1
            }
        }
        guard !query.letters.isEmpty else { return nil }
        var next = 0
        for character in title where character == query.letters[next] {
            next += 1
            if next == query.letters.count { return 3 }
        }
        return nil
    }

    /// The indices of the titles that answer the query, best first and otherwise in the order given.
    static func ranked(_ titles: [String], _ query: String) -> [Int] {
        ranked(titles, Query(query)) { Array(fold($0)) }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func ranked(_ titles: [String], _ query: Query, folding: (String) -> [Character]) -> [Int] {
        var scored: [(index: Int, score: Int)] = []
        for (index, title) in titles.enumerated() {
            if let score = score(folded: folding(title), query) { scored.append((index, score)) }
        }
        return scored.sorted { ($0.score, $0.index) < ($1.score, $1.index) }.map(\.index)
    }
}
