import Foundation
import UniformTypeIdentifiers

/// The words a list row shows under an item's title. A library makes them once, when it builds the item, so a
/// long list scrolls without reading any markdown.
nonisolated enum ItemPreview {
    /// Enough for two lines of the widest list, and little enough to keep with every item.
    static let limit = 240

    /// How much of a body is read: a preview never needs more, and a long note costs nothing extra.
    private static let reach = 4_000

    /// The body as plain text on one line. Markdown marks are gone, headings are skipped since they only name what
    /// follows, a first line that only repeats the title is dropped, and an item with no more text has an empty
    /// preview, so its row shows no gap. The fallback, such as a description, stands in when the body gives none.
    static func text(of body: String, title: String, fallback: String? = nil) -> String {
        let text = plain(body, title: title)
        guard text.isEmpty, let fallback else { return text }
        return plain(fallback, title: title)
    }

    private static func plain(_ body: String, title: String) -> String {
        var text = String(body.prefix(reach))
        if NoteText.holds(text, "<"), text.contains("<!--") {
            text.replace(comment, with: " ")
            text.replace(unfinishedComment, with: " ")
        }
        var lines = NoteText.readableLines(of: text, limit: 24, skippingHeadings: true, characters: limit + 80)
        if let first = lines.first, first.localizedCaseInsensitiveCompare(title) == .orderedSame {
            lines.removeFirst()
        }
        let words = sentences(lines).split(whereSeparator: \.isWhitespace)
        return String(words.joined(separator: " ").prefix(limit))
    }

    /// The lines run together, each ending as a sentence and starting as one, so the items of a list read apart,
    /// not as one phrase.
    private static func sentences(_ lines: [String]) -> String {
        var joined: [String] = []
        for (index, line) in lines.enumerated() {
            var line = line
            if let previous = joined.last, previous.last.map({ ".!?…".contains($0) }) == true {
                line = capitalized(line)
            }
            let isLast = index == lines.count - 1
            joined.append(isLast || endsSentence(line) ? line : line + ".")
        }
        return joined.joined(separator: " ")
    }

    private static func endsSentence(_ line: String) -> Bool {
        let closers: Set<Character> = [")", "]", "\"", "'", "”", "’", "»", "*", "_", "`"]
        guard let last = line.last(where: { !closers.contains($0) }) else { return true }
        return ".!?…:;".contains(last)
    }

    /// A line that begins with a lowercase word, as a list item does, begins a sentence. A word with a capital
    /// inside it, such as `iPhone`, is a name and stays as written.
    private static func capitalized(_ line: String) -> String {
        guard let first = line.first, first.isLowercase else { return line }
        let word = line.prefix { $0.isLetter }
        guard word.allSatisfy(\.isLowercase) else { return line }
        return first.uppercased() + line.dropFirst()
    }

    /// What a file's row says in place of text: its kind and size, as `Plain text, 76 bytes`. A size the library
    /// does not know is left out.
    static func file(_ type: UTType, byteCount: Int64) -> String {
        let described = type.localizedDescription ?? String(localized: "File")
        let kind = described.prefix(1).localizedUppercase + described.dropFirst()
        guard byteCount > 0 else { return kind }
        return kind + ", " + ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private nonisolated(unsafe) static let comment = /<!--.*?-->/.dotMatchesNewlines()
    private nonisolated(unsafe) static let unfinishedComment = /<!--.*/.dotMatchesNewlines()
}
