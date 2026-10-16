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

    /// The titles that answer what was typed after `[[`, best first, each once. The work runs off the main actor
    /// on a copy of the items, so typing in the page and the window never wait on a large library.
    @concurrent static func names(matching query: String, among items: [Item], limit: Int) async -> [String] {
        var matches: [(title: String, score: Int, modified: Date)] = []
        var seen: Set<String> = []
        for item in items where !item.isFile && canName(item.title) && !seen.contains(item.title) {
            guard let score = PaletteMatch.score(item.title, query) else { continue }
            seen.insert(item.title)
            matches.append((item.title, score, item.modified))
        }
        matches.sort { ($0.score, $1.modified, $0.title) < ($1.score, $0.modified, $1.title) }
        return matches.prefix(limit).map(\.title)
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

    func noteNames(matching query: String, limit: Int = 12) async -> [String] {
        await NoteLinks.names(matching: query, among: items(in: .allNotes), limit: limit)
    }

    func note(named target: String) -> Item? {
        NoteLinks.note(named: target, among: items(in: .allNotes), pathOf: { path(of: $0) })
    }
}
