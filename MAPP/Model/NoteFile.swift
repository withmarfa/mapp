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
        let end = text.utf8.index(text.utf8.startIndex, offsetBy: Self.frontMatterLength(of: text))
        frontMatter = String(text[..<end])
        body = String(text[end...])
    }

    /// The file's text: the byte-order mark, front matter and line endings put back around the body.
    var text: String {
        // Front matter closed at the very end of a file has no line break after it, and a body needs one.
        let separator = !frontMatter.isEmpty && frontMatter.utf8.last != UInt8(ascii: "\n") && !body.isEmpty ? "\n" : ""
        var text = frontMatter + separator + body
        if usesCRLF { text = text.replacing("\n", with: "\r\n") }
        return (hasByteOrderMark ? "\u{FEFF}" : "") + text
    }

    /// How many bytes of the text are front matter, by Marfa's rule: a first line of exactly `---`, not
    /// followed by a blank line, closed by a later line of exactly `---`. A blank line after the opening fence
    /// makes it a thematic break, and a fence never closed makes the whole text body. Lines may end either way.
    static func frontMatterLength(of text: String) -> Int {
        let bytes = Array(text.utf8)
        let newline = UInt8(ascii: "\n")
        let fence = Array("---".utf8)
        /// The line from `start`, without its line ending, and where the next line starts.
        func line(at start: Int) -> (content: ArraySlice<UInt8>, next: Int?) {
            let end = bytes[start...].firstIndex(of: newline) ?? bytes.endIndex
            var content = bytes[start..<end]
            if content.last == UInt8(ascii: "\r") { content = content.dropLast() }
            return (content, end < bytes.endIndex ? end + 1 : nil)
        }
        let opening = line(at: 0)
        guard opening.content.elementsEqual(fence), var start = opening.next, start < bytes.endIndex,
              !line(at: start).content.isEmpty
        else { return 0 }
        while true {
            let current = line(at: start)
            if current.content.elementsEqual(fence) { return current.next ?? bytes.endIndex }
            guard let next = current.next, next < bytes.endIndex else { return 0 }
            start = next
        }
    }

    // MARK: Properties

    private var lines: [Substring] {
        guard !frontMatter.isEmpty else { return [] }
        let lines = frontMatter.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        // The fences, and the empty remainder after a closing line break, are not properties.
        let end = lines.last == "" ? lines.count - 2 : lines.count - 1
        return end > 1 ? Array(lines[1..<end]) : []
    }

    /// A top-level property's value when it is a single scalar, unquoted; nil when absent or not a scalar.
    func property(_ key: String) -> String? {
        for line in lines {
            guard let value = Self.value(in: line, for: key) else { continue }
            return Self.scalar(value)
        }
        return nil
    }

    /// Sets a top-level property to a string, or removes it with nil, changing only its own lines. A property
    /// added goes last; front matter is made when there is none, and taken away when the last property goes.
    mutating func setProperty(_ key: String, _ value: String?) {
        setProperty(key, yaml: value.map(Self.yaml))
    }

    /// Sets a top-level property to true, or removes it, as a flag is written in YAML.
    mutating func setFlag(_ key: String, _ isOn: Bool) {
        setProperty(key, yaml: isOn ? "true" : nil)
    }

    private mutating func setProperty(_ key: String, yaml value: String?) {
        var lines = lines
        let index = lines.firstIndex { Self.value(in: $0, for: key) != nil }
        let line = value.map { Substring("\(key): \($0)") }
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

    var isPinned: Bool { property("pinned")?.lowercased() == "true" }

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
            && !value.contains(": ") && !value.hasSuffix(":") && !value.contains(" #")
            && !value.unicodeScalars.contains { $0.properties.generalCategory == .control }
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
