import Foundation

/// The letters in a person chip's circle: the first character of the first word, and of the last when the name has
/// more than one. A character is a grapheme, so an emoji or a letter with its accent set apart stays whole.
nonisolated enum PersonInitials {
    static func of(_ name: String) -> String? {
        let words = name.split(whereSeparator: \.isWhitespace)
        guard let first = words.first?.first else { return nil }
        guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
        return (String(first) + String(last)).uppercased()
    }
}
