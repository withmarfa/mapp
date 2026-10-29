import Foundation
import Testing
@testable import MAPP

/// Every picture a document points at a website for is drawn from the app instead, and only from its `src`.
struct SealedPictureRewriteTests {
    private let item = ItemID("item-1")

    private func rewrite(_ html: String) -> (html: String, addresses: [String]) {
        let result = SealedPictureRewrite.rewrite(Data(html.utf8), item: item, version: 3)
        return (String(decoding: result.html, as: UTF8.self), result.addresses.map(\.absoluteString))
    }

    /// The addresses the rewritten document asks the app for, read back as the page would read its `src` values.
    private func requested(in html: String) -> [String] {
        html.matches(of: /src="([a-z-]+:[^"]*)"/).compactMap { match in
            let url = URL(string: String(match.1).replacingOccurrences(of: "&amp;", with: "&"))
            return url.flatMap(SealedPictures.request).map { request in
                #expect(request.item == item)
                #expect(request.version == 3)
                return request.address.absoluteString
            }
        }
    }

    @Test func aPictureAtAWebAddressIsDrawnFromTheApp() {
        let (html, addresses) = rewrite(#"<p>One</p><IMG alt="a" SRC="https://example.com/a.png" width=40><img src='http://example.com/b.gif'>"#)

        #expect(addresses == ["https://example.com/a.png", "http://example.com/b.gif"])
        #expect(requested(in: html) == addresses)
        #expect(html.hasPrefix(#"<p>One</p><IMG alt="a" width=40 src="\#(SealedPictures.scheme):"#))
        #expect(!html.localizedCaseInsensitiveContains("src=\"http"))
        #expect(!html.contains("src='http"))
    }

    @Test func aLazyPictureIsDrawnFromItsDataSource() {
        let (html, addresses) = rewrite(#"<img data-src="https://example.com/lazy.png"><img src="" data-src="https://example.com/empty.png">"#)

        #expect(addresses == ["https://example.com/lazy.png", "https://example.com/empty.png"])
        #expect(requested(in: html) == addresses)
    }

    @Test func everySourceSetIsDropped() {
        let (html, addresses) = rewrite("""
            <picture><source srcset="https://example.com/wide.webp 2x" type="image/webp" media="(min-width: 1px)">\
            <img src="https://example.com/a.png" srcset="https://example.com/a2.png 2x, https://example.com/a3.png 3x"></picture>
            """)

        #expect(addresses == ["https://example.com/a.png"])
        #expect(!html.contains("srcset"))
        #expect(html.contains(#"<source type="image/webp" media="(min-width: 1px)">"#))
    }

    @Test func aQueryIsReadWithItsCharacterReferences() {
        let (html, addresses) = rewrite(#"<img src="https://example.com/a.png?w=1&amp;h=2&#38;fit=crop">"#)

        #expect(addresses == ["https://example.com/a.png?w=1&h=2&fit=crop"])
        #expect(requested(in: html) == addresses)
    }

    @Test func aPictureTheDocumentHoldsOrCannotReachIsLeftAsWritten() {
        let written = #"<img src="data:image/gif;base64,R0lGOD"><img src="images/a.png"><img src="//example.com/a.png">"#
        let (html, addresses) = rewrite(written)

        #expect(addresses.isEmpty)
        #expect(html == written)
    }

    @Test func textThatOnlyLooksLikeAPictureIsLeftAlone() {
        let written = #"<!-- <img src="https://example.com/a.png"> --><script>let s = '<img src="https://example.com/b.png">'</script>"#
        let (html, addresses) = rewrite(written)

        #expect(addresses.isEmpty)
        #expect(html == written)
    }

    /// Shift_JIS lead bytes such as 0x81 are neither UTF-8 nor Windows-1252, so a rewrite that read the document as text
    /// first would have nothing to give the page.
    @Test func aDocumentInAnotherEncodingKeepsItsBytes() throws {
        let words = "日本語の記事、です。"
        let written = try #require("<p>\(words)</p><img alt=\"写真\" src=\"https://example.com/a.png\">".data(using: .shiftJIS))
        try #require(String(data: written, encoding: .utf8) == nil)
        try #require(String(data: written, encoding: .windowsCP1252) == nil)

        let result = SealedPictureRewrite.rewrite(written, item: item, version: 3)
        let html = try #require(String(data: result.html, encoding: .shiftJIS))

        #expect(result.addresses.map(\.absoluteString) == ["https://example.com/a.png"])
        #expect(html.hasPrefix("<p>\(words)</p><img alt=\"写真\" src=\"\(SealedPictures.scheme):"))
        #expect(requested(in: html) == ["https://example.com/a.png"])
    }
}
