import Foundation

/// How well a title in the command palette answers what was typed, ignoring case and accents: best when the
/// title starts with it, then when one of its words does, then when it holds it anywhere, and last when it
/// holds its letters in order, so "nn" finds New Note.
nonisolated enum PaletteMatch {
    /// Lower is better; nil when the title does not answer the query at all. An empty query matches everything
    /// equally.
    static func score(_ title: String, _ query: String) -> Int? {
        let query = fold(query.trimmingCharacters(in: .whitespaces))
        guard !query.isEmpty else { return 0 }
        let title = fold(title)
        if title.hasPrefix(query) { return 0 }
        if let range = title.range(of: query) {
            let wordStart = range.lowerBound == title.startIndex || !title[title.index(before: range.lowerBound)].isLetter
            return wordStart ? 1 : 2
        }
        var remaining = query.filter { !$0.isWhitespace }[...]
        for character in title where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return 3 }
        }
        return nil
    }

    /// The indices of the titles that answer the query, best first and otherwise in the order given.
    static func ranked(_ titles: [String], _ query: String) -> [Int] {
        var scored: [(index: Int, score: Int)] = []
        for (index, title) in titles.enumerated() {
            if let score = score(title, query) { scored.append((index, score)) }
        }
        return scored.sorted { ($0.score, $0.index) < ($1.score, $1.index) }.map(\.index)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
