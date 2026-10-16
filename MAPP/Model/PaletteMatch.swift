import Foundation

/// How well a title in the command palette answers what was typed, ignoring case and accents: best when the
/// title starts with it, then when one of its words does, then when it holds it anywhere, and last when it
/// holds its letters in order, so "nn" finds New Note.
nonisolated enum PaletteMatch {
    /// A query folded once, for scoring many titles against it.
    nonisolated struct Query: Sendable {
        let folded: String
        /// The folded query without its whitespace, whose letters a title may hold in order.
        fileprivate let letters: String

        init(_ text: String) {
            folded = PaletteMatch.fold(text.trimmingCharacters(in: .whitespaces))
            letters = folded.filter { !$0.isWhitespace }
        }

        var isEmpty: Bool { folded.isEmpty }
    }

    /// Lower is better; nil when the title does not answer the query at all. An empty query matches everything
    /// equally.
    static func score(_ title: String, _ query: String) -> Int? {
        let query = Query(query)
        return query.isEmpty ? 0 : score(folded: fold(title), query)
    }

    /// The score of a title already folded by `fold`, for a caller that keeps the folded titles and asks again as
    /// the query grows.
    static func score(folded title: String, _ query: Query) -> Int? {
        guard !query.isEmpty else { return 0 }
        if title.hasPrefix(query.folded) { return 0 }
        if let range = title.range(of: query.folded) {
            let wordStart = range.lowerBound == title.startIndex || !title[title.index(before: range.lowerBound)].isLetter
            return wordStart ? 1 : 2
        }
        var remaining = query.letters[...]
        for character in title where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return 3 }
        }
        return nil
    }

    /// The indices of the titles that answer the query, best first and otherwise in the order given.
    static func ranked(_ titles: [String], _ query: String) -> [Int] {
        let query = Query(query)
        var scored: [(index: Int, score: Int)] = []
        for (index, title) in titles.enumerated() {
            if let score = query.isEmpty ? 0 : score(folded: fold(title), query) { scored.append((index, score)) }
        }
        return scored.sorted { ($0.score, $0.index) < ($1.score, $1.index) }.map(\.index)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
