import Foundation

/// A `[[link]]` as the page reads it: the name before any `|` or `#`, the heading after `#`, and the alias after
/// `|`, each trimmed. Marfa binds each spelling of a link on its own, so two links to one name can name two notes.
nonisolated struct NoteLink: Hashable, Sendable {
    var name: String
    var heading: String?
    var alias: String?

    init(name: String, heading: String? = nil, alias: String? = nil) {
        self.name = NoteName.trimmed(name)
        let heading = heading.map(NoteName.trimmed).flatMap { $0.isEmpty ? nil : $0 }
        self.heading = heading
        // An alias that only repeats what the link would show is none.
        let shown = heading.map { self.name + "#" + $0 } ?? self.name
        self.alias = alias.map(NoteName.trimmed).flatMap { $0.isEmpty || $0 == shown ? nil : $0 }
    }

    /// The link as Marfa reads the text between the brackets: the name up to the first `|` or `#`, then a heading
    /// after `#` up to a `|`, then an alias.
    init(reading raw: String) {
        let raw = NoteName.trimmed(raw)
        guard let separator = raw.firstIndex(where: { $0 == "|" || $0 == "#" }) else {
            self.init(name: raw)
            return
        }
        let name = String(raw[..<separator])
        let rest = raw[raw.index(after: separator)...]
        if raw[separator] == "|" {
            self.init(name: name, alias: String(rest))
        } else if let bar = rest.firstIndex(of: "|") {
            self.init(name: name, heading: String(rest[..<bar]), alias: String(rest[rest.index(after: bar)...]))
        } else {
            self.init(name: name, heading: String(rest))
        }
    }
}

/// A link in an item's text with what the library bound it to.
nonisolated struct BoundLink: Hashable, Sendable {
    let link: NoteLink
    let resolution: NoteReferenceResolution
}
