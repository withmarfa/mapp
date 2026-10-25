import Foundation

/// How the page names a note in a `[[link]]`: by its title, or by a spelling the library resolves to that note alone
/// (`ItemLibrary.bodyLink(to:)`).
nonisolated enum NoteLinks {
    /// Whether `[[title]]` names the title as written. A link ends at `]]`, reads `|` as an alias and `#` as a
    /// heading, and the page reads `\` as an escape, so a title holding one is left out rather than linked to
    /// something else.
    static func canSpell(_ text: String) -> Bool {
        !text.isEmpty && text == NoteName.trimmed(text)
            && !text.unicodeScalars.contains { "[]|#\\\r\n".unicodeScalars.contains($0) }
    }

    /// Whether the text is spelled as an identity, which a link reads as the item with that identity before it
    /// looks at any title, as Marfa (`is_id`) does.
    static func looksLikeIdentity(_ text: String) -> Bool {
        text.count == 36 && UUID(uuidString: text) != nil
    }

    /// Whether a title can be the spelling of a link to its own note: it can be written, and it is not read as
    /// an identity, which would name whichever item holds that identity.
    static func canName(_ title: String) -> Bool {
        canSpell(title) && !looksLikeIdentity(title)
    }

    static func link(to title: String) -> String { "[[\(title)]]" }

    /// A link that names an item by its identity and shows its title: `[[identity|Title]]`, which Marfa reads as
    /// naming the identity and the page shows as the title. The title is made a single line and its `\`, `[`, `]`,
    /// `|` and `#` are escaped for the page's linked syntax; a title with nothing left shows nothing.
    static func identityLink(to identity: String, titled title: String) -> String {
        let shown = label(title)
        return shown.isEmpty ? "[[\(identity)]]" : "[[\(identity)|\(shown)]]"
    }

    /// A title as one line of a link's label. Line breaks and control characters become one space.
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
        var escaped = String.UnicodeScalarView()
        for scalar in NoteName.trimmed(words.joined(separator: " ")).unicodeScalars {
            if "\\[]|#".unicodeScalars.contains(scalar) { escaped.append("\\") }
            escaped.append(scalar)
        }
        return String(escaped)
    }

    /// A name as the library's links compare it: ignoring case and the form of accents.
    static func nameKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased().precomposedStringWithCanonicalMapping
    }

    /// Keeps each note's title folded for matching, so a query that grows one letter at a time folds nothing again
    /// and a library of tens of thousands of notes is read in one pass. It works off the main actor, on a copy of
    /// the items, so typing in the page and the window never wait on it.
    actor Index {
        private struct Entry {
            let version: ItemVersion
            let title: String
            let folded: [Character]
            let key: String
            let nameable: Bool
            let modified: Date
        }

        private var entries: [ItemID: Entry] = [:]
        /// How many notes go by each name, since a title another note shares would be an ambiguous link.
        private var holders: [String: Int] = [:]
        /// How many titles have been folded, so a test can tell that a query folded none again.
        private(set) var foldedCount = 0

        /// The titles that answer what was typed after `[[`, best first (the closest match, then the most recently
        /// edited), each once. A title another note also goes by is not offered, since a link to it would not say
        /// which note, nor one the note it is typed in already links to another note (`established`).
        func names(matching text: String, among items: [Item], established: [String: ItemID] = [:], limit: Int) -> [String] {
            let query = PaletteMatch.Query(text)
            var notes = 0
            var best: [(title: String, score: Int, modified: Date)] = []
            for item in items where !item.isFile {
                notes += 1
                if let kept = entries[item.id], kept.version == item.version, kept.title == item.title { continue }
                if let old = entries[item.id] { forget(old.key) }
                let folded = PaletteMatch.fold(item.title)
                let entry = Entry(
                    version: item.version, title: item.title, folded: Array(folded), key: NoteLinks.nameKey(NoteName.trimmed(item.title)),
                    nameable: NoteLinks.canName(item.title), modified: item.modified)
                entries[item.id] = entry
                holders[entry.key, default: 0] += 1
                foldedCount += 1
            }
            if entries.count != notes {
                let live = Set(items.lazy.filter { !$0.isFile }.map(\.id))
                for (id, entry) in entries where !live.contains(id) {
                    forget(entry.key)
                    entries[id] = nil
                }
            }
            for item in items where !item.isFile {
                guard let entry = entries[item.id], entry.nameable, holders[entry.key] == 1,
                      established[entry.key].map({ $0 == item.id }) ?? true,
                      let score = PaletteMatch.score(folded: entry.folded, query) else { continue }
                Self.keep((entry.title, score, entry.modified), in: &best, limit: limit)
            }
            return best.map(\.title)
        }

        private func forget(_ key: String) {
            guard let count = holders[key] else { return }
            if count <= 1 { holders[key] = nil } else { holders[key] = count - 1 }
        }

        /// Whether `a` is offered before `b`: a closer match, then a more recent edit, then the title.
        private static func precedes(_ a: (title: String, score: Int, modified: Date), _ b: (title: String, score: Int, modified: Date)) -> Bool {
            if a.score != b.score { return a.score < b.score }
            if a.modified != b.modified { return a.modified > b.modified }
            return a.title < b.title
        }

        /// Keeps the `limit` best without ordering the notes that did not make it.
        private static func keep(_ match: (title: String, score: Int, modified: Date), in best: inout [(title: String, score: Int, modified: Date)], limit: Int) {
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

    func noteNames(matching query: String, in source: ItemID? = nil, using index: NoteLinks.Index, limit: Int = 12) async -> [String] {
        let established = source.flatMap { item($0)?.establishedLinks } ?? [:]
        return await index.names(matching: query, among: items(in: .allNotes), established: established, limit: limit)
    }
}
