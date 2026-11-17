import Foundation

/// A note's opening lines as a card reads them: the Markdown's own marks left out or drawn as text, never the source.
/// It reads a preview and writes nothing back, so the note keeps its bytes.
nonisolated enum OpeningText {
    private nonisolated(unsafe) static let rule = /^\s{0,3}([-*_])(\s*\1){2,}\s*$/
    private nonisolated(unsafe) static let tableSeparator = /^\s*\|?(\s*:?-+:?\s*\|)+(\s*:?-+:?\s*)?$/
    private nonisolated(unsafe) static let task = /^(\s*)[-*+]\s+\[[ xX]\]\s+(.*)$/
    private nonisolated(unsafe) static let bullet = /^(\s*)[-*+]\s+(.*)$/
    private nonisolated(unsafe) static let heading = /^\s{0,3}#{1,6}\s+(.*?)(\s+#+)?\s*$/
    private nonisolated(unsafe) static let quote = /^\s{0,3}>\s?(.*)$/
    /// A link or picture a preview cut off before its address ended: `[words](https` or `![words](`.
    private nonisolated(unsafe) static let cutAddress = /!?\[([^\]\n]*)\]\([^)\n]*$/
    /// A link or picture a preview cut off inside its words: `[the revised ed`.
    private nonisolated(unsafe) static let cutWords = /!?\[([^\]\n]*)$/

    /// The lines as plain reading text, one string a line, with the emphasis marks still in it.
    static func lines(from markdown: String) -> [String] {
        var out: [String] = []
        // A preview is cut where its length ends, so only its end can hold a link whose address is unfinished: it
        // shows the link's words, as the whole link would.
        let whole = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing(cutAddress) { String($0.1) }.replacing(cutWords) { String($0.1) }
        for raw in whole.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.wholeMatch(of: rule) != nil || line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { continue }
            if line.contains("|"), line.wholeMatch(of: tableSeparator) != nil { continue }
            let text = converted(line)
            // One blank line stands for any number, and none opens or closes the text.
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                if let last = out.last, !last.isEmpty { out.append("") }
            } else {
                out.append(text)
            }
        }
        while out.last == "" { out.removeLast() }
        return out
    }

    private static func converted(_ line: String) -> String {
        if let match = line.wholeMatch(of: task) { return String(match.1 + match.2) }
        if let match = line.wholeMatch(of: bullet) { return String(match.1) + "\u{2022} " + match.2 }
        if let match = line.wholeMatch(of: heading) { return String(match.1) }
        if let match = line.wholeMatch(of: quote) { return String(match.1) }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            return trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "   ")
        }
        return line
    }

    /// The text with emphasis drawn as styled text.
    static func attributed(from markdown: String) -> AttributedString {
        var result = AttributedString()
        for (index, line) in lines(from: markdown).enumerated() {
            if index > 0 { result += AttributedString("\n") }
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            result += (try? AttributedString(markdown: line, options: options)) ?? AttributedString(line)
        }
        // A link's words stay, but a card is for selecting and opening, so they are not a link to click.
        result.link = nil
        return result
    }
}
