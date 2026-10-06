import Foundation

/// A search hit's snippet comes as HTML, with `<mark>` around what was found and entities for the rest; a
/// preview shows it as plain text.
nonisolated enum MarfaSnippet {
    static func plainText(_ html: String) -> String {
        var text = ""
        var index = html.startIndex
        while index < html.endIndex {
            let character = html[index]
            if character == "<", let close = html[index...].firstIndex(of: ">") {
                index = html.index(after: close)
            } else if character == "&", let (decoded, next) = entity(in: html, at: index) {
                text.append(decoded)
                index = next
            } else {
                text.append(character)
                index = html.index(after: index)
            }
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static let named: [Substring: Character] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
    ]

    /// An entity left undecoded is kept as written, so a stray `&` reads as itself.
    private static func entity(in html: String, at start: String.Index) -> (Character, String.Index)? {
        let body = html.index(after: start)
        guard let end = html[body...].prefix(10).firstIndex(of: ";") else { return nil }
        let name = html[body..<end]
        let next = html.index(after: end)
        if let character = named[name] { return (character, next) }
        guard name.hasPrefix("#") else { return nil }
        let digits = name.dropFirst()
        let value = digits.first == "x" || digits.first == "X"
            ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits, radix: 10)
        guard let value, let scalar = Unicode.Scalar(value) else { return nil }
        return (Character(scalar), next)
    }
}
