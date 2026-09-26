import Foundation

/// A note's file split the way Marfa's folders read one: YAML front matter holds the note's properties and the
/// rest is the body. What the page cannot show, the front matter, a byte-order mark and Windows line endings, is
/// held here and put back as it was, so the page only ever sees the body.
nonisolated struct NoteFile: Hashable, Sendable {
    var hasByteOrderMark: Bool
    /// Windows line endings throughout; a mixture is read, and written back, as it stands.
    var usesCRLF: Bool
    /// The front matter as written, fences included and line endings as `\n`, or empty when there is none.
    private(set) var frontMatter: String
    var body: String

    init(text: String) {
        var text = text
        hasByteOrderMark = text.hasPrefix("\u{FEFF}")
        if hasByteOrderMark { text.removeFirst() }
        usesCRLF = text.contains("\r\n") && text.firstMatch(of: /(^|[^\r])\n/) == nil
        if usesCRLF { text = text.replacing("\r\n", with: "\n") }
        let length = Self.frontMatterLength(of: text)
        frontMatter = String(text.prefix(length))
        body = String(text.dropFirst(length))
    }

    /// The file's text: the byte-order mark, front matter and line endings put back around the body.
    var text: String {
        var text = frontMatter + body
        if usesCRLF { text = text.replacing("\n", with: "\r\n") }
        return (hasByteOrderMark ? "\u{FEFF}" : "") + text
    }

    /// How many characters of the text are front matter, by Marfa's rule: a first line of exactly `---`, not
    /// followed by a blank line, closed by a later line of exactly `---`. A blank line after the opening fence
    /// makes it a thematic break, and a fence never closed makes the whole text body.
    static func frontMatterLength(of text: String) -> Int {
        guard text.hasPrefix("---\n") else { return 0 }
        var lines = text.dropFirst(4).split(separator: "\n", omittingEmptySubsequences: false)[...]
        guard let first = lines.first, !first.isEmpty, first != "\r" else { return 0 }
        var length = 4
        while let line = lines.popFirst() {
            let isLast = lines.isEmpty
            length += line.count + (isLast ? 0 : 1)
            if line == "---" || line == "---\r" { return length }
        }
        return 0
    }

    // MARK: Properties

    private var lines: [Substring] {
        guard !frontMatter.isEmpty else { return [] }
        var inner = frontMatter.dropFirst(4)
        if inner.hasSuffix("\n") { inner = inner.dropLast() }
        return Array(inner.split(separator: "\n", omittingEmptySubsequences: false).dropLast())
    }

    /// A top-level property's value when it is a single scalar, unquoted; nil when absent or not a scalar.
    func property(_ key: String) -> String? {
        for line in lines {
            guard let value = Self.value(in: line, for: key) else { continue }
            return Self.scalar(value)
        }
        return nil
    }

    /// Sets a top-level property to a scalar, or removes it with nil, changing only its own lines. A property
    /// added goes last; front matter is made when there is none, and taken away when the last property goes.
    mutating func setProperty(_ key: String, _ value: String?) {
        var lines = lines
        let index = lines.firstIndex { Self.value(in: $0, for: key) != nil }
        let line = value.map { Substring("\(key): \(Self.yaml($0))") }
        if let index {
            // A value written over several lines continues on the lines indented under the key.
            var end = index + 1
            while end < lines.count, lines[end].first == " " || lines[end].first == "\t" || lines[end].isEmpty {
                end += 1
            }
            lines.replaceSubrange(index..<end, with: line.map { [$0] } ?? [])
        } else if let line {
            lines.append(line)
        } else {
            return
        }
        frontMatter = lines.isEmpty ? "" : "---\n" + lines.joined(separator: "\n") + "\n---\n"
    }

    var isPinned: Bool { property("pinned") == "true" }

    /// The note's own title, which Marfa keeps in the front matter.
    var title: String? {
        property("title").flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
    }

    private static func value(in line: Substring, for key: String) -> Substring? {
        guard line.hasPrefix(key) else { return nil }
        let rest = line.dropFirst(key.count)
        guard rest.first == ":" else { return nil }
        let value = rest.dropFirst()
        guard value.isEmpty || value.first == " " || value.first == "\t" else { return nil }
        return value
    }

    /// A YAML scalar as its text: quotes removed, a trailing comment dropped from a plain one.
    private static func scalar(_ raw: Substring) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            var result = ""
            var escaped = false
            for character in value.dropFirst().dropLast() {
                if escaped {
                    result.append(character == "n" ? "\n" : character == "t" ? "\t" : character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else {
                    result.append(character)
                }
            }
            return result
        }
        if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
            return String(value.dropFirst().dropLast()).replacing("''", with: "'")
        }
        if value.isEmpty || value.hasPrefix("|") || value.hasPrefix(">") || value.hasPrefix("[") || value.hasPrefix("{") {
            return nil
        }
        if let comment = value.range(of: " #") { return String(value[..<comment.lowerBound]) }
        return value
    }

    /// A string as a YAML scalar: plain where YAML reads it back unchanged, double-quoted otherwise.
    private static func yaml(_ value: String) -> String {
        let special = CharacterSet(charactersIn: "-?:,[]{}#&*!|>'\"%@`")
        let plain = !value.isEmpty
            && value.trimmingCharacters(in: .whitespaces) == value
            && value.unicodeScalars.first.map { !special.contains($0) } ?? false
            && !value.contains(": ") && !value.contains(" #") && !value.contains("\n")
            && !["true", "false", "yes", "no", "null", "~", "on", "off"].contains(value.lowercased())
            && Double(value) == nil
        if plain { return value }
        let escaped = value
            .replacing("\\", with: "\\\\")
            .replacing("\"", with: "\\\"")
            .replacing("\n", with: "\\n")
            .replacing("\t", with: "\\t")
        return "\"\(escaped)\""
    }
}
