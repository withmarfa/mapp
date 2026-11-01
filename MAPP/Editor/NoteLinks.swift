import Foundation
import Marfa

/// How the page names a note in a `[[link]]`: by its title, or by its identity with the title as a label. Whether a
/// spelling names the note is the core's to say (`ItemLibrary.bodyLink(to:in:)`); this only builds the text.
nonisolated enum NoteLinks {
    /// Whether `[[inner]]` is one link the core reads with exactly this name and alias, so the text survives
    /// as written: no `]]`, line break or padding in it. Marfa has no escape in a link, so a backslash is part of the
    /// name.
    static func spells(_ inner: String, as name: String, alias: String? = nil) -> Bool {
        guard !name.isEmpty else { return false }
        let text = "[[\(inner)]]"
        let parts = linkParts(in: text)
        guard parts.count == 1, let link = parts.first, link.text == text else { return false }
        return link.name.text == name && link.heading == nil && link.alias?.text == alias
    }

    /// A title as one line of a link's label. Line breaks and control characters become one space; nothing else is
    /// changed, since a link has no escape.
    static func label(_ title: String) -> String {
        var words: [String] = []
        var word = String.UnicodeScalarView()
        func end() {
            if !word.isEmpty { words.append(String(word)) }
            word = String.UnicodeScalarView()
        }
        for scalar in title.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: end()
            default: word.append(scalar)
            }
        }
        end()
        return NoteName.trimmed(words.joined(separator: " "))
    }

    /// A note the page may offer by its title.
    struct Match: Hashable, Sendable {
        let id: ItemID
        let title: String
    }

    /// Keeps each note's title folded for matching, so a query that grows one letter at a time folds nothing again
    /// and a library of tens of thousands of notes is read in one pass. It works off the main actor, on a copy of
    /// the items, so typing in the page and the window never wait on it.
    actor Index {
        private struct Entry {
            let version: ItemVersion
            let title: String
            let folded: [Character]
            let modified: Date
        }

        private var entries: [ItemID: Entry] = [:]
        /// How many titles have been folded, so a test can tell that a query folded none again.
        private(set) var foldedCount = 0

        /// The notes whose titles answer what was typed after `[[`, best first (the closest match, then the most
        /// recently edited). Whether a link to one names it alone is the core's to say, so the caller asks.
        func matches(for text: String, among items: [Item], limit: Int) -> [Match] {
            let query = PaletteMatch.Query(text)
            var notes = 0
            var best: [(match: Match, score: Int, modified: Date)] = []
            for item in items where !item.isFile {
                notes += 1
                if let kept = entries[item.id], kept.version == item.version, kept.title == item.title { continue }
                entries[item.id] = Entry(
                    version: item.version, title: item.title, folded: Array(PaletteMatch.fold(item.title)), modified: item.modified)
                foldedCount += 1
            }
            if entries.count != notes {
                let live = Set(items.lazy.filter { !$0.isFile }.map(\.id))
                for id in entries.keys where !live.contains(id) { entries[id] = nil }
            }
            for item in items where !item.isFile {
                guard let entry = entries[item.id], let score = PaletteMatch.score(folded: entry.folded, query) else { continue }
                Self.keep((Match(id: item.id, title: entry.title), score, entry.modified), in: &best, limit: limit)
            }
            return best.map(\.match)
        }

        private typealias Candidate = (match: Match, score: Int, modified: Date)

        /// Whether `a` is offered before `b`: a closer match, then a more recent edit, then the title.
        private static func precedes(_ a: Candidate, _ b: Candidate) -> Bool {
            if a.score != b.score { return a.score < b.score }
            if a.modified != b.modified { return a.modified > b.modified }
            return a.match.title < b.match.title
        }

        /// Keeps the `limit` best without ordering the notes that did not make it.
        private static func keep(_ match: Candidate, in best: inout [Candidate], limit: Int) {
            if best.count == limit, let last = best.last, !precedes(match, last) { return }
            let at = best.firstIndex { precedes(match, $0) } ?? best.endIndex
            best.insert(match, at: at)
            if best.count > limit { best.removeLast() }
        }
    }
}

extension ItemLibrary {
    /// The notes the picker lists, most recently edited first. A note that cannot be linked is told when it is chosen.
    func notesToLink(excluding id: ItemID? = nil) -> [Item] {
        items(in: .allNotes).filter { !$0.isFile && $0.id != id }.sorted { $0.modified > $1.modified }
    }

    /// The titles to offer for what was typed after `[[` in `note`, best first, each one only where `[[title]]`, written
    /// there, names that note as far as the copy knows (`LinkAnswer.names`). A title that two notes go by, or that a
    /// link cannot spell, is left out. The closest matches are asked of the core together, so a few left out leave the list full.
    func noteNames(matching query: String, in note: ItemID? = nil, using index: NoteLinks.Index, limit: Int = 12) async -> [String] {
        let matches = await index.matches(for: query, among: items(in: .allNotes), limit: limit * 4)
            .filter { NoteLinks.spells($0.title, as: $0.title) }
        guard !matches.isEmpty, let answers = await linkAnswers(of: matches.map(\.title), in: note) else { return [] }
        return zip(matches, answers).compactMap { $0.1.names($0.0.id) ? $0.0.title : nil }.prefix(limit).map { $0 }
    }
}
