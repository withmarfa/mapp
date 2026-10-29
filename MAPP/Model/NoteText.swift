import Foundation

/// Reads an item's words out of its markdown, as they read on screen: the lines a preview is made of.
nonisolated enum NoteText {
    /// A name as a file can take it: characters no file name can hold replaced, leading dots dropped, which
    /// would hide the file, and short enough for any file system. The one place a name is made safe, for a file
    /// the person saves or attaches.
    static func fileSafe(_ name: String) -> String {
        fitted(
            name.replacing(unsafeInName, with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingPrefix { $0 == "." }
                .trimmingCharacters(in: .whitespaces)
        ).trimmingCharacters(in: .whitespaces)
    }

    private nonisolated(unsafe) static let unsafeInName = /[\/\\:\x00-\x1F\x7F]/

    /// A name short enough for any file system, which counts bytes, with `room` left for an extension.
    private static func fitted(_ name: String, room: Int = 0) -> String {
        var name = name
        while name.utf8.count > 200 - room { name.removeLast() }
        return name
    }

    /// A file's name as an attachment can take it, keeping its extension, which says what it is.
    static func attachmentName(_ name: String) -> String {
        // A name such as `.png` is all extension.
        let bare = name.hasPrefix(".") && !name.dropFirst().contains(".")
        let ext = bare ? String(name.dropFirst()) : (name as NSString).pathExtension
        let stem = bare ? "" : fileSafe((name as NSString).deletingPathExtension)
        let short = fitted(stem, room: ext.utf8.count + 1)
        let base = short.isEmpty ? String(localized: "Image") : short
        return ext.isEmpty ? base : "\(base).\(fileSafe(ext))"
    }

    /// The body's lines as they read on screen, blank lines dropped, up to a limit, since a title and preview
    /// need only the first few. Code inside fences is kept as written. A preview skips headings, which only name
    /// what follows, and stops once its lines hold `characters` characters.
    static func readableLines(
        of body: String, limit: Int = .max, skippingHeadings: Bool = false, characters: Int = .max
    ) -> [String] {
        var lines: [String] = []
        var count = 0
        var inFence = false
        for line in Lines(body) {
            if lines.count >= limit || count >= characters { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.first == "`" || trimmed.first == "~", trimmed.wholeMatch(of: fence) != nil {
                inFence.toggle()
                continue
            }
            if skippingHeadings, !inFence {
                let unquoted = trimmed.first == ">" ? trimmed.replacing(quoteMarkers, with: "") : trimmed
                if unquoted.first == "#", unquoted.firstMatch(of: headingMarker) != nil { continue }
            }
            let text = inFence ? trimmed : plainText(of: line)
            if !text.isEmpty {
                lines.append(text)
                count += text.count
            }
        }
        return lines
    }

    /// One line of markdown as it reads on screen: block markers, table pipes and inline syntax removed.
    static func plainText(of line: Substring) -> String {
        // Each pattern runs only on a line holding a character it needs: a match that fails scans the whole line,
        // and across a library's previews most lines hold none.
        var text = line.trimmingCharacters(in: .whitespaces)
        if let first = text.first, "-*_=|:".contains(first), text.wholeMatch(of: structuralLine) != nil { return "" }

        if text.first == ">" { text.replace(quoteMarkers, with: "") }
        if text.first == "#", text.firstMatch(of: headingMarker) != nil {
            text.replace(headingMarker, with: "")
        } else if let first = text.first, "-*+".contains(first) || first.isNumber {
            text.replace(listMarker, with: "")
        }
        if text.hasPrefix("|") || text.hasSuffix("|") {
            text = text.split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "  ")
        }
        // A control character reads as a space, and has no place in a title or a name.
        var readable = inlineText(text)
        if mayHoldControl(readable) {
            readable = String(String.UnicodeScalarView(readable.unicodeScalars.map {
                $0.properties.generalCategory == .control ? " " : $0
            }))
        }
        return readable.trimmingCharacters(in: .whitespaces)
    }

    /// Whether the text may hold a control character (U+0000 to U+001F, U+007F to U+009F), read from its bytes: the
    /// lead byte 0xC2 also starts other characters, which only runs the full check.
    private static func mayHoldControl(_ text: String) -> Bool {
        text.utf8.contains { $0 < 0x20 || $0 == 0x7F || $0 == 0xC2 }
    }

    /// A text's lines, split where `Character.isNewline` splits them, with empty lines left out, read from the
    /// bytes and only as far as the reader goes: a preview needs a few lines of a body, not all of them. Every
    /// newline is a character of its own, so the byte where one starts is always where a character starts.
    struct Lines: Sequence, IteratorProtocol {
        private let text: String
        private var position: String.Index

        init(_ text: String) {
            self.text = text
            position = text.startIndex
        }

        mutating func next() -> Substring? {
            let bytes = text.utf8
            while position < bytes.endIndex {
                let start = position
                var index = start
                var separator: Int?
                while index < bytes.endIndex {
                    separator = Self.newline(in: bytes, at: index)
                    if separator != nil { break }
                    index = bytes.index(after: index)
                }
                position = separator.map { bytes.index(index, offsetBy: $0) } ?? bytes.endIndex
                if index > start { return text[start..<index] }
            }
            return nil
        }

        /// The length in bytes of the newline that starts at `index`, if one does: LF, VT, FF, CR, NEL, LS or PS.
        private static func newline(in bytes: String.UTF8View, at index: String.Index) -> Int? {
            let byte = bytes[index]
            if (0x0A...0x0D).contains(byte) { return 1 }
            guard byte == 0xC2 || byte == 0xE2 else { return nil }
            func after(_ offset: Int) -> UInt8? {
                guard let next = bytes.index(index, offsetBy: offset, limitedBy: bytes.endIndex), next < bytes.endIndex
                else { return nil }
                return bytes[next]
            }
            if byte == 0xC2 { return after(1) == 0x85 ? 2 : nil }
            return after(1) == 0x80 && (after(2) == 0xA8 || after(2) == 0xA9) ? 3 : nil
        }
    }

    /// Code spans keep their contents as written; everything around them loses links and emphasis.
    private static func inlineText(_ text: String) -> String {
        var result = ""
        var rest = text[...]
        while holds(rest, "`"), let span = rest.firstMatch(of: codeSpan) {
            result += unescaped(stripInline(String(rest[..<span.range.lowerBound])))
            result += span.output.1
            rest = rest[span.range.upperBound...]
        }
        return result + unescaped(stripInline(String(rest)))
    }

    /// Text as markdown means it: a backslash before punctuation is only there to keep the punctuation plain,
    /// and a character reference such as `&amp;` or `&#x20;` stands for its character.
    static func unescaped(_ text: String) -> String {
        guard holds(text, "\\") || holds(text, "&") else { return text }
        var text = text.replacing(backslashEscape) { String($0.output.1) }
        text.replace(characterReference) { match in
            let (whole, name) = match.output
            // A reference to a control character stands as written; it has no place in a title or a name.
            let number = name.hasPrefix("#x") || name.hasPrefix("#X")
                ? UInt32(name.dropFirst(2), radix: 16) : name.hasPrefix("#") ? UInt32(name.dropFirst()) : nil
            if name.hasPrefix("#") {
                guard let scalar = number.flatMap(Unicode.Scalar.init), scalar.properties.generalCategory != .control
                else { return String(whole) }
                return String(scalar)
            }
            return namedReferences[String(name)] ?? String(whole)
        }
        return text
    }

    private nonisolated(unsafe) static let backslashEscape = /\\([!-\/:-@\[-`{-~])/
    private nonisolated(unsafe) static let characterReference = /&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});/
    /// The references writers use for plain text; the full HTML list is not worth carrying for a preview.
    private static let namedReferences = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}",
        "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}", "copy": "\u{A9}",
    ]

    private static func stripInline(_ text: String) -> String {
        var text = text
        let authored = text
        if holds(text, "<") {
            text.replace(htmlBreak) { match in
                isEscaped(at: match.range.lowerBound, in: authored) ? String(match.output) : " "
            }
        }
        if holds(text, "[") {
            let linked = text
            text.replace(wikiReference) { match in
                let (whole, embedded, content) = match.output
                guard !isEscaped(at: match.range.lowerBound, in: linked) else { return String(whole) }
                let alias = firstUnescaped("|", in: content)
                let target = content[..<(alias ?? content.endIndex)]
                if !embedded.isEmpty {
                    return String(target[..<(firstUnescaped("#", in: target) ?? target.endIndex)])
                }
                return alias.map { String(content[content.index(after: $0)...]) } ?? String(content)
            }
            // An image's width rides in its alt text, as `name|400`; the name alone is what it says.
            text.replace(image) { String($0.output.1).replacing(/\\?\|\d{1,5}$/, with: "") }
            text.replace(link) { String($0.output.1) }
        }
        let starred = holds(text, "*") || holds(text, "_")
        if starred || holds(text, "~") { text.replace(strongOrStrike) { String($0.output.2) } }
        if starred { text.replace(emphasis) { String($0.output.1) + String($0.output.2) } }
        return text
    }

    /// Whether the text holds an ASCII character, read from its bytes: `StringProtocol.contains` with a string
    /// searches through Foundation, which costs more than the patterns it guards. A byte that is part of a larger
    /// character still answers true, which only runs the pattern, as it would run with no check.
    static func holds(_ text: some StringProtocol, _ character: Unicode.Scalar) -> Bool {
        let byte = UInt8(character.value)
        return text.utf8.contains(byte)
    }

    private static func isEscaped(at index: String.Index, in text: String) -> Bool {
        !text[..<index].reversed().prefix { $0 == "\\" }.count.isMultiple(of: 2)
    }

    private static func firstUnescaped(_ delimiter: Character, in text: Substring) -> String.Index? {
        var escaped = false
        for index in text.indices {
            if escaped {
                escaped = false
            } else if text[index] == "\\" {
                escaped = true
            } else if text[index] == delimiter {
                return index
            }
        }
        return nil
    }

    // Regex is not Sendable; these are immutable and only ever read.
    private nonisolated(unsafe) static let fence = /(```|~~~).*/
    /// Thematic breaks, setext underlines and table delimiter rows carry no words.
    private nonisolated(unsafe) static let structuralLine = /([-*_]\s*){3,}|=+|\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?/
    private nonisolated(unsafe) static let quoteMarkers = /^(>\s?)+/
    private nonisolated(unsafe) static let headingMarker = /^#{1,6}(\s+|$)/
    private nonisolated(unsafe) static let listMarker = /^([-*+]|\d{1,9}[.)])(\s+|$)(\[[ xX]\](\s+|$))?/
    private nonisolated(unsafe) static let codeSpan = /`+([^`]*)`+/
    private nonisolated(unsafe) static let htmlBreak = /(?i)<br\s*\/?\s*>/
    private nonisolated(unsafe) static let wikiReference = /(!?)\[\[((?:[^\\\]\n]|\\.)+)\]\]/
    private nonisolated(unsafe) static let image = /!\[([^\]]*)\]\((?:[^()]|\([^()]*\))*\)/
    private nonisolated(unsafe) static let link = /\[([^\]]*)\]\((?:[^()]|\([^()]*\))*\)/
    private nonisolated(unsafe) static let strongOrStrike = /(\*\*|__|~~)(\S(?:.*?\S)?)\1/
    /// A single `*` or `_` counts only in pairs at a word's edges, so `snake_case` and `*.swift` survive.
    private nonisolated(unsafe) static let emphasis = /(^|[^\w*])[*_](\S(?:.*?\S)?)[*_](?=[^\w*]|$)/
}
