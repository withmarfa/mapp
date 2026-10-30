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
    ///
    /// The header is read again on every edit of the text, so this scans the UTF-8 once per kind of markup instead
    /// of running regular expressions over a long article. Each scan matches what its pattern would, read by Unicode
    /// scalar rather than by character: `![...](...)`, then `](...)`, then `<...>`, each replaced by a space. Each
    /// scan reads the text at most once for each closer it looks for, however many openers find none.
    static func words(in markdown: String) -> Int {
        var bytes = Array(markdown.utf8)
        bytes = replacingMatches(in: bytes) { closers, start in
            let bytes = closers.bytes
            guard bytes[start] == UInt8(ascii: "!"), start + 1 < bytes.count, bytes[start + 1] == UInt8(ascii: "["),
                  let label = closers.first(UInt8(ascii: "]"), from: start + 2),
                  label + 1 < bytes.count, bytes[label + 1] == UInt8(ascii: "("),
                  let end = closers.first(UInt8(ascii: ")"), from: label + 2) else { return nil }
            return end + 1
        }
        bytes = replacingMatches(in: bytes) { closers, start in
            let bytes = closers.bytes
            guard bytes[start] == UInt8(ascii: "]"), start + 1 < bytes.count, bytes[start + 1] == UInt8(ascii: "("),
                  let end = closers.first(UInt8(ascii: ")"), from: start + 2) else { return nil }
            return end + 1
        }
        bytes = replacingMatches(in: bytes) { closers, start in
            guard closers.bytes[start] == UInt8(ascii: "<"), let end = closers.first(UInt8(ascii: ">"), from: start + 1)
            else { return nil }
            return end + 1
        }
        return String(decoding: bytes, as: UTF8.self).split(whereSeparator: \.isWhitespace)
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }.count
    }

    /// Where each closer next appears, for a scan whose searches never start before an earlier one did. An answer
    /// at or after a search's start is still the first there, so it is reused, and a closer found nowhere is never
    /// looked for again: without this, text full of openers with no closer, such as `a < b`, is read once per opener.
    private struct Closers {
        let bytes: [UInt8]
        /// The last answer for each closer: its index, or `bytes.count` where it appears nowhere after the search's start.
        private var found: [UInt8: Int] = [:]

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func first(_ closer: UInt8, from start: Int) -> Int? {
            if let known = found[closer], known >= start { return known < bytes.count ? known : nil }
            let index = bytes[start...].firstIndex(of: closer) ?? bytes.count
            found[closer] = index
            return index < bytes.count ? index : nil
        }
    }

    /// `bytes` with each match replaced by a space. `match` gives the end of the match starting at an index, if one does.
    private static func replacingMatches(in bytes: [UInt8], _ match: (inout Closers, Int) -> Int?) -> [UInt8] {
        var closers = Closers(bytes)
        var result = [UInt8]()
        result.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if let end = match(&closers, index) {
                result.append(UInt8(ascii: " "))
                index = end
            } else {
                result.append(bytes[index])
                index += 1
            }
        }
        return result
    }
}
