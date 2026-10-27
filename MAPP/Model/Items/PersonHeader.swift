import Foundation

/// What a person's page shows first: their initials, or their picture if the item carries one, and a line saying
/// what they do and where.
nonisolated struct PersonHeader: Hashable, Sendable, Encodable {
    let initials: String
    /// An image the item holds inline (a data URI), which the page may show because it needs no network.
    let photo: String?
    /// The largest picture the page is sent with each header; a bigger one is left to the inspector.
    static let largestPhoto = 200_000

    /// The properties the header draws.
    static let keys: Set<String> = ["job_title", "organization"]

    let subtitle: String?

    init(item: Item) {
        func text(_ key: String) -> String? {
            item.value(of: key)?.string.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        if let given = text("given_name"), let family = text("family_name") {
            initials = Self.initials(of: [given, family])
        } else {
            initials = Self.initials(of: item.title.split(whereSeparator: \.isWhitespace).map(String.init))
        }
        let line = [text("job_title"), text("organization")].compactMap { $0 }.joined(separator: ", ")
        subtitle = line.isEmpty ? nil : line
        let thumbnail = text("thumbnail")
        photo = thumbnail.flatMap { $0.hasPrefix("data:image/") && $0.count <= Self.largestPhoto ? $0 : nil }
    }

    /// The first letter of the first and last words, so "Ruth Okonjo" is "RO" and "Cher" is "C".
    static func initials(of words: [String]) -> String {
        let letters = words.compactMap { $0.first(where: \.isLetter) }
        guard let first = letters.first else { return "" }
        guard letters.count > 1, let last = letters.last else { return String(first).uppercased() }
        return (String(first) + String(last)).uppercased()
    }
}
