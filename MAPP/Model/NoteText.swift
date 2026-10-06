import Foundation

/// Reads a note's words out of its markdown, as they read on screen: the first line, which names a note, and
/// the preview that follows it.
nonisolated enum NoteText {
    static let previewLimit = 240

    /// The first line with words in it, as it reads; nil for a note with nothing in it yet.
    static func firstLine(of body: String) -> String? {
        readableLines(of: body, limit: 1).first
    }

    /// What follows the title: the body's text, less a first line that only repeats the title.
    static func preview(of body: String, title: String) -> String {
        var lines = readableLines(of: body, limit: 64)
        if let first = lines.first, first.localizedCaseInsensitiveCompare(title) == .orderedSame {
            lines.removeFirst()
        }
        var preview = ""
        for line in lines {
            preview += preview.isEmpty ? line : " " + line
            if preview.count >= previewLimit { break }
        }
        return preview.isEmpty ? String(localized: "No additional text") : String(preview.prefix(previewLimit))
    }

    /// The note's text around the first place a search finds, as one line, to show why a note was found.
    static func snippet(of body: String, around query: String, reach: Int = 48) -> String? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = readableLines(of: body).joined(separator: " ")
        guard !query.isEmpty, let found = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
        else { return nil }
        let start = text.index(found.lowerBound, offsetBy: -reach, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(found.upperBound, offsetBy: reach, limitedBy: text.endIndex) ?? text.endIndex
        let stretch = text[start..<end].trimmingCharacters(in: .whitespaces)
        return (start > text.startIndex ? "…" : "") + stretch + (end < text.endIndex ? "…" : "")
    }

    /// The name a note's file takes from its first line.
    static func fileName(for body: String) -> String {
        name(for: firstLine(of: body) ?? "")
    }

    /// The name for a first line: the line as it reads, as a file can hold it, or New Note for none.
    static func name(for line: String) -> String {
        let name = fileSafe(line)
        return name.isEmpty ? String(localized: "New Note") : name
    }

    /// Whether a file's name is the one a first line gives, or that name numbered, as a second note of the
    /// same name is. Unless `exactly`, a name an earlier version gave the line also counts: it kept the line's
    /// backslash escapes and character references as written (`Plan&#x20;`), and the note goes on following
    /// its line, to take the name it should have when next left.
    static func isName(_ fileTitle: String, of line: String, exactly: Bool = false) -> Bool {
        let name = name(for: line)
        if fileTitle == name { return true }
        if fileTitle.hasPrefix(name + " "), let number = Int(fileTitle.dropFirst(name.count + 1)), number > 1 {
            return true
        }
        let earlier = fileSafe(unescaped(fileTitle))
        return !exactly && earlier != fileTitle && isName(earlier, of: line, exactly: true)
    }

    /// Whether a first line has characters its file's name cannot, so the note keeps the line as its `title`,
    /// where Marfa reads a title from.
    static func needsTitle(_ line: String) -> Bool {
        line.contains(unsafeInName) || line.hasPrefix(".")
    }

    /// A name as a file can take it: characters no file name can hold replaced, leading dots dropped, which
    /// would hide the file, and short enough for any file system. The one place a name is made safe, for notes,
    /// folders and attachments alike.
    static func fileSafe(_ name: String) -> String {
        fitted(
            name.replacing(unsafeInName, with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingPrefix { $0 == "." }
                .trimmingCharacters(in: .whitespaces)
        ).trimmingCharacters(in: .whitespaces)
    }

    private nonisolated(unsafe) static let unsafeInName = /[\/\\:\x00-\x1F\x7F]/

    /// A name short enough for any file system, which counts bytes, with room for a number and `.md` after it.
    static func fitted(_ name: String, room: Int = 0) -> String {
        var name = name
        while name.utf8.count > 200 - room { name.removeLast() }
        return name
    }

    /// The body with its links into the attachments folder written from a new directory, as when the note moves
    /// between the Inbox and a folder, so they still reach their files. Other links are left as written.
    static func rebasingAttachmentLinks(in body: String, from old: String, to new: String) -> String {
        guard old != new else { return body }
        return body.replacing(markdownLink) { match in
            let (whole, opening, destination) = match.output
            let bracketed = destination.hasPrefix("<") && destination.hasSuffix(">")
            let raw = bracketed ? String(destination.dropFirst().dropLast()) : String(destination)
            guard let target = attachmentPath(raw, from: old) else { return String(whole) }
            let depth = new.split(separator: "/").count
            let encoded = target.split(separator: "/").map {
                $0.addingPercentEncoding(withAllowedCharacters: linkPathAllowed) ?? String($0)
            }
            return String(opening) + (Array(repeating: "..", count: depth) + encoded).joined(separator: "/")
        }
    }

    /// Where a relative link from the directory leads, when it leads into the attachments folder.
    private static func attachmentPath(_ link: String, from directory: String) -> String? {
        guard !link.isEmpty, link.firstMatch(of: /^[a-zA-Z][a-zA-Z0-9+.-]*:|^\/|^#/) == nil,
              let decoded = link.removingPercentEncoding
        else { return nil }
        var components = directory.split(separator: "/").map(String.init)
        for part in decoded.split(separator: "/").map(String.init) {
            switch part {
            case ".": continue
            case "..": if components.popLast() == nil { return nil }
            default: components.append(part)
            }
        }
        guard components.count > 1, components.first == FolderStore.attachments else { return nil }
        return components.joined(separator: "/")
    }

    /// What a markdown link's path can hold as it is; spaces and brackets are escaped.
    static let linkPathAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "()<> "))

    /// A markdown link or image up to the end of its destination: `[text](` and the destination.
    private nonisolated(unsafe) static let markdownLink = /(!?\[(?:[^\]\\]|\\.)*\]\()(<[^>\n]*>|[^)\s]+)/

    /// The body's lines as they read on screen, blank lines dropped, up to a limit, since a title and preview
    /// need only the first few. Code inside fences is kept as written.
    static func readableLines(of body: String, limit: Int = .max) -> [String] {
        var lines: [String] = []
        var inFence = false
        for line in body.split(whereSeparator: \.isNewline) {
            if lines.count >= limit { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.wholeMatch(of: fence) != nil {
                inFence.toggle()
                continue
            }
            let text = inFence ? trimmed : plainText(of: line)
            if !text.isEmpty { lines.append(text) }
        }
        return lines
    }

    /// One line of markdown as it reads on screen: block markers, table pipes and inline syntax removed.
    static func plainText(of line: Substring) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.wholeMatch(of: structuralLine) != nil { return "" }

        text.replace(quoteMarkers, with: "")
        if text.firstMatch(of: headingMarker) != nil {
            text.replace(headingMarker, with: "")
        } else {
            text.replace(listMarker, with: "")
        }
        if text.hasPrefix("|") || text.hasSuffix("|") {
            text = text.split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "  ")
        }
        // A control character reads as a space, and has no place in a title, a name or front matter.
        let readable = String(String.UnicodeScalarView(inlineText(text).unicodeScalars.map {
            $0.properties.generalCategory == .control ? " " : $0
        }))
        return readable.trimmingCharacters(in: .whitespaces)
    }

    /// Code spans keep their contents as written; everything around them loses links and emphasis.
    private static func inlineText(_ text: String) -> String {
        var result = ""
        var rest = text[...]
        while let span = rest.firstMatch(of: codeSpan) {
            result += unescaped(stripInline(String(rest[..<span.range.lowerBound])))
            result += span.output.1
            rest = rest[span.range.upperBound...]
        }
        return result + unescaped(stripInline(String(rest)))
    }

    /// Text as markdown means it: a backslash before punctuation is only there to keep the punctuation plain,
    /// and a character reference such as `&amp;` or `&#x20;` stands for its character.
    static func unescaped(_ text: String) -> String {
        guard text.contains("\\") || text.contains("&") else { return text }
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
        // An image's width rides in its alt text, as `name|400`; the name alone is what it says.
        text.replace(image) { String($0.output.1).replacing(/\\?\|\d{1,5}$/, with: "") }
        text.replace(link) { String($0.output.1) }
        text.replace(strongOrStrike) { String($0.output.2) }
        text.replace(emphasis) { String($0.output.1) + String($0.output.2) }
        return text
    }

    // Regex is not Sendable; these are immutable and only ever read.
    private nonisolated(unsafe) static let fence = /(```|~~~).*/
    /// Thematic breaks, setext underlines and table delimiter rows carry no words.
    private nonisolated(unsafe) static let structuralLine = /([-*_]\s*){3,}|=+|\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?/
    private nonisolated(unsafe) static let quoteMarkers = /^(>\s?)+/
    private nonisolated(unsafe) static let headingMarker = /^#{1,6}(\s+|$)/
    private nonisolated(unsafe) static let listMarker = /^([-*+]|\d{1,9}[.)])(\s+|$)(\[[ xX]\](\s+|$))?/
    private nonisolated(unsafe) static let codeSpan = /`+([^`]*)`+/
    private nonisolated(unsafe) static let image = /!\[([^\]]*)\]\((?:[^()]|\([^()]*\))*\)/
    private nonisolated(unsafe) static let link = /\[([^\]]*)\]\((?:[^()]|\([^()]*\))*\)/
    private nonisolated(unsafe) static let strongOrStrike = /(\*\*|__|~~)(\S(?:.*?\S)?)\1/
    /// A single `*` or `_` counts only in pairs at a word's edges, so `snake_case` and `*.swift` survive.
    private nonisolated(unsafe) static let emphasis = /(^|[^\w*])[*_](\S(?:.*?\S)?)[*_](?=[^\w*]|$)/
}
