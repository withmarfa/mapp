@testable import MAPP
import Foundation
import Testing

/// The analysis runs Mozilla's Readability over a copy of the document in a sealed page of its own, so each test here
/// loads a real document and reads what the script found.
@Suite(.hangLimit)
@MainActor struct PageAnalyzerTests {
    private let title = "The cliff path that teaches you to slow down"

    private static let sentences = [
        "Seven miles of chalk, two steep climbs and a sea that changes colour by the hour, make this a walk to take slowly.",
        "Start at the cove car park and take the steps up behind the visitor centre, where the crowds thin out within ten minutes.",
        "By the first waymark you will mostly have the path to yourself, apart from the gulls, the sheep and the odd climber.",
        "The second climb is the steeper one, but the view back along the coast, in the low evening light, repays every step.",
        "Bring water, a coat and a torch, because the last mile home is unlit and the cliff edge is closer than it looks.",
    ]

    private func prose(_ paragraphs: Int = 5) -> String {
        (0..<paragraphs).map { "<p>\(Self.sentences[$0 % Self.sentences.count])</p>" }.joined(separator: "\n")
    }

    /// Paragraphs long enough to count as an article without an `article` element around them, as Readability's own
    /// check of a page weighs them.
    private func longProse(_ paragraphs: Int = 6) -> String {
        (0..<paragraphs).map { "<p>\(Self.sentences[$0 % Self.sentences.count]) \(Self.sentences[($0 + 1) % Self.sentences.count])</p>" }
            .joined(separator: "\n")
    }

    private func page(body: String? = nil, head: String = "", lang: String = "en", dir: String = "", documentTitle: String? = nil) -> String {
        """
        <!doctype html><html lang="\(lang)" \(dir)><head><meta charset="utf-8"><title>\(documentTitle ?? "\(title) | Slow Walks")</title>\(head)</head><body>
        <nav><a href="/">Slow Walks Home</a> <a href="/routes">Routes</a> <a href="/maps">Maps</a></nav>
        <article><h1>\(title)</h1>\(body ?? prose())</article>
        <footer>Subscribe to the newsletter</footer></body></html>
        """
    }

    private func analyse(_ html: String, title: String? = nil, encoding: String.Encoding? = nil) async throws -> PageAnalysis {
        try await PageAnalyzer.analyze(Data(html.utf8), encoding: encoding, title: title ?? self.title)
    }

    // MARK: Finding the article

    @Test func theArticleIsFoundWithoutThePageAroundIt() async throws {
        let article = try #require(try await analyse(page()).article)
        #expect(article.html.contains("Seven miles of chalk"))
        #expect(!article.html.contains("Subscribe to the newsletter") && !article.html.contains("Slow Walks Home"))
        #expect(article.language == "en")
    }

    @Test func aHeadingThatRepeatsTheItemsTitleIsDropped() async throws {
        // The document's own title differs, so Readability keeps the heading and the cleanup is what drops it.
        let html = page(documentTitle: "Slow Walks routes, maps and the newsletter of an unhurried coast")
        let article = try #require(try await analyse(html).article)
        #expect(!article.html.contains("slow down"), "the title is MAPP's, above the page")
        let other = try #require(try await analyse(html, title: "Something else").article)
        #expect(other.html.contains("slow down"), "a heading that is not the title stays")
    }

    @Test func aHeadingsPermalinkAndEscapedQuotesAreCleaned() async throws {
        let body = prose() + "<h2 id=\"why\">Why it matters<a href=\"#why\">#</a></h2><p>It said \\\"I don't know\\\" and stopped, then walked on.</p><pre>keep \\\"this\\\"</pre>"
        let html = try #require(try await analyse(page(body: body)).article).html
        #expect(html.contains("Why it matters") && !html.contains(">#<"))
        #expect(html.contains("\"I don't know\"") && !html.contains("\\\"I don"))
        #expect(html.contains("keep \\\"this\\\""), "code is left as written")
    }

    @Test func aPicturesFixedSizeIsLeftToTheStyles() async throws {
        let body = "<figure><img src=\"https://example.com/a.jpg\" width=\"1200\" height=\"800\"></figure>" + prose()
        let html = try #require(try await analyse(page(body: body)).article).html
        #expect(html.contains("example.com/a.jpg") && !html.contains("width=") && !html.contains("height="))
    }

    @Test func theArticleHoldsNoScriptOrEventHandler() async throws {
        let body = prose() + "<p onclick=\"steal()\" onmouseover=\"x()\">Click here to read more of the walk.</p><a href=\"javascript:steal()\">go</a>"
        let html = try #require(try await analyse(page(body: body)).article).html
        #expect(html.contains("Click here") && !html.contains("onclick") && !html.contains("onmouseover") && !html.contains("javascript:"))
    }

    @Test func theFirstPictureBeforeAnyTextIsTheLeadPicture() async throws {
        let lead = "<figure><img src=\"https://example.com/lead.jpg\"><figcaption>The path west of Lulworth.</figcaption></figure>"
        let withLead = try #require(try await analyse(page(body: lead + prose())).article).html
        #expect(withLead.contains("mapp-lead"))
        let later = try #require(try await analyse(page(body: prose() + lead)).article).html
        #expect(!later.contains("mapp-lead"), "a picture in the middle of the text is part of it")
    }

    // MARK: Not an article

    @Test func aPageOfLinksAndSnippetsIsNoArticle() async throws {
        let products = (1...40).map { "<li><a href=\"/p/\($0)\">Oak worktop \($0)</a> from £\($0 * 10)</li>" }.joined()
        let html = "<html><head><title>Shop</title></head><body><nav><a href=\"/\">Home</a></nav><ul>\(products)</ul></body></html>"
        #expect(try await analyse(html).article == nil)
    }

    @Test func aPageWithTooLittleTextIsNoArticle() async throws {
        let analysis = try await analyse(page(body: "<p>Seven miles of chalk and two steep climbs, walked slowly, in the evening.</p>"))
        #expect(analysis.article == nil && !analysis.offersReader)
    }

    @Test func anEmptyDocumentIsNothing() async throws {
        #expect(try await analyse("") == .none)
    }

    @Test func onlyATableOfDataIsMarkedForTheReadersTableStyling() async throws {
        let data = "<table><tr><th>Stage</th><th>Miles</th></tr>" +
            (1...6).map { "<tr><td>Stage \($0)</td><td>\($0 * 2)</td></tr>" }.joined() + "</table>"
        let layout = "<table role=\"presentation\"><tr><td>" + longProse(2) + "</td></tr><tr><td>" + longProse(2) + "</td></tr></table>"
        let article = try #require(try await analyse(page(body: longProse(4) + data + layout)).article)
        #expect(article.html.contains("class=\"mapp-data\""), "a table of rows and columns keeps its grid")
        #expect(article.html.components(separatedBy: "<table").count == 3)
        #expect(article.html.components(separatedBy: "mapp-data").count == 2, "a layout table is not styled as data")
    }

    // MARK: Documents that go wrong

    @Test func theDocumentsOwnScriptsAreNotRunToFindTheArticle() async throws {
        // A script that would empty the page, then one that throws: neither runs, so the article is as written.
        let head = "<script>document.body.innerHTML = '';</script><script>throw new Error('broken');</script>"
        let article = try #require(try await analyse(page(head: head)).article)
        #expect(article.html.contains("Seven miles of chalk") && !article.html.contains("broken"))
    }

    @Test func malformedMarkupStillGivesTheArticle() async throws {
        let body = "<p>Seven miles of <b>chalk, <i>two steep climbs</p><div><p>and a sea that changes colour by the hour, so walk slowly, " +
            "and take the steps up behind the visitor centre, where the crowds thin out within ten minutes. " +
            "By the first waymark you will mostly have the path to yourself, apart from the gulls, the sheep and the odd climber. " +
            "The second climb is the steeper one, but the view back along the coast repays every step. <table><td>Bring water</p></div>" + prose()
        let analysis = try await analyse(page(body: body))
        #expect(analysis.article?.html.contains("Bring water") == true)
    }

    @Test func aPageInAnotherEncodingIsReadInIt() async throws {
        let html = page(body: prose() + "<p>Afterwards, a café on the quay serves crème brûlée until late in the evening, every day.</p>")
            .replacingOccurrences(of: "<meta charset=\"utf-8\">", with: "<meta charset=\"windows-1252\">")
        let data = try #require(html.data(using: .windowsCP1252))
        let article = try #require(try await PageAnalyzer.analyze(data, title: title).article)
        #expect(article.html.contains("café") && article.html.contains("crème brûlée"))
    }

    @Test func aRightToLeftArticleKeepsItsLanguageAndDirection() async throws {
        let sentence = "هذا نص عربي طويل يصف مسارا على طول الجرف الأبيض، ويستغرق السير فيه ساعات طويلة عند الغروب، فاحمل الماء والمعطف معك."
        let body = (0..<6).map { _ in "<p>\(sentence)</p>" }.joined()
        let article = try #require(try await analyse(page(body: body, lang: "ar", dir: "dir=\"rtl\"")).article)
        #expect(article.direction == .rtl && article.language == "ar")
        #expect(article.html.contains("مسارا"))
    }

    @Test func aLongPageIsGivenUpOnRatherThanReadSlowly() async throws {
        let many = String(repeating: "<div><span>x</span></div>", count: 600)
        let analysis = try await PageAnalyzer.analyze(Data(page(body: prose() + many).utf8), title: title, elementLimit: 200)
        #expect(analysis.article == nil)
    }

    @Test func aPageThatTakesTooLongIsNoArticle() async throws {
        let started = ContinuousClock.now
        let analysis = try await PageAnalyzer.analyze(Data(page().utf8), title: title, limit: .milliseconds(1))
        #expect(analysis == .none)
        #expect(ContinuousClock.now - started < .seconds(5), "the answer does not wait for the page")
    }

    @Test func aCancelledAnalysisThrowsInsteadOfAnswering() async throws {
        let data = Data(page().utf8)
        let title = title
        let task = Task { try await PageAnalyzer.analyze(data, title: title) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    // MARK: Mail

    private let mailColumn = """
        <table role="presentation" width="100%" bgcolor="#eeeeee"><tr><td align="center">
        <table role="presentation" width="600" cellpadding="0" cellspacing="0"><tr><td style="background:#ffffff">
        <h1 style="font-size:20px">Autumn offcuts</h1>
        """

    @Test func aTableLaidOutAtAFixedWidthIsAMail() async throws {
        let html = "<html><body>\(mailColumn)\(prose())<p><a href=\"https://example.com/u\">Unsubscribe</a></p></td></tr></table></td></tr></table></body></html>"
        #expect(try await analyse(html).isMail)
    }

    @Test func aFixedWidthInStyleCountsAsMuchAsOneInAnAttribute() async throws {
        let html = "<html><body><table style=\"width:100%;max-width:560px\"><tr><td>\(prose())</td></tr></table></body></html>"
        #expect(try await analyse(html).isMail)
    }

    @Test func aWebPageIsNotAMailEvenWithAFixedWidthColumn() async throws {
        #expect(try await analyse(page()).isMail == false)
        let column = "<html><body><div style=\"max-width:600px;margin:0 auto\">\(prose())</div></body></html>"
        #expect(try await analyse(column).isMail == false, "a column with no layout table is not a mail's")
    }

    @Test func aTableThatSpansThePageIsNotAMail() async throws {
        let html = "<html><body><table width=\"100%\"><tr><td>\(prose())</td></tr></table></body></html>"
        #expect(try await analyse(html).isMail == false)
    }

    @Test func aMailCanAlsoHaveAnArticle() async throws {
        let html = "<html><body>\(mailColumn)\(longProse())</td></tr></table></td></tr></table></body></html>"
        let analysis = try await analyse(html)
        #expect(analysis.isMail && analysis.offersReader)
    }
}
