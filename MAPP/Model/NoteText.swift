import Foundation

/// Reads a note's title and preview out of its markdown, the way Notes reads them out of rich text:
/// the first line is the title and what follows is the preview.
enum NoteText {
    static func title(of body: String) -> String {
        for line in body.split(whereSeparator: \.isNewline) {
            let text = plainText(of: line)
            if !text.isEmpty { return text }
        }
        return String(localized: "New Note")
    }

    static func preview(of body: String, limit: Int = 240) -> String {
        var parts: [String] = []
        var length = 0
        var foundTitle = false
        for line in body.split(whereSeparator: \.isNewline) {
            let text = plainText(of: line)
            guard !text.isEmpty else { continue }
            guard foundTitle else {
                foundTitle = true
                continue
            }
            parts.append(text)
            length += text.count + 1
            if length >= limit { break }
        }
        let preview = parts.joined(separator: " ")
        return preview.isEmpty ? String(localized: "No additional text") : String(preview.prefix(limit))
    }

    /// One line of markdown as it reads on screen: block markers, table pipes and inline syntax removed.
    static func plainText(of line: Substring) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.wholeMatch(of: structuralLine) != nil { return "" }

        var previous = ""
        while previous != text {
            previous = text
            text.replace(blockMarker, with: "")
        }
        if text.hasPrefix("|") || text.hasSuffix("|") {
            text = text.split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "  ")
        }
        text.replace(image) { String($0.output.1) }
        text.replace(link) { String($0.output.1) }
        text.replace(emphasisPair, with: "")
        text.replace(emphasisOpening) { String($0.output.1) }
        text.replace(emphasisClosing) { String($0.output.1) }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Code fences, thematic breaks and table delimiter rows carry no words.
    private static let structuralLine = /(```.*|~~~.*|([-*_]\s*){3,}|\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?)/
    private static let blockMarker = /^(#{1,6}\s+|>\s?|[-*+]\s+|\d+[.)]\s+|\[[ xX]\]\s+)/
    private static let image = /!\[([^\]]*)\]\([^)]*\)/
    private static let link = /\[([^\]]*)\]\([^)]*\)/
    private static let emphasisPair = /\*\*|__|~~|`/
    /// Single `*` and `_` count as emphasis only at a word's edge, so `snake_case` survives.
    private static let emphasisOpening = /(^|\W)[*_]+(?=\S)/
    private static let emphasisClosing = /(\S)[*_]+(?=\W|$)/
}
