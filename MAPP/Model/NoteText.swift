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
