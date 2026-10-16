import Foundation

/// How well a title in the command palette answers what was typed, ignoring case and accents: best when the
/// title starts with it, then when one of its words does, then when it holds it anywhere, and last when it
/// holds its letters in order, so "nn" finds New Note.
nonisolated enum PaletteMatch {
    /// A query folded once, for scoring many titles against it.
    nonisolated struct Query: Sendable {
        /// The folded query as Unicode scalar values.
        fileprivate let scalars: [UInt32]
        /// The same without whitespace, whose letters a title may hold in order.
        fileprivate let letters: [UInt32]

        init(_ text: String) {
            let folded = PaletteMatch.fold(text.trimmingCharacters(in: .whitespaces)).unicodeScalars
            scalars = folded.map(\.value)
            letters = folded.filter { !$0.properties.isWhitespace }.map(\.value)
        }

        var isEmpty: Bool { scalars.isEmpty }
    }

    /// A title folded and read as Unicode scalar values, for a caller that keeps its titles and asks again as the
    /// query grows.
    static func folded(_ title: String) -> [UInt32] {
        fold(title).unicodeScalars.map(\.value)
    }

    /// Lower is better; nil when the title does not answer the query at all. An empty query matches everything
    /// equally.
    static func score(_ title: String, _ query: String) -> Int? {
        let query = Query(query)
        return query.isEmpty ? 0 : score(folded: folded(title), query)
    }

    /// The score of a title read by `folded(_:)`.
    static func score(folded title: [UInt32], _ query: Query) -> Int? {
        guard !query.isEmpty else { return 0 }
        let wanted = query.scalars
        if title.count >= wanted.count {
            if title.starts(with: wanted) { return 0 }
            var start = 1
            let last = title.count - wanted.count
            while start <= last {
                if title[start] == wanted[0], title[start...].starts(with: wanted) {
                    return isLetter(title[start - 1]) ? 2 : 1
                }
                start += 1
            }
        }
        guard !query.letters.isEmpty else { return nil }
        var next = 0
        for scalar in title where scalar == query.letters[next] {
            next += 1
            if next == query.letters.count { return 3 }
        }
        return nil
    }

    private static func isLetter(_ value: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(value) else { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
        default: return false
        }
    }

    /// The indices of the titles that answer the query, best first and otherwise in the order given.
    static func ranked(_ titles: [String], _ query: String) -> [Int] {
        let query = Query(query)
        var scored: [(index: Int, score: Int)] = []
        for (index, title) in titles.enumerated() {
            if let score = score(folded: folded(title), query) { scored.append((index, score)) }
        }
        return scored.sorted { ($0.score, $0.index) < ($1.score, $1.index) }.map(\.index)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
