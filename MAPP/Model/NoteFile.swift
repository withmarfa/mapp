import Foundation
import Yams

/// A note's file split the way Marfa's folders read one: YAML front matter holds the note's properties and the
/// rest is the body. What the page cannot show, the front matter, a byte-order mark and Windows line endings, is
/// held here and put back as it was, so the page only ever sees the body.
nonisolated struct NoteFile: Hashable, Sendable {
    var hasByteOrderMark: Bool
    /// Windows line endings throughout; a mixture is read, and written back, as it stands.
    var usesCRLF: Bool
    /// The front matter as written, fences included; uniformly Windows line endings are held as `\n`.
    private(set) var frontMatter: String { didSet { tags = Self.marfaTags(in: frontMatter) } }
    var body: String
    /// The tags Marfa's folder reads from the front matter; nil where it would refuse them.
    private(set) var tags: [String]?

    init(text: String) {
        var text = text
        hasByteOrderMark = text.hasPrefix("\u{FEFF}")
        if hasByteOrderMark { text.removeFirst() }
        usesCRLF = text.contains("\r\n") && text.firstMatch(of: /(^|[^\r])\n/) == nil
        if usesCRLF { text = text.replacing("\r\n", with: "\n") }
        let end = text.utf8.index(text.utf8.startIndex, offsetBy: Self.frontMatterLength(of: text))
        frontMatter = String(text[..<end])
        body = String(text[end...])
        tags = Self.marfaTags(in: frontMatter)
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
        // A key spelled another way, quoted or with space before its colon, keeps its spelling.
        var spelling = Substring("\(key):")
        if let range, let existing = Self.value(in: lines[range.lowerBound], for: key) {
            spelling = lines[range.lowerBound][..<existing.startIndex]
        }
        let line = value.map { Substring("\(spelling) \($0)\(ending)") }
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

    /// Why the favorite tag was left as it was.
    enum TagEditError: Error, Equatable {
        /// Marfa would not read the front matter, or reads its `tags` value as something other than tags.
        case unreadable
        /// No edit of the `tags` lines alone gives exactly the intended tags with every other field unchanged.
        case unsafe
    }

    var isFavorite: Bool { tags?.contains(Self.favoriteTag) == true }

    /// Adds or removes the `favorite` tag in the form the `tags` value already has: an item in a flow or block
    /// list, or a comma-separated item in a string. An empty value becomes `[favorite]`, a note without the field
    /// gains `tags: [favorite]`, and removing the last tag takes the field away. The result is read again before it
    /// is kept, and an edit that would change anything else is refused.
    mutating func setFavorite(_ isOn: Bool) throws(TagEditError) {
        guard let current = tags, let others = Self.fieldsOtherThanTags(in: frontMatter) else { throw .unreadable }
        guard current.contains(Self.favoriteTag) != isOn else { return }
        let intended = Set(current).symmetricDifference([Self.favoriteTag])
        var edited = self
        guard edited.editTags(adding: isOn), let tags = edited.tags, Set(tags) == intended,
              Self.fieldsOtherThanTags(in: edited.frontMatter) == others
        else { throw .unsafe }
        self = edited
    }

    /// Puts back the front matter `original` had, keeping this file's body.
    mutating func restoreFrontMatter(from original: NoteFile) {
        frontMatter = original.frontMatter
    }

    /// The front matter's YAML, between its fences, as Yams composes it; nil when there is none.
    static func composed(_ frontMatter: String) throws -> Node? {
        guard !frontMatter.isEmpty else { return nil }
        var lines = frontMatter.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        lines.removeFirst()
        lines.removeLast()
        return try Yams.compose(yaml: lines.joined(separator: "\n"))
    }

    /// The tags as Marfa's folder reads them (`tags_of` in its folder fields): a list of tags, tags separated by
    /// commas, or nothing, each trimmed, none empty, a repeat dropped. Nil where Marfa would refuse the value, or
    /// the front matter that holds it.
    private static func marfaTags(in frontMatter: String) -> [String]? {
        // Most notes have no tags, so they skip the parse; only a key spelled with escapes, such as `"t\x61gs"`, is missed.
        guard frontMatter.contains("tags") else { return [] }
        let root: Node?
        do { root = try composed(frontMatter) } catch { return nil }
        guard let root else { return [] }
        // Marfa reads front matter that is not a mapping as Markdown, which has no tags.
        guard case .mapping(let mapping) = root else { return [] }
        guard marfaCarries(root, source: frontMatter.components(separatedBy: "\n")) else { return nil }
        guard let value = mapping.first(where: { isTagsKey($0.key) })?.value else { return [] }
        let named: [String]
        switch value {
        case .scalar(let scalar):
            switch marfaScalar(scalar) {
            case .null: return []
            case .string(let text):
                named = text.unicodeScalars.split(separator: ",", omittingEmptySubsequences: false)
                    .map { String(String.UnicodeScalarView($0)) }
            case .other: return nil
            }
        case .sequence(let sequence):
            var items: [String] = []
            for item in sequence {
                guard case .scalar(let scalar) = item, case .string(let text) = marfaScalar(scalar) else { return nil }
                items.append(text)
            }
            named = items
        case .mapping, .alias:
            return nil
        }
        var tags: [String] = []
        for name in named {
            let tag = NoteName.trimmed(name)
            guard !tag.isEmpty else { return nil }
            if !tags.contains(tag) { tags.append(tag) }
        }
        return tags
    }

    private enum MarfaScalar: Equatable {
        case null
        case string(String)
        case other
    }

    /// A scalar typed as Marfa's YAML reader, yaml-rust2, types it. A quoted or block scalar is text; a plain one
    /// is typed by its explicit tag, or else is null, a boolean or a number by YAML 1.2's core schema and otherwise
    /// text. A float Rust reads as infinite or not a number reaches Marfa as its text.
    private static func marfaScalar(_ scalar: Node.Scalar) -> MarfaScalar {
        let text = scalar.string
        guard scalar.style == .plain else { return .string(text) }
        // Read before anything compares the node, since Yams resolves an implicit tag in place when it does.
        let explicit = Tag.Name(rawValue: scalar.tag.rawValue)
        if explicit != .implicit {
            switch explicit {
            case .null: return text == "~" || text == "null" ? .null : .other
            case .bool, .int, .float: return .other
            default: return .string(text)
            }
        }
        if text.hasPrefix("0x") {
            if Int64(text.dropFirst(2), radix: 16) != nil { return .other }
        } else if text.hasPrefix("0o") {
            if Int64(text.dropFirst(2), radix: 8) != nil { return .other }
        } else if text.hasPrefix("+"), Int64(text.dropFirst()) != nil {
            return .other
        }
        switch text {
        case "", "~", "null": return .null
        case "true", "True", "TRUE", "false", "False", "FALSE": return .other
        default: break
        }
        if Int64(text) != nil { return .other }
        if text.wholeMatch(of: /[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?/) != nil,
           Double(text)?.isFinite == true {
            return .other
        }
        return .string(text)
    }

    /// Whether Marfa can carry the value as an item's front matter: every key is text, none repeats or merges, and
    /// no plain scalar in a flow collection starts at or before the column of the block holding it, which yaml-rust2
    /// refuses as invalid indentation where Yams reads on.
    private static func marfaCarries(_ node: Node, source: [String], blockColumn: Int = 1, inFlow: Bool = false) -> Bool {
        /// Yams takes a collection's style from the event that ends it, so the source tells flow from block.
        func opensFlow(_ mark: Yams.Mark?) -> Bool {
            guard let mark, mark.line < source.count else { return false }
            let line = Array(source[mark.line].unicodeScalars)
            return mark.column - 1 < line.count && (line[mark.column - 1] == "[" || line[mark.column - 1] == "{")
        }
        switch node {
        case .mapping(let mapping):
            let flow = inFlow || opensFlow(mapping.mark)
            let column = flow ? blockColumn : mapping.mark?.column ?? blockColumn
            var keys: Set<String> = []
            for (key, value) in mapping {
                guard case .scalar(let scalar) = key, case .string(let name) = marfaScalar(scalar), name != "<<",
                      keys.insert(name).inserted,
                      marfaCarries(key, source: source, blockColumn: column, inFlow: flow),
                      marfaCarries(value, source: source, blockColumn: column, inFlow: flow)
                else { return false }
            }
            return true
        case .sequence(let sequence):
            let flow = inFlow || opensFlow(sequence.mark)
            let column = flow ? blockColumn : sequence.mark?.column ?? blockColumn
            return sequence.allSatisfy { marfaCarries($0, source: source, blockColumn: column, inFlow: flow) }
        case .scalar(let scalar):
            guard inFlow, scalar.style == .plain, !scalar.string.isEmpty, let mark = scalar.mark else { return true }
            return mark.column > blockColumn
        case .alias:
            return true
        }
    }

    private static func isTagsKey(_ key: Node) -> Bool {
        guard case .scalar(let scalar) = key else { return false }
        return marfaScalar(scalar) == .string("tags")
    }

    /// Every top-level field but `tags`, in order, to show that a tag edit changed nothing else.
    private static func fieldsOtherThanTags(in frontMatter: String) -> [Node]? {
        let root: Node?
        do { root = try composed(frontMatter) } catch { return nil }
        guard let root else { return [] }
        guard case .mapping(let mapping) = root else { return [root] }
        return mapping.filter { !isTagsKey($0.key) }.flatMap { [$0.key, $0.value] }
    }

    /// Edits the `tags` lines in place, found by where Yams read the field. False where the value has a form
    /// with no known edit.
    private mutating func editTags(adding: Bool) -> Bool {
        let all = lines
        let raw = rawLines
        let root: Node?
        do { root = try Self.composed(frontMatter) } catch { return false }
        let pairs: [(key: Node, value: Node)]
        if case .mapping(let mapping)? = root { pairs = Array(mapping) } else { pairs = [] }
        guard let position = pairs.firstIndex(where: { Self.isTagsKey($0.key) }) else {
            guard adding else { return false }
            setProperty("tags", yaml: "[\(Self.favoriteTag)]")
            return true
        }
        guard let keyMark = pairs[position].key.mark, keyMark.line >= 1, keyMark.line <= all.count,
              Self.value(in: all[keyMark.line - 1], for: "tags") != nil
        else { return false }
        let first = keyMark.line - 1
        var end = all.count
        if position + 1 < pairs.count {
            guard let next = pairs[position + 1].key.mark, next.line - 1 > first, next.line - 1 <= all.count else { return false }
            end = next.line - 1
        }
        // Blank lines and comments at the margin before the next field belong to it.
        while end > first + 1, all[end - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || all[end - 1].hasPrefix("#") {
            end -= 1
        }
        var region = TagsRegion(lines: all[first..<end], firstLine: keyMark.line)
        let value = pairs[position].value
        let remaining = (tags ?? []).filter { $0 != Self.favoriteTag }
        var edited: [Substring]
        if !adding && remaining.isEmpty {
            // Comment lines inside the field stay, since YAML allows them anywhere.
            edited = all
            edited.replaceSubrange(first..<end, with: all[first..<end].filter {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("#")
            })
            store(edited, around: raw, removing: true)
            return true
        }
        let changed: Bool = switch value {
        case .sequence(let sequence):
            region.editList(sequence, adding: adding)
        case .scalar(let scalar):
            region.editScalar(scalar, isNull: Self.marfaScalar(scalar) == .null, adding: adding)
        case .mapping, .alias:
            false
        }
        guard changed else { return false }
        edited = all
        edited.replaceSubrange(first..<end, with: region.lines)
        store(edited, around: raw, removing: !adding)
        return true
    }

    /// The `tags` field's lines as one run of Unicode scalars, which is how Yams counts a mark's column.
    private struct TagsRegion {
        private var text: [Unicode.Scalar]
        private let lineStarts: [Int]
        private let firstLine: Int

        init(lines: ArraySlice<Substring>, firstLine: Int) {
            var text: [Unicode.Scalar] = []
            var starts: [Int] = []
            for line in lines {
                starts.append(text.count)
                text.append(contentsOf: line.unicodeScalars)
            }
            self.text = text
            lineStarts = starts
            self.firstLine = firstLine
        }

        var lines: [Substring] {
            let joined = String(String.UnicodeScalarView(text))
            var result: [Substring] = []
            var start = joined.startIndex
            while start < joined.endIndex {
                let end = joined.utf8[start...].firstIndex(of: UInt8(ascii: "\n")).map { joined.utf8.index(after: $0) } ?? joined.endIndex
                result.append(joined[start..<end])
                start = end
            }
            return result
        }

        private func offset(_ mark: Yams.Mark?) -> Int? {
            guard let mark else { return nil }
            let line = mark.line - firstLine
            guard line >= 0, line < lineStarts.count else { return nil }
            let offset = lineStarts[line] + mark.column - 1
            let lineEnd = line + 1 < lineStarts.count ? lineStarts[line + 1] : text.count
            return offset < lineEnd ? offset : nil
        }

        private func line(of offset: Int) -> Int {
            (lineStarts.lastIndex { $0 <= offset }) ?? 0
        }

        private func lineEnd(_ line: Int) -> Int {
            line + 1 < lineStarts.count ? lineStarts[line + 1] : text.count
        }

        private static func isBlank(_ scalar: Unicode.Scalar) -> Bool { scalar == " " || scalar == "\t" }
        private static func isBreak(_ scalar: Unicode.Scalar) -> Bool { scalar == "\n" || scalar == "\r" }

        private func isBlank(_ range: Range<Int>) -> Bool { text[range].allSatisfy(Self.isBlank) }

        /// Where a scalar starting at `start` ends: past its closing quote, or before the comment, separator or
        /// line break that ends a plain one.
        private func scalarEnd(from start: Int, inFlow: Bool) -> Int? {
            guard start < text.count else { return nil }
            var index = start
            switch text[start] {
            case "\"":
                index += 1
                while index < text.count {
                    if text[index] == "\\" { index += 2; continue }
                    if text[index] == "\"" { return index + 1 }
                    index += 1
                }
                return nil
            case "'":
                index += 1
                while index < text.count {
                    if text[index] == "'" {
                        if index + 1 < text.count, text[index + 1] == "'" { index += 2; continue }
                        return index + 1
                    }
                    index += 1
                }
                return nil
            default:
                while index < text.count, !Self.isBreak(text[index]) {
                    if inFlow, ",[]{}".unicodeScalars.contains(text[index]) { break }
                    if text[index] == "#", index > start, Self.isBlank(text[index - 1]) { break }
                    index += 1
                }
                while index > start, Self.isBlank(text[index - 1]) { index -= 1 }
                return index
            }
        }

        /// The first scalar from `start` that is not white space, a line break or a comment.
        private func significant(from start: Int) -> Int {
            var index = start
            while index < text.count {
                if Self.isBlank(text[index]) || Self.isBreak(text[index]) {
                    index += 1
                } else if text[index] == "#" {
                    while index < text.count, !Self.isBreak(text[index]) { index += 1 }
                } else {
                    break
                }
            }
            return index
        }

        private mutating func replace(_ range: Range<Int>, with replacement: String) {
            text.replaceSubrange(range, with: replacement.unicodeScalars)
        }

        /// A list is told flow from block by its source, since Yams takes a sequence's style from the event that
        /// ends it.
        mutating func editList(_ sequence: Node.Sequence, adding: Bool) -> Bool {
            guard let start = offset(sequence.mark) else { return false }
            return text[start] == "[" ? editFlowList(sequence, open: start, adding: adding) : editBlockList(sequence, adding: adding)
        }

        private mutating func editFlowList(_ sequence: Node.Sequence, open: Int, adding: Bool) -> Bool {
            var items: [(range: Range<Int>, isFavorite: Bool)] = []
            for node in sequence {
                guard case .scalar(let scalar) = node, let start = offset(scalar.mark),
                      let end = scalarEnd(from: start, inFlow: true), end > start
                else { return false }
                items.append((start..<end, NoteName.trimmed(scalar.string) == NoteFile.favoriteTag))
            }
            /// The comma after an item, past any comment or line break.
            func comma(after item: Int) -> Int? {
                let index = significant(from: items[item].range.upperBound)
                return index < text.count && text[index] == "," ? index : nil
            }
            if adding {
                guard let last = items.indices.last else {
                    replace(open + 1..<open + 1, with: NoteFile.favoriteTag)
                    return true
                }
                if let trailing = comma(after: last) {
                    let after = trailing + 1
                    if after < text.count, text[after] == " " {
                        replace(after + 1..<after + 1, with: NoteFile.favoriteTag)
                    } else {
                        replace(after..<after, with: " " + NoteFile.favoriteTag)
                    }
                } else {
                    let end = items[last].range.upperBound
                    replace(end..<end, with: ", " + NoteFile.favoriteTag)
                }
                return true
            }
            var remaining = items.count
            for item in items.indices.reversed() where items[item].isFavorite {
                let range = items[item].range
                if item < remaining - 1 {
                    // An item before others goes with the comma after it.
                    guard let separator = comma(after: item) else { return false }
                    if isBlank(range.upperBound..<separator) {
                        var end = separator + 1
                        while end < text.count, Self.isBlank(text[end]) { end += 1 }
                        replace(range.lowerBound..<end, with: "")
                    } else {
                        replace(separator..<separator + 1, with: "")
                        replace(range, with: "")
                    }
                } else {
                    // The last item goes with the comma before it, so a trailing comma stays.
                    guard item > 0, let separator = comma(after: item - 1) else { return false }
                    let previous = items[item - 1].range.upperBound
                    if isBlank(previous..<separator), isBlank(separator + 1..<range.lowerBound) {
                        replace(previous..<range.upperBound, with: "")
                    } else {
                        replace(range, with: "")
                        replace(separator..<separator + 1, with: "")
                    }
                }
                remaining -= 1
            }
            return true
        }

        private mutating func editBlockList(_ sequence: Node.Sequence, adding: Bool) -> Bool {
            var entries: [(line: Int, marker: String, isFavorite: Bool)] = []
            for node in sequence {
                guard case .scalar(let scalar) = node, let start = offset(scalar.mark) else { return false }
                let row = line(of: start)
                let marker = String(String.UnicodeScalarView(text[lineStarts[row]..<start]))
                guard marker.wholeMatch(of: /[ \t]*-[ \t]+/) != nil else { return false }
                entries.append((row, marker, NoteName.trimmed(scalar.string) == NoteFile.favoriteTag))
            }
            guard !entries.isEmpty else { return false }
            /// The lines an entry holds: its own and any that continue it, without comments or blank lines.
            func held(_ entry: Int) -> [Int] {
                let last = entry + 1 < entries.count ? entries[entry + 1].line : lineStarts.count
                return (entries[entry].line..<last).filter { line in
                    let content = text[lineStarts[line]..<lineEnd(line)].filter { !Self.isBlank($0) && !Self.isBreak($0) }
                    return line == entries[entry].line || !(content.isEmpty || content.first == "#")
                }
            }
            if adding {
                let lastEntry = entries.count - 1
                guard let last = held(lastEntry).last else { return false }
                let end = lineEnd(last)
                let ending = end >= 2 && text[end - 2] == "\r" ? "\r\n" : "\n"
                let hasBreak = end > 0 && text[end - 1] == "\n"
                replace(end..<end, with: (hasBreak ? "" : ending) + entries[lastEntry].marker + NoteFile.favoriteTag + (hasBreak ? ending : ""))
                return true
            }
            for entry in entries.indices.reversed() where entries[entry].isFavorite {
                for line in held(entry).reversed() {
                    replace(lineStarts[line]..<lineEnd(line), with: "")
                }
            }
            return true
        }

        /// An empty value becomes a flow list; a string on the key's line gains or loses one comma-separated item.
        mutating func editScalar(_ scalar: Node.Scalar, isNull: Bool, adding: Bool) -> Bool {
            if isNull {
                guard adding else { return false }
                let keyLine = text[lineStarts[0]..<lineEnd(0)]
                guard let colon = keyLine.firstIndex(of: ":") else { return false }
                let rest = keyLine[(colon + 1)...]
                var value = rest.prefix { !Self.isBreak($0) }
                var comment: ArraySlice<Unicode.Scalar> = []
                if let hash = value.indices.first(where: { value[$0] == "#" && ($0 == value.startIndex || Self.isBlank(value[$0 - 1])) }) {
                    comment = value[hash...]
                    value = value[..<hash]
                }
                let spelled = String(String.UnicodeScalarView(value)).trimmingCharacters(in: .whitespaces)
                guard ["", "~", "null"].contains(spelled) else { return false }
                let suffix = comment.isEmpty ? "" : " " + String(String.UnicodeScalarView(comment))
                replace(colon + 1..<value.endIndex + comment.count, with: " [\(NoteFile.favoriteTag)]" + suffix)
                return true
            }
            guard scalar.style == .plain || scalar.style == .singleQuoted || scalar.style == .doubleQuoted,
                  let start = offset(scalar.mark), line(of: start) == 0,
                  let end = scalarEnd(from: start, inFlow: false)
            else { return false }
            let content = scalar.style == .plain ? start..<end : start + 1..<end - 1
            // An escape or a folded line would make the text differ from the value read.
            guard content.lowerBound <= content.upperBound,
                  String(String.UnicodeScalarView(text[content])) == scalar.string
            else { return false }
            if adding {
                replace(content.upperBound..<content.upperBound, with: ", " + NoteFile.favoriteTag)
                return true
            }
            let pieces = text[content].split(separator: ",", omittingEmptySubsequences: false)
            let kept = pieces.filter { NoteName.trimmed(String(String.UnicodeScalarView($0))) != NoteFile.favoriteTag }
            var joined = Array(kept.joined(separator: [","]))
            while let first = joined.first, Self.isBlank(first) { joined.removeFirst() }
            replace(content, with: String(String.UnicodeScalarView(joined)))
            return true
        }
    }

    /// The note's own title, which Marfa keeps in the front matter.
    var title: String? {
        property("title").flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
    }

    /// The value on a top-level property's line. The key may be quoted and may have white space before its colon,
    /// since YAML reads each of those as the same key, and a second line for it would make the front matter invalid.
    private static func value(in line: Substring, for key: String) -> Substring? {
        var rest: Substring
        if line.hasPrefix(key) {
            rest = line.dropFirst(key.count)
        } else if line.hasPrefix("\"\(key)\"") || line.hasPrefix("'\(key)'") {
            rest = line.dropFirst(key.count + 2)
        } else {
            return nil
        }
        rest = rest.drop { $0 == " " || $0 == "\t" }
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
