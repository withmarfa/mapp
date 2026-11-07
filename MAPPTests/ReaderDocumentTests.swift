@testable import MAPP
import Foundation
import Testing
import WebKit

@Suite(.hangLimit)
@MainActor struct ReaderDocumentTests {
    private func article(_ html: String = "<p>Words.</p>", lang: String? = "en", dir: PageAnalysis.Article.Direction? = nil) -> PageAnalysis.Article {
        PageAnalysis.Article(html: html, language: lang, direction: dir)
    }

    @Test func theArticleIsTheDocumentsBody() {
        let document = ReaderDocument.html(for: article("<p>Seven miles.</p>"))
        #expect(document.contains("<article><p>Seven miles.</p></article>"))
        #expect(document.contains("lang=\"en\"") && !document.contains("dir="))
    }

    @Test func aRightToLeftArticleSetsTheDocumentsDirection() {
        let document = ReaderDocument.html(for: article(lang: "ar", dir: .rtl))
        #expect(document.contains("dir=\"rtl\"") && document.contains("lang=\"ar\""))
    }

    @Test func aDocumentThatNamedNoLanguageSetsNone() {
        #expect(!ReaderDocument.html(for: article(lang: nil)).contains("lang="))
    }

    @Test func theDocumentRunsNoScriptEvenWhereThePageAllowsThem() async throws {
        let hostile = article("<p>Words.</p><script>window.ran = true</script><img src=\"data:image/gif;base64,R0lGODlhAQABAAAAACw=\" onerror=\"window.ran = true\">")
        let page = try await SealedWebPage.make(runsScripts: true)
        try await page.show(Data(ReaderDocument.html(for: hostile).utf8), encoding: .utf8)
        #expect(try await page.page.callJavaScript("return window.ran === undefined") as? Bool == true)
    }

    @Test func thePicturesAreTheAppsToGiveLikeAnyOtherDocuments() throws {
        let item = ItemID("item")
        let document = ReaderDocument.html(for: article("<figure class=\"mapp-lead\"><img src=\"https://example.com/lead.jpg\"></figure>"))
        let rewritten = SealedPictureRewrite.rewrite(Data(document.utf8), item: item, version: 3)
        #expect(rewritten.addresses == [URL(string: "https://example.com/lead.jpg")!] && rewritten.encoding == .utf8)
        let html = String(decoding: rewritten.html, as: UTF8.self)
        #expect(!html.contains("https://example.com/lead.jpg\"") && html.contains("\(SealedPictures.scheme):"))
    }

    @Test func theReaderLookIsAppliedToTheDocument() async throws {
        let page = try await SealedWebPage.make(runsScripts: false)
        try await page.show(
            Data(ReaderDocument.html(for: article("<h2>Heading</h2><p>Words.</p>")).utf8), encoding: .utf8,
            look: SourceLook(mode: .reader, isMail: false, page: PageStyle()))
        let font = try await page.page.callJavaScript("return getComputedStyle(document.querySelector('p')).fontFamily") as? String
        #expect(font?.contains("New York") == true)
    }
}
