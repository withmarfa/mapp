import Foundation

/// A `[[link]]` as the page reads it: the name before any `|` or `#`, the heading after `#`, and the alias after `|`,
/// with the backslash escapes of `[`, `]`, `|`, `#` and `\` taken out, as InkKit reads a link and as the page posts it.
///
/// Marfa binds each spelling of a link on its own, so two links to one name can name two notes, and it tells spellings
/// apart by their text, spaces inside the brackets included. So the parts keep the spaces between the brackets and only
/// the text as a whole is trimmed, as Marfa trims it. Two spellings InkKit does not tell apart in what it hands the page
/// stay one link here: `[[Plan]]` and `[[Plan|Plan]]` (an alias that repeats the link is none).
nonisolated struct NoteLink: Hashable, Sendable {
    var name: String
    var heading: String?
    var alias: String?

    init(name: String, heading: String? = nil, alias: String? = nil) {
        let heading = heading.flatMap { NoteName.trimmed($0).isEmpty ? nil : $0 }
        let alias = alias.flatMap { NoteName.trimmed($0).isEmpty ? nil : $0 }
        // An alias that only repeats what the link would show is none.
        let shown = heading.map { name + "#" + $0 } ?? name
        let kept = alias == shown ? nil : alias
        var parts = [name, heading, kept]
        parts[0] = Self.withoutLeadingSpace(name)
        let last = parts.lastIndex { $0 != nil } ?? 0
        parts[last] = parts[last].map(Self.withoutTrailingSpace)
        self.name = parts[0] ?? ""
        self.heading = parts[1]
        self.alias = parts[2]
    }

    /// The name a library looks a link up by, whatever spaces the text puts around it.
    var lookupName: String { NoteName.trimmed(name) }

    /// The link as Marfa reads the text between the brackets: the name up to the first `|` or `#`, then a heading
    /// after `#` up to a `|`, then an alias; each with its escapes taken out.
    init(reading raw: String) {
        let raw = NoteName.trimmed(raw)
        guard let separator = raw.firstIndex(where: { $0 == "|" || $0 == "#" }) else {
            self.init(name: Self.unescaped(raw))
            return
        }
        let name = Self.unescaped(String(raw[..<separator]))
        let rest = raw[raw.index(after: separator)...]
        if raw[separator] == "|" {
            self.init(name: name, alias: Self.unescaped(String(rest)))
        } else if let bar = rest.firstIndex(of: "|") {
            self.init(
                name: name, heading: Self.unescaped(String(rest[..<bar])),
                alias: Self.unescaped(String(rest[rest.index(after: bar)...])))
        } else {
            self.init(name: name, heading: Self.unescaped(String(rest)))
        }
    }

    /// A backslash before `[`, `]`, `|`, `#` or `\` stands for that character, as InkKit reads it.
    static func unescaped(_ text: String) -> String {
        var result = ""
        var characters = text.makeIterator()
        while let character = characters.next() {
            guard character == "\\" else {
                result.append(character)
                continue
            }
            guard let next = characters.next() else {
                result.append(character)
                break
            }
            if "[]|#\\".contains(next) { result.append(next) } else { result.append(character); result.append(next) }
        }
        return result
    }

    private static func withoutLeadingSpace(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { !$0.properties.isWhitespace }) else { return "" }
        return String(String.UnicodeScalarView(scalars[first...]))
    }

    private static func withoutTrailingSpace(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let last = scalars.lastIndex(where: { !$0.properties.isWhitespace }) else { return "" }
        return String(String.UnicodeScalarView(scalars[...last]))
    }
}

/// A link in an item's text with what the library bound it to.
nonisolated struct BoundLink: Hashable, Sendable {
    let link: NoteLink
    let resolution: NoteReferenceResolution
}

/// Marfa trims Unicode White_Space, which excludes format characters such as U+200B.
nonisolated enum NoteName {
    static func trimmed(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { !$0.properties.isWhitespace }),
              let last = scalars.lastIndex(where: { !$0.properties.isWhitespace }) else { return "" }
        return String(String.UnicodeScalarView(scalars[first...last]))
    }
}

nonisolated enum NoteReferenceResolution: Hashable, Sendable {
    case resolved(ItemID)
    case missing
    case ambiguous([ItemID])
    /// Not looked up on the server yet.
    case pending
    /// The server refused the lookup or the write of the edge.
    case refused(String)
}
