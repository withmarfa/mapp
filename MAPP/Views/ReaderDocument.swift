import Foundation

/// The page Reader shows: the article `PageAnalyzer` found, alone in a document of its own, which `SourceLook` then
/// styles in the note page's text. The article's pictures name their websites until `SealedPictureRewrite` points them at
/// the app, as for any document.
///
/// The document allows no script, whatever the page allows: the article held none, and one that got in would not run.
nonisolated enum ReaderDocument {
    static func html(for article: PageAnalysis.Article) -> String {
        let language = article.language.map { " lang=\"\($0)\"" } ?? ""
        let direction = article.direction.map { " dir=\"\($0.rawValue)\"" } ?? ""
        return """
            <!doctype html><html\(language)\(direction)><head><meta charset="utf-8">\
            <meta http-equiv="Content-Security-Policy" content="script-src 'none'">\
            <meta name="viewport" content="width=device-width, initial-scale=1"></head>\
            <body><article>\(article.html)</article></body></html>
            """
    }
}
