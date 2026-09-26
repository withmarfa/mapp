import Foundation

/// Reads a note's title and preview out of its markdown, the way Notes reads them out of rich text:
/// the first line is the title and what follows is the preview.
nonisolated enum NoteText {
    static let previewLimit = 240

    static func titleAndPreview(of body: String) -> (title: String, preview: String) {
        var title: String?
        var parts: [String] = []
        var length = 0
        for line in readableLines(of: body) {
            guard title != nil else {
                title = line
                continue
            }
            parts.append(line)
            length += line.count + 1
            if length >= previewLimit { break }
        }
        let preview = parts.joined(separator: " ")
        return (
            title ?? String(localized: "New Note"),
            preview.isEmpty ? String(localized: "No additional text") : String(preview.prefix(previewLimit))
        )
    }

    /// What follows the title: the body's text, less a first line that only repeats the title.
    static func preview(of body: String, title: String) -> String {
        var lines = readableLines(of: body)
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

    /// Whether the note's first line is finished, which shows once something is written on a line after it.
    /// The page writes every note with a closing line break, so one alone says nothing.
    static func hasCompleteFirstLine(_ body: String) -> Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).contains("\n")
    }

    /// The name a note's file takes from its first line: the line as it reads, without characters a file name
    /// cannot hold, and short enough for any file system.
    static func fileName(for body: String) -> String {
        let line = readableLines(of: body).first ?? ""
        let cleaned = line
            .replacing(/[\/\\:\x00-\x1F]/, with: "-")
            .trimmingCharacters(in: .whitespaces)
            .trimmingPrefix { $0 == "." }
        let name = fitted(String(cleaned)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? String(localized: "New Note") : name
    }

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

    /// The body's lines as they read on screen, blank lines dropped. Code inside fences is kept as written.
    static func readableLines(of body: String) -> [String] {
        var lines: [String] = []
        var inFence = false
        for line in body.split(whereSeparator: \.isNewline) {
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
        return inlineText(text).trimmingCharacters(in: .whitespaces)
    }

    /// Code spans keep their contents as written; everything around them loses links and emphasis.
    private static func inlineText(_ text: String) -> String {
        var result = ""
        var rest = text[...]
        while let span = rest.firstMatch(of: codeSpan) {
            result += stripInline(String(rest[..<span.range.lowerBound]))
            result += span.output.1
            rest = rest[span.range.upperBound...]
        }
        return result + stripInline(String(rest))
    }

    private static func stripInline(_ text: String) -> String {
        var text = text
        text.replace(image) { String($0.output.1) }
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
