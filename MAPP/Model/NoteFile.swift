import Foundation

/// A note's file split the way Marfa's folders read one: YAML front matter holds the note's properties and the
/// rest is the body. What the page cannot show, the front matter, a byte-order mark and Windows line endings, is
/// held here and put back as it was, so the page only ever sees the body.
nonisolated struct NoteFile: Hashable, Sendable {
    var hasByteOrderMark: Bool
    /// Windows line endings throughout; a mixture is read, and written back, as it stands.
    var usesCRLF: Bool
    /// The front matter as written, fences included; uniformly Windows line endings are held as `\n`.
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

    private var rawLines: [Substring] {
        var result: [Substring] = []
        var start = frontMatter.startIndex
        while start < frontMatter.endIndex {
            let end = frontMatter.utf8[start...].firstIndex(of: UInt8(ascii: "\n"))
                .map { frontMatter.utf8.index(after: $0) } ?? frontMatter.endIndex
            result.append(frontMatter[start..<end])
            start = end
        }
        return result
    }

    private var lines: [Substring] {
        Array(rawLines.dropFirst().dropLast())
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

    private mutating func setProperty(_ key: String, yaml value: String?) {
        guard !frontMatter.isEmpty else {
            if let value { frontMatter = "---\n\(key): \(value)\n---\n" }
            return
        }
        let raw = rawLines
        var lines = lines
        let range = Self.range(of: key, in: lines)
        let endingSource = range.map { lines[$0.lowerBound] } ?? raw.last!
        let ending = endingSource.hasSuffix("\r\n") ? "\r\n" : "\n"
        let line = value.map { Substring("\(key): \($0)\(ending)") }
        if let range {
            lines.replaceSubrange(range, with: line.map { [$0] } ?? [])
        } else if let line {
            lines.append(line)
        } else {
            return
        }
        store(lines, around: raw, removing: value == nil)
    }

    /// Puts edited property lines back between the fences, taking the front matter away when nothing is left.
    private mutating func store(_ lines: [Substring], around raw: [Substring], removing: Bool) {
        var lines = lines
        // Marfa treats an empty line immediately after the opening fence as a thematic break, not metadata.
        if removing { lines = Array(lines.drop(while: { $0.trimmingCharacters(in: .newlines).isEmpty })) }
        let hasContent = lines.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        frontMatter = hasContent ? String(raw.first!) + lines.joined() + String(raw.last!) : ""
    }

    /// The lines of one top-level property: its own line and what belongs to it, an indented value or a block
    /// list written at the key's own indent. Blank lines within a value belong to it; a separator after it
    /// belongs to the file.
    private static func range(of key: String, in lines: [Substring]) -> Range<Int>? {
        guard let start = lines.firstIndex(where: { value(in: $0, for: key) != nil }) else { return nil }
        var end = start + 1
        var scan = end
        while scan < lines.count {
            if lines[scan].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scan += 1
                continue
            }
            guard lines[scan].first == " " || lines[scan].first == "\t" || isSequenceEntry(lines[scan]) else { break }
            scan += 1
            end = scan
        }
        return start..<end
    }

    private static func isSequenceEntry(_ line: Substring) -> Bool {
        guard line.hasPrefix("-") else { return false }
        return line.dropFirst().first.map { $0 == " " || $0 == "\t" || $0.isNewline } ?? true
    }

    /// Restores one field's original spelling without replacing a subsequently edited body or other fields.
    mutating func restoreField(_ key: String, from original: NoteFile) {
        let originalLines = original.lines
        let source = Self.range(of: key, in: originalLines).map { Array(originalLines[$0]) } ?? []
        if source.isEmpty { setField(key, nil); return }
        if frontMatter.isEmpty { frontMatter = "---\n" + source.joined() + "---\n"; return }
        let raw = rawLines
        var current = lines
        if let target = Self.range(of: key, in: current) { current.replaceSubrange(target, with: source) }
        else { current.append(contentsOf: source) }
        frontMatter = String(raw.first!) + current.joined() + String(raw.last!)
    }

    /// Encodes only the changed field; the remaining envelope keeps its original spelling.
    mutating func setField(_ key: String, _ value: NoteFieldValue?) {
        setProperty(key, yaml: value.map(Self.fieldYAML))
    }

    private static func fieldYAML(_ value: NoteFieldValue) -> String {
        switch value {
        case .null: "null"
        case .bool(let flag): flag ? "true" : "false"
        case .number(let number): NSDecimalNumber(decimal: number).stringValue
        case .string(let text): yaml(text)
        case .array(let values): "[" + values.map(fieldYAML).joined(separator: ", ") + "]"
        case .object(let values): "{" + values.keys.sorted().map { yaml($0) + ": " + fieldYAML(values[$0]!) }.joined(separator: ", ") + "}"
        }
    }

    // MARK: Tags

    /// Marfa's ordinary tag for an item the person keeps close.
    static let favoriteTag = "favorite"

    /// The tags Marfa's folder reads from the `tags` front matter line, which it takes only as a YAML list, in
    /// flow or block form. Empty when the line is absent or is anything else.
    var tags: [String] { tagList()?.tags ?? [] }

    var isFavorite: Bool { tags.contains(Self.favoriteTag) }

    /// Adds or removes the `favorite` tag, changing nothing else. A tag is added in the form of the list already
    /// there, or as a flow list when there is none; the last tag removed takes the whole line with it. A `tags`
    /// value that is not a list is left as written.
    mutating func setFavorite(_ isOn: Bool) {
        let all = lines
        guard Self.range(of: "tags", in: all) != nil else {
            if isOn { setProperty("tags", yaml: "[\(Self.favoriteTag)]") }
            return
        }
        guard let list = tagList() else { return }
        var edited = all
        let raw = rawLines
        if isOn {
            guard !list.tags.contains(Self.favoriteTag) else { return }
            switch list.layout {
            case .flow(let text, let items, let close, let hasTrailingComma):
                let afterSpace = text[..<close].last?.isWhitespace == true
                let insertion = items.isEmpty || (hasTrailingComma && afterSpace) ? Self.favoriteTag
                    : hasTrailingComma ? " \(Self.favoriteTag)" : ", \(Self.favoriteTag)"
                var changed = text
                changed.insert(contentsOf: insertion, at: close)
                edited.replaceSubrange(list.range, with: [Substring(changed)])
            case .block(let entries):
                let last = list.range.lowerBound + entries.last!
                let indent = edited[last].prefix { $0 == " " || $0 == "\t" }
                let gap = edited[last].dropFirst(indent.count + 1).prefix { $0 == " " || $0 == "\t" }
                let marker = String(indent) + "-" + (gap.isEmpty ? " " : String(gap))
                let ending = edited[last].hasSuffix("\r\n") ? "\r\n" : "\n"
                edited.insert(Substring("\(marker)\(Self.favoriteTag)\(ending)"), at: last + 1)
            }
            store(edited, around: raw, removing: false)
        } else {
            var list = list
            while let position = list.tags.firstIndex(of: Self.favoriteTag) {
                if list.tags.count == 1 {
                    edited.removeSubrange(list.range)
                } else {
                    switch list.layout {
                    case .flow(let text, let items, _, _):
                        let removal = position < items.count - 1
                            ? items[position].lowerBound..<items[position + 1].lowerBound
                            : items[position - 1].upperBound..<items[position].upperBound
                        var changed = text
                        changed.removeSubrange(removal)
                        edited.replaceSubrange(list.range, with: [Substring(changed)])
                    case .block(let entries):
                        edited.remove(at: list.range.lowerBound + entries[position])
                    }
                }
                store(edited, around: raw, removing: true)
                guard let next = tagList() else { return }
                list = next
                edited = lines
            }
        }
    }

    private struct TagList {
        enum Layout {
            /// The joined lines of the list, each item's range within them, where the list closes, and whether
            /// the last item is followed by a comma.
            case flow(text: String, items: [Range<String.Index>], close: String.Index, hasTrailingComma: Bool)
            /// The offset within the list's lines of each item's line.
            case block(entries: [Int])
        }

        let range: Range<Int>
        let layout: Layout
        let tags: [String]
    }

    private func tagList() -> TagList? {
        let all = lines
        guard let range = Self.range(of: "tags", in: all), let value = Self.value(in: all[range.lowerBound], for: "tags") else { return nil }
        let block = Array(all[range])
        let head = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.isEmpty || head.hasPrefix("#") {
            var entries: [Int] = []
            var tags: [String] = []
            for (offset, line) in block.enumerated().dropFirst() {
                let content = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if content.isEmpty || content.hasPrefix("#") { continue }
                guard Self.isSequenceEntry(Substring(content)), let tag = Self.scalar(content.dropFirst()) else { return nil }
                entries.append(offset)
                tags.append(tag)
            }
            return entries.isEmpty ? nil : TagList(range: range, layout: .block(entries: entries), tags: tags)
        }
        guard head.hasPrefix("[") else { return nil }
        let text = block.joined()
        var index = text.index(after: text.firstIndex(of: "[")!)
        var items: [Range<String.Index>] = []
        var start: String.Index?
        var end = index
        var quote: Character?
        var escaped = false
        var close: String.Index?
        var hasTrailingComma = false
        while index < text.endIndex {
            let character = text[index]
            if let open = quote {
                if escaped { escaped = false }
                else if open == "\"" && character == "\\" { escaped = true }
                else if character == open { quote = nil }
                end = text.index(after: index)
            } else if character == "]" {
                close = index
                break
            } else if character == "," {
                guard let first = start else { return nil }
                items.append(first..<end)
                start = nil
                hasTrailingComma = true
            } else if character == "[" || character == "{" {
                return nil
            } else if !character.isWhitespace {
                if start == nil {
                    start = index
                    if character == "\"" || character == "'" { quote = character }
                }
                hasTrailingComma = false
                end = text.index(after: index)
            }
            index = text.index(after: index)
        }
        guard let close, quote == nil else { return nil }
        if let first = start { items.append(first..<end) }
        let rest = text[text.index(after: close)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard rest.isEmpty || rest.hasPrefix("#") else { return nil }
        let tags = items.compactMap { Self.scalar(text[$0]) }
        guard tags.count == items.count else { return nil }
        return TagList(range: range, layout: .flow(text: text, items: items, close: close, hasTrailingComma: hasTrailingComma), tags: tags)
    }

    /// The note's own title, which Marfa keeps in the front matter.
    var title: String? {
        property("title").flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
    }

    private static func value(in line: Substring, for key: String) -> Substring? {
        guard line.hasPrefix(key) else { return nil }
        let rest = line.dropFirst(key.count)
        guard rest.first == ":" else { return nil }
        let value = rest.dropFirst()
        guard value.isEmpty || value.first == " " || value.first == "\t" || value.first?.isNewline == true else { return nil }
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
