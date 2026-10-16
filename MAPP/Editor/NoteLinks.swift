import Foundation

/// How the page names a note in a `[[link]]`: by its title, as the library's own links already resolve it.
nonisolated enum NoteLinks {
    /// Whether `[[title]]` names the title as written. A link ends at `]]`, reads `|` as an alias and `#` as a
    /// heading, and the page reads `\` as an escape, so a title holding one is left out rather than linked to
    /// something else.
    static func canName(_ title: String) -> Bool {
        !title.isEmpty && title == NoteName.trimmed(title)
            && !title.unicodeScalars.contains { "[]|#\\\r\n".unicodeScalars.contains($0) }
    }

    static func link(to title: String) -> String { "[[\(title)]]" }

    /// Keeps each note's title folded for matching, so a query that grows one letter at a time folds nothing again
    /// and a library of tens of thousands of notes is read in one pass. It works off the main actor, on a copy of
    /// the items, so typing in the page and the window never wait on it.
    actor Index {
        private struct Entry {
            let version: ItemVersion
            let title: String
            let folded: [UInt32]
            let nameable: Bool
            let modified: Date
        }

        private var entries: [ItemID: Entry] = [:]

        /// The titles that answer what was typed after `[[`, best first (the closest match, then the most recently
        /// edited), each once.
        func names(matching text: String, among items: [Item], limit: Int) -> [String] {
            let query = PaletteMatch.Query(text)
            var notes = 0
            var best: [(title: String, score: Int, modified: Date)] = []
            for item in items where !item.isFile {
                notes += 1
                let entry: Entry
                if let kept = entries[item.id], kept.version == item.version, kept.title == item.title {
                    entry = kept
                } else {
                    entry = Entry(
                        version: item.version, title: item.title, folded: PaletteMatch.folded(item.title),
                        nameable: NoteLinks.canName(item.title), modified: item.modified)
                    entries[item.id] = entry
                }
                guard entry.nameable, let score = PaletteMatch.score(folded: entry.folded, query) else { continue }
                Self.keep((entry.title, score, entry.modified), in: &best, limit: limit)
            }
            if entries.count != notes {
                let live = Set(items.lazy.filter { !$0.isFile }.map(\.id))
                entries = entries.filter { live.contains($0.key) }
            }
            return best.map(\.title)
        }

        /// Whether `a` is offered before `b`: a closer match, then a more recent edit, then the title.
        private static func precedes(_ a: (title: String, score: Int, modified: Date), _ b: (title: String, score: Int, modified: Date)) -> Bool {
            if a.score != b.score { return a.score < b.score }
            if a.modified != b.modified { return a.modified > b.modified }
            return a.title < b.title
        }

        /// Keeps the `limit` best, one for each title, without ordering the notes that did not make it.
        private static func keep(_ match: (title: String, score: Int, modified: Date), in best: inout [(title: String, score: Int, modified: Date)], limit: Int) {
            if let same = best.firstIndex(where: { $0.title == match.title }) {
                guard precedes(match, best[same]) else { return }
                best.remove(at: same)
            } else if best.count == limit, let last = best.last, !precedes(match, last) {
                return
            }
            let at = best.firstIndex { precedes(match, $0) } ?? best.endIndex
            best.insert(match, at: at)
            if best.count > limit { best.removeLast() }
        }
    }

    /// The same name as the library's links read it: ignoring case and the form of accents.
    private static func key(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased().precomposedStringWithCanonicalMapping
    }

    /// The note a link's target names, as the library's links resolve it: by title, or by the path or file name
    /// where the library has files. When several answer, the most recently edited.
    static func note(named target: String, among items: [Item], pathOf: (ItemID) -> String?) -> Item? {
        let wanted = key(NoteName.trimmed(target))
        guard !wanted.isEmpty else { return nil }
        func names(of item: Item) -> [String] {
            var names = [NoteName.trimmed(item.title)]
            if let path = pathOf(item.id) {
                let file = (path as NSString).lastPathComponent
                names += [path, (path as NSString).deletingPathExtension, file, (file as NSString).deletingPathExtension]
            }
            return names
        }
        return items.filter { !$0.isFile && names(of: $0).contains { key($0) == wanted } }
            .max { $0.modified < $1.modified }
    }
}

extension ItemLibrary {
    /// The notes a link can name by title, most recently edited first.
    func linkableNotes(excluding id: ItemID? = nil) -> [Item] {
        items(in: .allNotes).filter { !$0.isFile && $0.id != id && NoteLinks.canName($0.title) }
            .sorted { $0.modified > $1.modified }
    }

    func noteNames(matching query: String, using index: NoteLinks.Index, limit: Int = 12) async -> [String] {
        await index.names(matching: query, among: items(in: .allNotes), limit: limit)
    }

    func note(named target: String) -> Item? {
        NoteLinks.note(named: target, among: items(in: .allNotes), pathOf: { path(of: $0) })
    }
}
