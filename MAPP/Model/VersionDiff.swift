import Foundation

/// How a stretch of a version's text differs from the version before it.
nonisolated enum DiffChange: Hashable, Sendable {
    case same, added, removed
}

/// A stretch of text read against another version of it.
nonisolated struct DiffPiece: Hashable, Sendable {
    var text: String
    var change: DiffChange
}

/// The words of one text set against the words of another. Pure, so the page that draws it decides nothing.
nonisolated enum WordDiff {
    /// Above this many pairs of words the exact comparison is not attempted; the lines are compared instead.
    private static let wordPairLimit = 4_000_000

    /// The text of `new` in order, cut into pieces that are the same as `old`, added in `new`, or removed from `old`.
    /// Removed pieces stand where they were in `old`. Joining the pieces that are not removed gives `new`; joining those
    /// that are not added gives `old`.
    static func pieces(from old: String, to new: String) -> [DiffPiece] {
        if old == new { return new.isEmpty ? [] : [DiffPiece(text: new, change: .same)] }
        let found = compare(tokens(old, by: .words), tokens(new, by: .words), limit: wordPairLimit, fallback: {
            compare(tokens(old, by: .lines), tokens(new, by: .lines), limit: 40_000_000, fallback: { nil })
        })
        // Neighbouring pieces of one kind are one piece, so a count of changes is a count of stretches.
        var merged: [DiffPiece] = []
        for piece in found where !piece.text.isEmpty {
            if let last = merged.last, last.change == piece.change {
                merged[merged.count - 1].text += piece.text
            } else {
                merged.append(piece)
            }
        }
        return merged
    }

    /// How many stretches were added and how many removed, ignoring stretches of only spaces.
    static func counts(_ pieces: [DiffPiece]) -> (added: Int, removed: Int) {
        func meaningful(_ piece: DiffPiece, _ change: DiffChange) -> Bool {
            piece.change == change && !piece.text.allSatisfy(\.isWhitespace)
        }
        return (pieces.filter { meaningful($0, .added) }.count, pieces.filter { meaningful($0, .removed) }.count)
    }

    /// How many separate changes there are: a removal and an addition side by side are one.
    static func changes(_ pieces: [DiffPiece]) -> Int {
        var count = 0
        var inChange = false
        for piece in pieces where !piece.text.allSatisfy(\.isWhitespace) {
            if piece.change == .same {
                inChange = false
            } else if !inChange {
                count += 1
                inChange = true
            }
        }
        return count
    }

    private enum Granularity { case words, lines }

    /// Runs of letters and digits, runs of spaces, and every other character alone; or lines with their break.
    private static func tokens(_ text: String, by granularity: Granularity) -> [String] {
        var tokens: [String] = []
        var current = ""
        var kind = 0
        func flush() { if !current.isEmpty { tokens.append(current); current = "" } }
        for character in text {
            switch granularity {
            case .lines:
                current.append(character)
                if character.isNewline { flush() }
            case .words:
                let next = character.isLetter || character.isNumber ? 1 : (character == " " || character == "\t" ? 2 : 0)
                if next == 0 || next != kind { flush() }
                current.append(character)
                kind = next
                if next == 0 { flush() }
            }
        }
        flush()
        return tokens
    }

    private static func compare(_ a: [String], _ b: [String], limit: Int, fallback: () -> [DiffPiece]?) -> [DiffPiece] {
        var start = 0
        while start < a.count, start < b.count, a[start] == b[start] { start += 1 }
        var endA = a.count, endB = b.count
        while endA > start, endB > start, a[endA - 1] == b[endB - 1] { endA -= 1; endB -= 1 }
        let head = a[..<start].joined()
        let tail = a[endA...].joined()
        let x = Array(a[start..<endA]), y = Array(b[start..<endB])
        var middle: [DiffPiece]
        if x.isEmpty || y.isEmpty {
            middle = [DiffPiece(text: x.joined(), change: .removed), DiffPiece(text: y.joined(), change: .added)]
        } else if x.count * y.count > limit {
            if let lines = fallback() { return lines }
            middle = [DiffPiece(text: x.joined(), change: .removed), DiffPiece(text: y.joined(), change: .added)]
        } else {
            middle = longestCommon(x, y)
        }
        return [DiffPiece(text: head, change: .same)] + middle + [DiffPiece(text: tail, change: .same)]
    }

    private static func longestCommon(_ x: [String], _ y: [String]) -> [DiffPiece] {
        let n = x.count, m = y.count
        var table = [UInt16](repeating: 0, count: (n + 1) * (m + 1))
        let width = m + 1
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i * width + j] = x[i] == y[j]
                    ? table[(i + 1) * width + j + 1] &+ 1
                    : max(table[(i + 1) * width + j], table[i * width + j + 1])
            }
        }
        var pieces: [DiffPiece] = []
        var i = 0, j = 0
        while i < n, j < m {
            if x[i] == y[j] {
                pieces.append(DiffPiece(text: x[i], change: .same)); i += 1; j += 1
            } else if table[(i + 1) * width + j] >= table[i * width + j + 1] {
                pieces.append(DiffPiece(text: x[i], change: .removed)); i += 1
            } else {
                pieces.append(DiffPiece(text: y[j], change: .added)); j += 1
            }
        }
        while i < n { pieces.append(DiffPiece(text: x[i], change: .removed)); i += 1 }
        while j < m { pieces.append(DiffPiece(text: y[j], change: .added)); j += 1 }
        return pieces
    }
}

// MARK: Reading a text as a page

/// A span of one line: text, how it is marked against the other version, and how it is set.
nonisolated struct ReadSpan: Hashable, Sendable {
    var text: String
    var change: DiffChange
    var bold = false
    var italic = false
    var code = false
    var link: String?
    /// Whether the span is the shown text of a `[[wiki link]]`, which a version draws as a link but does not follow.
    var wikiLink = false
}

/// A table in a version's text. Every row has one cell for each column, and a cell is spans, as a line's are.
nonisolated struct ReadTable: Hashable, Sendable {
    enum Alignment: Hashable, Sendable { case leading, center, trailing }

    var alignments: [Alignment]
    var header: [[ReadSpan]]
    var rows: [[[ReadSpan]]]
}

/// One line of a version's text laid out for reading: what kind of line it is, and its spans without the marks that
/// make the kind (`#`, `-`, `>`), which the page draws as a heading, a bullet or a quote.
nonisolated struct ReadLine: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case paragraph
        case heading(level: Int)
        /// `number` is the entry's number in an ordered list.
        case bullet(depth: Int, number: Int?)
        case quote
        case code
        case rule
        case blank
        /// A table, from its header row to its last row. The line has no spans of its own.
        case table(ReadTable)
    }

    let id: Int
    var kind: Kind
    var spans: [ReadSpan]

    /// Whether every part of the line was removed, so it stands only to show what went.
    var isRemoved: Bool { !spans.isEmpty && spans.allSatisfy { $0.change == .removed } }
}

nonisolated enum ReadableText {
    /// The version's lines, with `pieces` marking what it added and what the version before it had. Pass a single
    /// `.same` piece for text with nothing to compare against.
    static func lines(_ pieces: [DiffPiece]) -> [ReadLine] {
        var raw: [[(Character, DiffChange)]] = [[]]
        for piece in pieces {
            for character in piece.text {
                if character == "\n" || character == "\r\n" {
                    // A break that was removed ends the removed line it belongs to, and starts no empty one.
                    raw[raw.count - 1].append((character, piece.change))
                    raw.append([])
                } else {
                    raw[raw.count - 1].append((character, piece.change))
                }
            }
        }
        let rows = raw.map { $0.filter { !$0.0.isNewline } }
        var lines: [ReadLine] = []
        var inFence = false
        var index = 0
        while index < rows.count {
            if index == rows.count - 1, rows[index].isEmpty, index > 0 { break }
            if !inFence, let (found, next) = table(in: rows, at: index) {
                lines.append(ReadLine(id: index, kind: .table(found), spans: []))
                index = next
            } else {
                lines.append(read(rows[index], id: index, inFence: &inFence))
                index += 1
            }
        }
        return lines
    }

    private static func read(_ characters: [(Character, DiffChange)], id: Int, inFence: inout Bool) -> ReadLine {
        let text = String(characters.map(\.0))
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return ReadLine(id: id, kind: .blank, spans: spans(characters, drop: 0, marked: false)) }
        // The editor writes an empty paragraph as a lone break, which the note page shows as an empty line.
        if !inFence, ["<br>", "<br/>", "<br />"].contains(trimmed) { return ReadLine(id: id, kind: .blank, spans: []) }
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            inFence.toggle()
            return ReadLine(id: id, kind: .code, spans: spans(characters, drop: 0, marked: false))
        }
        if inFence { return ReadLine(id: id, kind: .code, spans: spans(characters, drop: 0, marked: false)) }
        let indent = text.prefix { $0 == " " || $0 == "\t" }.count
        let rest = text.dropFirst(indent)
        if let level = headingLevel(rest) {
            return ReadLine(id: id, kind: .heading(level: level), spans: spans(characters, drop: indent + level + 1))
        }
        if rest.count >= 3, Set(rest.filter { $0 != " " }).count == 1, let mark = rest.first, "-*_".contains(mark),
           rest.filter({ $0 == mark }).count >= 3 {
            return ReadLine(id: id, kind: .rule, spans: [])
        }
        if rest.hasPrefix("> ") || rest == ">" {
            return ReadLine(id: id, kind: .quote, spans: spans(characters, drop: indent + min(2, rest.count)))
        }
        if let first = rest.first, "-*+".contains(first), rest.dropFirst().first == " " {
            return ReadLine(id: id, kind: .bullet(depth: indent / 2, number: nil), spans: spans(characters, drop: indent + 2))
        }
        let digits = rest.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count < 10, rest.dropFirst(digits.count).hasPrefix(". "), let number = Int(digits) {
            return ReadLine(id: id, kind: .bullet(depth: indent / 2, number: number), spans: spans(characters, drop: indent + digits.count + 2))
        }
        return ReadLine(id: id, kind: .paragraph, spans: spans(characters, drop: 0))
    }

    private static func headingLevel(_ rest: Substring) -> Int? {
        let hashes = rest.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), rest.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    // MARK: Tables

    /// The table that starts at row `start`: a row of cells, a row of dashes that sets each column, and every row after
    /// them that holds a bar. Returns it with the index of the row after it. A row the version dropped stands in the
    /// table struck through, as a line does.
    private static func table(in rows: [[(Character, DiffChange)]], at start: Int) -> (ReadTable, Int)? {
        guard start + 1 < rows.count, isTableRow(rows[start]), isTableRow(rows[start + 1]) else { return nil }
        let header = cells(of: rows[start])
        guard let alignments = columnAlignments(of: cells(of: rows[start + 1]), count: header.count) else { return nil }
        var body: [[[ReadSpan]]] = []
        var next = start + 2
        while next < rows.count, isTableRow(rows[next]) {
            let row = cells(of: rows[next])
            // A second row of dashes belongs to the version this one replaced, and sets nothing here.
            if columnAlignments(of: row, count: header.count) == nil { body.append(fit(row, to: header.count)) }
            next += 1
        }
        return (ReadTable(alignments: alignments, header: fit(header, to: header.count), rows: body), next)
    }

    /// A row of a table holds a bar and does not start a fence.
    private static func isTableRow(_ row: [(Character, DiffChange)]) -> Bool {
        let text = String(row.map(\.0)).trimmingCharacters(in: .whitespaces)
        return text.contains("|") && !text.hasPrefix("```") && !text.hasPrefix("~~~")
    }

    /// The cells of a row, each as spans. The bars at the ends are not cells; `\|` and a bar inside code are text.
    private static func cells(of row: [(Character, DiffChange)]) -> [[ReadSpan]] {
        var cells: [[(Character, DiffChange)]] = [[]]
        var inCode = false
        var index = 0
        while index < row.count {
            let (character, change) = row[index]
            if character == "\\", index + 1 < row.count, row[index + 1].0 == "|" {
                cells[cells.count - 1].append(row[index + 1])
                index += 2
                continue
            }
            if character == "`" { inCode.toggle() }
            if character == "|", !inCode {
                cells.append([])
            } else {
                cells[cells.count - 1].append((character, change))
            }
            index += 1
        }
        func isBlank(_ cell: [(Character, DiffChange)]) -> Bool { cell.allSatisfy { $0.0.isWhitespace } }
        if let first = cells.first, isBlank(first) { cells.removeFirst() }
        if let last = cells.last, isBlank(last), !cells.isEmpty { cells.removeLast() }
        return cells.map { cell in
            var cell = cell[...]
            while let first = cell.first, first.0.isWhitespace { cell.removeFirst() }
            while let last = cell.last, last.0.isWhitespace { cell.removeLast() }
            return merge(inline(Array(cell)))
        }
    }

    /// How each column is set, if the cells are a row of dashes (`---`, `:--`, `:-:`, `--:`) of the table's width.
    private static func columnAlignments(of cells: [[ReadSpan]], count: Int) -> [ReadTable.Alignment]? {
        guard cells.count == count, count > 0 else { return nil }
        var result: [ReadTable.Alignment] = []
        for cell in cells {
            let text = cell.map(\.text).joined()
            let dashes = text.drop { $0 == ":" }.reversed().drop { $0 == ":" }
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            switch (text.hasPrefix(":"), text.hasSuffix(":")) {
            case (true, true): result.append(.center)
            case (false, true): result.append(.trailing)
            default: result.append(.leading)
            }
        }
        return result
    }

    /// The row with exactly `count` cells: short rows are filled out empty, and cells past the last column are left out.
    private static func fit(_ cells: [[ReadSpan]], to count: Int) -> [[ReadSpan]] {
        Array((cells + Array(repeating: [], count: max(0, count - cells.count))).prefix(count))
    }

    /// The characters after the first `drop`, in spans by mark and by how inline markdown sets them.
    private static func spans(_ characters: [(Character, DiffChange)], drop: Int, marked: Bool = true) -> [ReadSpan] {
        let body = Array(characters.dropFirst(drop))
        guard marked else { return merge(body.map { ReadSpan(text: String($0.0), change: $0.1) }) }
        return merge(inline(body))
    }

    /// Reads `**bold**`, `*italic*`, `_italic_`, `` `code` ``, `[text](address)` and `[[wiki links]]`, dropping their marks. A mark with no
    /// partner stays as typed. Marks and the text between them keep the change of the characters they came from.
    private static func inline(_ characters: [(Character, DiffChange)]) -> [ReadSpan] {
        var spans: [ReadSpan] = []
        var bold = false, italic = false
        var index = 0
        func add(_ character: Character, _ change: DiffChange, code: Bool = false, link: String? = nil, wikiLink: Bool = false) {
            spans.append(ReadSpan(
                text: String(character), change: change, bold: bold, italic: italic, code: code, link: link, wikiLink: wikiLink))
        }
        func find(_ marker: [Character], from start: Int) -> Int? {
            var i = start
            while i + marker.count <= characters.count {
                if (0..<marker.count).allSatisfy({ characters[i + $0].0 == marker[$0] }) { return i }
                i += 1
            }
            return nil
        }
        while index < characters.count {
            let (character, change) = characters[index]
            if character == "`", let end = find(["`"], from: index + 1) {
                for i in (index + 1)..<end { add(characters[i].0, characters[i].1, code: true) }
                index = end + 1
            } else if character == "*", index + 1 < characters.count, characters[index + 1].0 == "*",
                      bold || find(["*", "*"], from: index + 2) != nil {
                bold.toggle()
                index += 2
            } else if character == "*" || character == "_",
                      italic ? closesEmphasis(characters, at: index) : opensEmphasis(characters, at: index) {
                italic.toggle()
                index += 1
            } else if character == "[", index + 1 < characters.count, characters[index + 1].0 == "[",
                      let end = find(["]", "]"], from: index + 2),
                      !(index + 2..<end).contains(where: { characters[$0].0 == "[" || characters[$0].0 == "]" }) {
                // `[[target|label]]` shows its label, and `[[target]]` its target, as the note page does.
                let inside = Array((index + 2)..<end)
                let shown = inside.firstIndex { characters[$0].0 == "|" }.map { Array(inside[($0 + 1)...]) } ?? inside
                for i in shown { add(characters[i].0, characters[i].1, wikiLink: true) }
                index = end + 2
            } else if character == "[", let close = find(["]", "("], from: index + 1), let end = find([")"], from: close + 2) {
                let address = String(characters[(close + 2)..<end].map(\.0))
                for i in (index + 1)..<close { add(characters[i].0, characters[i].1, link: address) }
                index = end + 1
            } else {
                add(character, change)
                index += 1
            }
        }
        return spans
    }

    /// A mark opens emphasis when text follows it, a later mark of its kind closes it, and (for `_`) it does not sit
    /// inside a word, as in `snake_case`. A lone `*` between spaces, as in `2 * 3`, is a star.
    private static func opensEmphasis(_ characters: [(Character, DiffChange)], at index: Int) -> Bool {
        let mark = characters[index].0
        guard index + 1 < characters.count, characters[index + 1].0 != mark, !characters[index + 1].0.isWhitespace else { return false }
        if mark == "_", index > 0, characters[index - 1].0.isLetter || characters[index - 1].0.isNumber { return false }
        return ((index + 2)..<max(characters.count, index + 2)).contains { closesEmphasis(characters, at: $0) && characters[$0].0 == mark }
    }

    private static func closesEmphasis(_ characters: [(Character, DiffChange)], at index: Int) -> Bool {
        let mark = characters[index].0
        guard mark == "*" || mark == "_", index > 0, !characters[index - 1].0.isWhitespace, characters[index - 1].0 != mark else { return false }
        if index + 1 < characters.count {
            let after = characters[index + 1].0
            if after == mark { return false }
            if mark == "_", after.isLetter || after.isNumber { return false }
        }
        return true
    }

    private static func merge(_ spans: [ReadSpan]) -> [ReadSpan] {
        var merged: [ReadSpan] = []
        for span in spans {
            if var last = merged.last, last.change == span.change, last.bold == span.bold, last.italic == span.italic,
               last.code == span.code, last.link == span.link, last.wikiLink == span.wikiLink {
                last.text += span.text
                merged[merged.count - 1] = last
            } else {
                merged.append(span)
            }
        }
        return merged
    }
}
