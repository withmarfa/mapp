@testable import MAPP
import Foundation
import Testing
import WebKit

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

    private func analyze(_ html: String, title: String? = nil, encoding: String.Encoding? = nil) async throws -> PageAnalysis {
        try await PageAnalyzer.analyze(Data(html.utf8), encoding: encoding, title: title ?? self.title)
    }

    // MARK: Finding the article

    @Test func theArticleIsFoundWithoutThePageAroundIt() async throws {
        let article = try #require(try await analyze(page()).article)
        #expect(article.html.contains("Seven miles of chalk"))
        #expect(!article.html.contains("Subscribe to the newsletter") && !article.html.contains("Slow Walks Home"))
        #expect(article.language == "en")
    }

    @Test func aHeadingThatRepeatsTheItemsTitleIsDropped() async throws {
        // The document's own title differs, so Readability keeps the heading and the cleanup is what drops it.
        let html = page(documentTitle: "Slow Walks routes, maps and the newsletter of an unhurried coast")
        let article = try #require(try await analyze(html).article)
        #expect(!article.html.contains("slow down"), "the title is MAPP's, above the page")
        let other = try #require(try await analyze(html, title: "Something else").article)
        #expect(other.html.contains("slow down"), "a heading that is not the title stays")
    }

    @Test func aHeadingsPermalinkAndEscapedQuotesAreCleaned() async throws {
        let body = prose() + "<h2 id=\"why\">Why it matters<a href=\"#why\">#</a></h2><p>It said \\\"I don't know\\\" and stopped, then walked on.</p><pre>keep \\\"this\\\"</pre>"
        let html = try #require(try await analyze(page(body: body)).article).html
        #expect(html.contains("Why it matters") && !html.contains(">#<"))
        #expect(html.contains("\"I don't know\"") && !html.contains("\\\"I don"))
        #expect(html.contains("keep \\\"this\\\""), "code is left as written")
    }

    @Test func aPicturesFixedSizeIsLeftToTheStyles() async throws {
        let body = "<figure><img src=\"https://example.com/a.jpg\" width=\"1200\" height=\"800\"></figure>" + prose()
        let html = try #require(try await analyze(page(body: body)).article).html
        #expect(html.contains("example.com/a.jpg") && !html.contains("width=") && !html.contains("height="))
    }

    @Test func theArticleHoldsNoScriptOrEventHandler() async throws {
        let body = prose() + "<p onclick=\"steal()\" onmouseover=\"x()\">Click here to read more of the walk.</p><a href=\"javascript:steal()\">go</a>"
        let html = try #require(try await analyze(page(body: body)).article).html
        #expect(html.contains("Click here") && !html.contains("onclick") && !html.contains("onmouseover") && !html.contains("javascript:"))
    }

    @Test func theFirstPictureBeforeAnyTextIsTheLeadPicture() async throws {
        let lead = "<figure><img src=\"https://example.com/lead.jpg\"><figcaption>The path west of Lulworth.</figcaption></figure>"
        let withLead = try #require(try await analyze(page(body: lead + prose())).article).html
        #expect(withLead.contains("mapp-lead"))
        let later = try #require(try await analyze(page(body: prose() + lead)).article).html
        #expect(!later.contains("mapp-lead"), "a picture in the middle of the text is part of it")
    }

    // MARK: Not an article

    @Test func aPageOfLinksAndSnippetsIsNoArticle() async throws {
        let products = (1...40).map { "<li><a href=\"/p/\($0)\">Oak worktop \($0)</a> from £\($0 * 10)</li>" }.joined()
        let html = "<html><head><title>Shop</title></head><body><nav><a href=\"/\">Home</a></nav><ul>\(products)</ul></body></html>"
        #expect(try await analyze(html).article == nil)
    }

    @Test func aPageWithTooLittleTextIsNoArticle() async throws {
        let analysis = try await analyze(page(body: "<p>Seven miles of chalk and two steep climbs, walked slowly, in the evening.</p>"))
        #expect(analysis.article == nil && !analysis.offersReader)
    }

    @Test func anEmptyDocumentIsNothing() async throws {
        #expect(try await analyze("") == .none)
    }

    @Test func onlyATableOfDataIsMarkedForTheReadersTableStyling() async throws {
        let data = "<table><tr><th>Stage</th><th>Miles</th></tr>" +
            (1...6).map { "<tr><td>Stage \($0)</td><td>\($0 * 2)</td></tr>" }.joined() + "</table>"
        let layout = "<table role=\"presentation\"><tr><td>" + longProse(2) + "</td></tr><tr><td>" + longProse(2) + "</td></tr></table>"
        let article = try #require(try await analyze(page(body: longProse(4) + data + layout)).article)
        #expect(article.html.contains("class=\"mapp-data\""), "a table of rows and columns keeps its grid")
        #expect(article.html.components(separatedBy: "<table").count == 3)
        #expect(article.html.components(separatedBy: "mapp-data").count == 2, "a layout table is not styled as data")
    }

    // MARK: Documents that go wrong

    @Test func theDocumentsOwnScriptsAreNotRunToFindTheArticle() async throws {
        // A script that would empty the page, then one that throws: neither runs, so the article is as written.
        let head = "<script>document.body.innerHTML = '';</script><script>throw new Error('broken');</script>"
        let article = try #require(try await analyze(page(head: head)).article)
        #expect(article.html.contains("Seven miles of chalk") && !article.html.contains("broken"))
    }

    @Test func malformedMarkupStillGivesTheArticle() async throws {
        let body = "<p>Seven miles of <b>chalk, <i>two steep climbs</p><div><p>and a sea that changes colour by the hour, so walk slowly, " +
            "and take the steps up behind the visitor centre, where the crowds thin out within ten minutes. " +
            "By the first waymark you will mostly have the path to yourself, apart from the gulls, the sheep and the odd climber. " +
            "The second climb is the steeper one, but the view back along the coast repays every step. <table><td>Bring water</p></div>" + prose()
        let analysis = try await analyze(page(body: body))
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
        let article = try #require(try await analyze(page(body: body, lang: "ar", dir: "dir=\"rtl\"")).article)
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

    // MARK: Documents that name their elements after the page's methods

    /// A form's controls, and a document's images, objects, embeds and frames, are reachable by their `name` as properties
    /// of the form or the document, and they win over the built-in ones: `form.children` is then a control.
    private let loopingForms = "<html><head><title>The cliff path</title></head><body><fieldset form=\"f\" name=\"children\"><form id=\"f\">"

    @MainActor private final class ScriptRun {
        var answer: Any?
        var finished = false
    }

    private func runningTheScript(on html: String) async throws -> (answer: Any?, answeredAgain: Bool) {
        let sealed = try await SealedWebPage.make(runsScripts: false)
        try await sealed.show(Data(html.utf8))
        let readability = try #require(PageAnalyzer.readability)
        let page = sealed.page
        let title = title
        let run = ScriptRun()
        let call = Task {
            run.answer = try? await page.callJavaScript(
                readability + PageAnalyzer.script, arguments: ["title": title, "limit": PageAnalyzer.maxElements], contentWorld: SealedWebPage.world)
            run.finished = true
        }
        defer { call.cancel() }
        let answeredInTime = await eventually(within: .seconds(20)) { run.finished }
        // A process still busy with the script answers nothing else.
        var again = false
        if answeredInTime { again = (try? await page.callJavaScript("return 1")) as? Int == 1 }
        return (run.answer, again)
    }

    @Test func aFormThatHidesItsChildrenDoesNotKeepThePageBusy() async throws {
        let html = loopingForms + longProse() + "</form></fieldset></body></html>"
        let (answer, answeredAgain) = try await runningTheScript(on: html)
        #expect(answeredAgain, "the script ended; the page's process is free")
        #expect(PageAnalysis(javaScript: answer).article != nil)
        let analysis = try await analyze(html)
        #expect(analysis.article?.html.contains("Seven miles of chalk") == true, "the analysis answered with the article, not with its time limit")
    }

    @Test func aMailInsideAFormThatHidesItsChildrenIsStillAMail() async throws {
        let html = "<html><body><form><input type=\"hidden\" name=\"children\"><input type=\"hidden\" name=\"parentElement\">" +
            "\(mailColumn)\(prose())</td></tr></table></td></tr></table></form></body></html>"
        let (_, answeredAgain) = try await runningTheScript(on: html)
        #expect(answeredAgain)
        #expect(try await analyze(html).isMail)
    }

    @Test func elementsNamedAfterTheDocumentsMethodsDoNotBreakTheAnalysis() async throws {
        let names = ["cloneNode", "querySelectorAll", "querySelector", "createElement", "createTreeWalker", "createRange", "body", "documentElement", "getElementsByTagName"]
        let clobbers = names.map { "<img name=\"\($0)\" width=\"1\" height=\"1\" src=\"https://example.com/\($0).gif\">" }.joined()
        let formNames = ["children", "parentElement", "matches", "closest", "getAttribute", "getAttributeNames", "removeAttribute", "querySelectorAll", "style", "classList"]
        let controls = formNames.map { "<input type=\"hidden\" name=\"\($0)\" value=\"1\">" }.joined()
        let body = clobbers + "<form>" + controls + "</form>" + prose()
        let article = try #require(try await analyze(page(body: body)).article)
        #expect(article.html.contains("Seven miles of chalk"))
        #expect(!article.html.contains(" name=\""), "a name stays out of the article, where it would hide a property of its form or document")
    }

    @Test func aLegacyAnchorKeepsItsName() async throws {
        let article = try #require(try await analyze(page(body: "<p><a name=\"top\"></a>" + Self.sentences[0] + "</p>" + prose())).article)
        #expect(article.html.contains("name=\"top\""))
    }

    // MARK: What the cleaner leaves out of the article

    @Test func documentMarkupNeverReachesTheArticle() async throws {
        let shadow = "<div><template shadowrootmode=\"open\"></template><template shadowrootmode=\"open\"><style>:host{position:fixed;inset:0}</style>" +
            "<link rel=\"stylesheet\" href=\"https://example.com/a.css\"><iframe src=\"about:blank\"></iframe></template></div>"
        let body = prose() + shadow + "<meta http-equiv=\"refresh\" content=\"0;url=https://example.com/\"><base href=\"https://evil.example/\">" +
            "<form action=\"https://evil.example/\"><input name=\"q\"><button>Go</button></form>" +
            "<video src=\"https://example.com/v.mp4\" controls></video><audio src=\"https://example.com/a.mp3\" controls></audio>" +
            "<svg style=\"position:fixed;inset:0\"><style>svg{position:fixed}</style><text>x</text></svg>"
        let html = try #require(try await analyze(page(body: body)).article).html
        for markup in ["<template", "<style", "<link", "<iframe", "<meta", "<base", "<form", "<input", "<button", "<video", "<audio", "position"] {
            #expect(!html.contains(markup), "\(markup) is in the article")
        }
        #expect(html.contains("Seven miles of chalk"))
    }

    @Test func aLinkOrPictureGoesToAnAddressOnlyIfItsSchemeIsOneThatIsSafeToShow() async throws {
        let links = [
            "<a href=\"javascript:steal(1)\">plain</a>", "<a href=\"java&#9;script:steal(2)\">tab</a>", "<a href=\"&#10;JaVaScRiPt:steal(3)\">newline</a>",
            "<a href=\" \u{1}javascript:steal(4)\">control</a>", "<a href=\"vbscript:steal(5)\">vb</a>", "<a href=\"data:text/html,steal(6)\">data</a>",
            "<a href=\"file:///etc/hosts\">file</a>", "<svg><a xlink:href=\"javascript:steal(7)\"><text>x</text></a></svg>",
            "<img src=\"javascript:steal(8)\">", "<img src=\"data:text/html,steal(9)\">",
        ].joined()
        let fine = "<a href=\"https://example.com/ok\">fine</a><a href=\"mailto:a@example.com\">mail</a><a href=\"#part\">part</a><a href=\"/relative\">relative</a>" +
            "<img src=\"data:image/png;base64,iVBORw0KGgo=\"><img src=\"https://example.com/p.png\">"
        let html = try #require(try await analyze(page(body: prose() + "<p>" + links + fine + "</p>")).article).html
        #expect(!html.contains("steal"), "an address with a script scheme, however it is spelled, is gone")
        #expect(!html.contains("file:") && !html.contains("data:text"))
        for kept in ["https://example.com/ok", "mailto:a@example.com", "#part", "/relative", "data:image/png", "https://example.com/p.png"] {
            #expect(html.contains(kept), "\(kept)")
        }
    }

    // MARK: Mail

    private let mailColumn = """
        <table role="presentation" width="100%" bgcolor="#eeeeee"><tr><td align="center">
        <table role="presentation" width="600" cellpadding="0" cellspacing="0"><tr><td style="background:#ffffff">
        <h1 style="font-size:20px">Autumn offcuts</h1>
        """

    @Test func aTableLaidOutAtAFixedWidthIsAMail() async throws {
        let html = "<html><body>\(mailColumn)\(prose())<p><a href=\"https://example.com/u\">Unsubscribe</a></p></td></tr></table></td></tr></table></body></html>"
        #expect(try await analyze(html).isMail)
    }

    @Test func aFixedWidthInStyleCountsAsMuchAsOneInAnAttribute() async throws {
        let html = "<html><body><table style=\"width:100%;max-width:560px\"><tr><td>\(prose())</td></tr></table></body></html>"
        #expect(try await analyze(html).isMail)
    }

    @Test func aWebPageIsNotAMailEvenWithAFixedWidthColumn() async throws {
        #expect(try await analyze(page()).isMail == false)
        let column = "<html><body><div style=\"max-width:600px;margin:0 auto\">\(prose())</div></body></html>"
        #expect(try await analyze(column).isMail == false, "a column with no layout table is not a mail's")
    }

    @Test func aTableThatSpansThePageIsNotAMail() async throws {
        let html = "<html><body><table width=\"100%\"><tr><td>\(prose())</td></tr></table></body></html>"
        #expect(try await analyze(html).isMail == false)
    }

    @Test func aMailCanAlsoHaveAnArticle() async throws {
        let html = "<html><body>\(mailColumn)\(longProse())</td></tr></table></td></tr></table></body></html>"
        let analysis = try await analyze(html)
        #expect(analysis.isMail && analysis.offersReader)
    }

    @Test func aMailLaidOutAsSiblingTablesOfOneWidthIsOneColumn() async throws {
        // The usual template: a header, a body and a footer, each its own table of the same width. No one of them holds
        // nine tenths of the text.
        let header = "<table width=\"600\"><tr><td><p>\(Self.sentences[0])</p></td></tr></table>"
        let content = "<table width=\"600\"><tr><td>\(prose(4))</td></tr></table>"
        let footer = "<table width=\"600\"><tr><td><p>\(Self.sentences[1])</p></td></tr></table>"
        let html = "<html><body><table width=\"100%\" bgcolor=\"#eeeeee\"><tr><td align=\"center\">\(header)\(content)\(footer)</td></tr></table></body></html>"
        #expect(try await analyze(html).isMail)
        let mixed = "<html><body><table width=\"100%\"><tr><td align=\"center\">\(header)\(content)<table width=\"400\"><tr><td>\(prose(4))</td></tr></table></td></tr></table></body></html>"
        #expect(try await analyze(mixed).isMail == false, "tables of different widths are not one template")
    }

    @Test func anEssayInATableBesideAPictureIsNotAMail() async throws {
        // A page from the nineties web: a table with a picture down the side and the essay in a table of 435 pixels.
        let html = """
            <html><head><title>\(title)</title></head><body bgcolor="#ffffff" text="#000000"><table border="0" cellspacing="0" cellpadding="0"><tr valign="top">
            <td width="335"><img src="https://example.com/side.gif" width="69" height="357"></td>
            <td><img src="https://example.com/banner.gif" width="410" height="45"><br><br>
            <table border="0" cellspacing="0" cellpadding="0" width="435"><tr valign="top"><td width="435">\(longProse())</td></tr></table></td></tr></table></body></html>
            """
        let analysis = try await analyze(html)
        #expect(analysis.isMail == false)
        #expect(analysis.offersReader, "so the essay opens in Reader")
    }
}
