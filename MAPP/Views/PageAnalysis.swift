import Foundation

/// What a saved HTML document turned out to be, found by `PageAnalyzer`: the article in it, if there is one, and whether
/// it is laid out as a mail. It decides which looks the item page offers and how the original is placed.
nonisolated struct PageAnalysis: Equatable, Sendable {
    /// The article Readability found, or nil when there is none or what it found is too short to be one.
    var article: Article?
    /// Whether the document is laid out as the mail a sender's tool makes (`MailColumn`). Marfa's catalogue has no type
    /// for a newsletter or a mail, so the markup is all there is to go by.
    var isMail: Bool

    static let none = PageAnalysis(article: nil, isMail: false)

    /// Fewer characters of text than this are a snippet, not an article: Readability's own threshold for a page worth
    /// reading, which it falls short of rather than fail, so the answer is checked here.
    static let shortestArticle = 500

    struct Article: Equatable, Sendable {
        /// The article's markup, from the document as written: its pictures still name their websites, for
        /// `SealedPictureRewrite` to point at the app.
        var html: String
        /// The article's language, as a BCP 47 tag, where the document said one.
        var language: String?
        /// The direction the document gave the article's text, where it said one.
        var direction: Direction?

        enum Direction: String, Sendable { case ltr, rtl }
    }

    /// Reader is offered only for an article; any other document is shown as it is.
    var offersReader: Bool { article != nil }

    /// The look to show: the person's choice, or the original where the document has no article to read.
    func mode(choosing chosen: SourceViewMode) -> SourceViewMode { offersReader ? chosen : .original }

    init(article: Article?, isMail: Bool) {
        self.article = article
        self.isMail = isMail
    }

    /// The analysis the script's answer describes, or `none` for an answer that is not what the script gives.
    init(javaScript answer: Any?) {
        guard let answer = answer as? [String: Any] else {
            self = .none
            return
        }
        self.init(article: Article(javaScript: answer["article"]), isMail: answer["mail"] as? Bool ?? false)
    }
}

nonisolated extension PageAnalysis.Article {
    fileprivate init?(javaScript answer: Any?) {
        guard let answer = answer as? [String: Any], let html = answer["html"] as? String,
              let length = (answer["length"] as? NSNumber)?.intValue, length >= PageAnalysis.shortestArticle
        else { return nil }
        self.init(
            html: html, language: (answer["lang"] as? String).flatMap { Self.isLanguageTag($0) ? $0 : nil },
            direction: (answer["dir"] as? String).flatMap { Direction(rawValue: $0.lowercased()) })
    }

    /// A language tag is letters, digits and hyphens, so one is safe to write into an attribute.
    static func isLanguageTag(_ text: String) -> Bool {
        (1...35).contains(text.utf8.count) && text.utf8.allSatisfy { byte in
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x2D
        }
    }
}
