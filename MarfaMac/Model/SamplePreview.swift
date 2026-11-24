#if DEBUG
import Foundation

/// Reading text for the sample library's fake copy, for the Markdown used in sample bodies.
nonisolated enum SamplePreview {
    private nonisolated(unsafe) static let rule = /^\s{0,3}([-*_])(\s*\1){2,}\s*$/
    private nonisolated(unsafe) static let underline = /^\s*=+\s*$/
    private nonisolated(unsafe) static let reference = /^\s{0,3}\[[^\]]+\]:\s.*$/
    private nonisolated(unsafe) static let delimiterRow = /^\s*\|?(\s*:?-+:?\s*\|)+(\s*:?-+:?\s*)?$|^\s*\|?\s*:?-+:?\s*\|?\s*$/
    private nonisolated(unsafe) static let quote = /^\s*>/
    private nonisolated(unsafe) static let listMarker = /^\s*(?:[-*+]|\d{1,9}[.)])(?:\s+|$)(?:\[[ xX]\]\s*)?/
    private nonisolated(unsafe) static let heading = /^\s*#{1,6}(?:\s+|$)/
    private nonisolated(unsafe) static let headingClose = /\s+#+\s*$/
    private nonisolated(unsafe) static let image = /!\[[^\]]*\]\([^)]*\)|!\[\[[^\]]*\]\]/
    private nonisolated(unsafe) static let wikiLink = /\[\[(?:[^\]|]*\|)?([^\]]*)\]\]/
    private nonisolated(unsafe) static let link = /\[([^\]]*)\]\([^)]*\)/
    private nonisolated(unsafe) static let runs = /[*_~]{2,}/

    /// The text the lines read as: one string, the lines joined with single spaces, cut at 240 characters.
    static func text(of lines: [String]) -> String {
        var pieces: [String] = []
        var inFence = false
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") || line.trimmingCharacters(in: .whitespaces).hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence {
                pieces.append(line)
                continue
            }
            if line.wholeMatch(of: rule) != nil || line.wholeMatch(of: underline) != nil || line.wholeMatch(of: reference) != nil { continue }
            if line.contains("|"), index < lines.count, lines[index].contains("-"), lines[index].wholeMatch(of: delimiterRow) != nil {
                pieces.append(cells(of: line))
                index += 1
                while index < lines.count, lines[index].contains("|") {
                    pieces.append(cells(of: lines[index]))
                    index += 1
                }
                continue
            }
            pieces.append(inline(withoutPrefixes(line)))
        }
        let joined = pieces.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return joined.count > 240 ? String(joined.prefix(239)) + "\u{2026}" : joined
    }

    /// One line as the name reads it, with its marks left out.
    static func line(_ text: String) -> String {
        inline(withoutPrefixes(text)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func cells(of row: String) -> String {
        row.split(separator: "|").map { inline(String($0)).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The quote, list and heading marks at the start of a line, taken off until none is left.
    private static func withoutPrefixes(_ line: String) -> String {
        var text = line
        while true {
            if let match = text.prefixMatch(of: quote) ?? text.prefixMatch(of: listMarker) ?? text.prefixMatch(of: heading) {
                text = String(text[match.range.upperBound...])
            } else {
                break
            }
        }
        return text.replacing(headingClose, with: "").trimmingCharacters(in: .whitespaces)
    }

    private static func inline(_ text: String) -> String {
        text.replacing(image, with: "").replacing(wikiLink) { String($0.1) }.replacing(link) { String($0.1) }
            .replacing(runs, with: "").replacing("`", with: "").removingSingleMarks()
    }
}

private extension String {
    /// Takes out each single `*` or `_` with a letter or digit on exactly one side of it, which is emphasis; one inside
    /// a word or standing alone is text.
    nonisolated func removingSingleMarks() -> String {
        let characters = Array(self)
        func isWordCharacter(_ index: Int) -> Bool {
            characters.indices.contains(index) && (characters[index].isLetter || characters[index].isNumber)
        }
        return String(characters.indices.compactMap { index in
            let character = characters[index]
            guard character == "*" || character == "_" else { return character }
            return isWordCharacter(index - 1) != isWordCharacter(index + 1) ? nil : character
        })
    }
}
#endif
