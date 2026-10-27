import Foundation

/// What a page to read shows above its title: where it came from, when it was published and how long it takes,
/// and a description to stand under the title.
nonisolated struct ReadingHeader: Equatable, Sendable {
    /// "Y Combinator Blog · 2 Oct 2025 · 6 min read", as the byline's parts.
    let byline: PageByline
    /// The item's description, read as the page's dek.
    let dek: String?
    /// The address "Open Original" opens: a web address in the item's `url`.
    let original: URL?

    /// The properties the header draws, and `image_url`, which it leaves out: the page loads nothing from the network,
    /// and a bare image address reads as clutter above an article. The inspector still shows it.
    static let keys: Set<String> = ["description", "publisher", "source_title", "published_at", "image_url"]

    /// Fewer words than this are a clipping, not something to read for a time.
    static let shortestRead = 100
    static let wordsPerMinute = 220

    init(item: Item, body: String?, locale: Locale = .current, calendar: Calendar = .current) {
        func text(_ key: String) -> String? {
            item.value(of: key)?.string.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        original = Self.webAddress(text("url"))
        let host = original?.host(percentEncoded: false).map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        let published = text("published_at").flatMap { ItemDate.parse($0, calendar: calendar) }
            .map { ItemDate(date: $0.date, hasTime: false).text(locale: locale, calendar: calendar) }
        let words = body.map { Self.words(in: $0) } ?? 0
        let minutes = words >= Self.shortestRead ? Self.minutes(words: words) : nil
        byline = PageByline(
            source: text("source_title") ?? text("publisher") ?? host, date: published ?? "",
            detail: minutes.map { String(localized: "\($0) min read") })
        dek = text("description")
    }

    static func webAddress(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()), url.host() != nil
        else { return nil }
        return url
    }

    /// Whole minutes to read `words`, at least one.
    static func minutes(words: Int) -> Int { max(1, Int((Double(words) / Double(wordsPerMinute)).rounded(.up))) }

    /// The words a person reads in some Markdown: not the addresses of its links and images, nor the tags of any
    /// HTML in it.
    static func words(in markdown: String) -> Int {
        var text = markdown
        text.replace(#/!\[[^\]]*\]\([^)]*\)/#, with: " ")
        text.replace(#/\]\([^)]*\)/#, with: " ")
        text.replace(#/<[^>]*>/#, with: " ")
        return text.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }.count
    }
}
