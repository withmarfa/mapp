@testable import MarfaMac
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

    @Test func theArticleHoldsNoScriptOrEventHandler() async throws {
        let body = prose() + "<p onclick=\"steal()\" onmouseover=\"x()\">Click here to read more of the walk.</p><a href=\"javascript:steal()\">go</a>"
        let html = try #require(try await analyze(page(body: body)).article).html
        #expect(html.contains("Click here") && !html.contains("onclick") && !html.contains("onmouseover") && !html.contains("javascript:"))
    }

    // MARK: Documents that go wrong

    @Test func theDocumentsOwnScriptsAreNotRunToFindTheArticle() async throws {
        // A script that would empty the page, then one that throws: neither runs, so the article is as written.
        let head = "<script>document.body.innerHTML = '';</script><script>throw new Error('broken');</script>"
        let article = try #require(try await analyze(page(head: head)).article)
        #expect(article.html.contains("Seven miles of chalk") && !article.html.contains("broken"))
    }

    @Test func aPageInAnotherEncodingIsReadInIt() async throws {
        let html = page(body: prose() + "<p>Afterwards, a café on the quay serves crème brûlée until late in the evening, every day.</p>")
            .replacingOccurrences(of: "<meta charset=\"utf-8\">", with: "<meta charset=\"windows-1252\">")
        let data = try #require(html.data(using: .windowsCP1252))
        let article = try #require(try await PageAnalyzer.analyze(data, title: title).article)
        #expect(article.html.contains("café") && article.html.contains("crème brûlée"))
    }

    @Test func aLongPageIsGivenUpOnRatherThanReadSlowly() async throws {
        let many = String(repeating: "<div><span>x</span></div>", count: 600)
        let analysis = try await PageAnalyzer.analyze(Data(page(body: prose() + many).utf8), title: title, elementLimit: 200)
        #expect(analysis.article == nil)
    }

    /// The same page gives an article with no limit (`theArticleIsFoundWithoutThePageAroundIt`), so `.none` here is the limit's.
    /// The wall clock is not measured: a busy machine moves it.
    @Test func aPageThatTakesTooLongIsNoArticle() async throws {
        let analysis = try await PageAnalyzer.analyze(Data(page().utf8), title: title, limit: .milliseconds(1))
        #expect(analysis == .none)
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

    private let mailColumn = """
        <table role="presentation" width="100%" bgcolor="#eeeeee"><tr><td align="center">
        <table role="presentation" width="600" cellpadding="0" cellspacing="0"><tr><td style="background:#ffffff">
        <h1 style="font-size:20px">Autumn offcuts</h1>
        """

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

    // MARK: Documents built to run long

    /// Nothing ends a script once it runs, so what stops these is that they never reach the slow path. A failure here
    /// leaves a web process spinning until the test host quits.
    @Test(arguments: LongDocument.allCases) func aDocumentBuiltToRunLongStillFindsItsArticle(_ document: LongDocument) async throws {
        let html = page(body: prose(12) + document.body, head: document.head, documentTitle: document.title)
        let article = try #require(try await analyze(html).article)
        #expect(article.html.contains("Seven miles of chalk"))
    }

    // MARK: Markup that changes when it is parsed again

    /// The live elements a parser finds in the article, once it is in Reader's document, that the cleaner removes.
    private func removedMarkup(in article: PageAnalysis.Article) async throws -> String? {
        let document = SealedPictureRewrite.rewrite(Data(ReaderDocument.html(for: article).utf8), item: ItemID("i"), version: 1)
        // A page with scripts on reads a noscript as text, so a Web Page's Reader is the parse that finds the most.
        let sealed = try await SealedWebPage.make(runsScripts: true)
        try await sealed.show(document.html, encoding: document.encoding)
        return try await sealed.page.callJavaScript("""
            const found = document.querySelectorAll('body :is(script, style, link, iframe, object, embed, template, meta, base, video, audio, input, select, textarea, button, form), body [onerror], body [style]');
            return Array.from(found).map(e => e.outerHTML.slice(0, 80)).join(' ');
            """, contentWorld: SealedWebPage.world) as? String
    }

    @Test(arguments: [
        "<form><math><mtext></form><form><mglyph><xmp></math><style>article{position:fixed}</style><meta http-equiv=refresh content=\"0;url=https://example.com/\"><iframe srcdoc=x></iframe>",
        "<form><math><mtext></form><form><mglyph><noembed></math><style>article{position:fixed}</style>",
        "<form><math><mtext></form><form><mglyph><noframes></math><style>article{position:fixed}</style>",
        "<svg><title><xmp></svg><style>article{position:fixed}</style></xmp></title></svg>",
        "<math><mtext><table><mglyph><xmp></math><style>article{position:fixed}</style>",
        "<svg><plaintext></svg><style>article{position:fixed}</style>",
        "<form><math><mtext></form><form><mglyph><style></math><iframe srcdoc=x></iframe>",
        "<svg></p><style><a title=\"</style><iframe srcdoc=x></iframe>\">",
        "<math><mtext><table><mglyph><style><!--</style><iframe srcdoc=x></iframe>-->",
        "<table><caption><svg><title><table><caption><title><style><a title=\"</style><iframe srcdoc=x></iframe>\">",
        "<svg><desc><noscript><p title=\"</noscript><iframe srcdoc=x></iframe>\">",
        "<select><template><style><!--</style><a title=\"--><iframe srcdoc=x></iframe>\">",
    ]) func markupThatChangesWhenParsedAgainNeverReachesReader(_ markup: String) async throws {
        // Long paragraphs on both sides, so Readability keeps the block that holds the markup.
        let html = page(body: longProse(6) + "<div>\(markup)</div><p>\(Self.sentences[0])</p>" + longProse(6))
        let article = try #require(try await analyze(html).article)
        #expect(try await removedMarkup(in: article) == "")
    }

    // MARK: SVG pictures

    @Test func aPictureAnSVGHoldsStaysAndOtherDataAddressesGo() async throws {
        let png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        let svg = """
            <svg width="30" height="30"><image id="a" href="\(png)" width="30" height="30"/><image id="b" xlink:href="\(png)" width="30" height="30"/>\
            <image id="c" href="data:text/html,x" width="30" height="30"/><a id="d" href="\(png)"><text>x</text></a></svg>
            """
        let article = try #require(try await analyze(page(body: prose() + svg + prose())).article)
        #expect(article.html.components(separatedBy: png).count == 3, "both pictures are kept: \(article.html)")
        #expect(!article.html.contains("data:text"), "only a picture may be a data address")
    }

}

/// Each feeds one of Readability's slow paths a value of about two megabytes.
nonisolated enum LongDocument: CaseIterable, CustomTestStringConvertible {
    case pictureSourceSet, sourceElementSourceSet, lazySourceSet, lazyAddress, lazyPictureInNoscript, metaProperty, titleAgainstHeading, structuredDataName

    private static let length = 2_000_000
    private static let word = String(repeating: "a", count: length)
    private static func words(_ prefix: String) -> String { (0..<(length / 8)).map { "\(prefix)\($0)" }.joined(separator: " ") }

    var testDescription: String { "\(self)" }

    var head: String {
        switch self {
        case .metaProperty: "<meta property=\"\(String(repeating: " ", count: Self.length))x\" content=\"a\">"
        case .structuredDataName:
            "<script type=\"application/ld+json\">{\"@context\":\"https://schema.org\",\"@type\":\"Article\",\"name\":\"\(Self.words("n"))\",\"headline\":\"\(Self.words("h"))\"}</script>"
        default: ""
        }
    }

    var title: String? {
        switch self {
        case .titleAgainstHeading, .structuredDataName: Self.words("t")
        default: nil
        }
    }

    var body: String {
        switch self {
        case .pictureSourceSet: "<figure><img src=\"https://example.com/a.jpg\" srcset=\"\(Self.word) b\"></figure>"
        case .sourceElementSourceSet: "<picture><source srcset=\"\(Self.word) b\"><img src=\"https://example.com/a.jpg\"></picture>"
        case .lazySourceSet: "<figure><img class=\"lazy\" data-x=\"a.jpg 1 \(Self.word) b\"></figure>"
        case .lazyAddress: "<figure><img class=\"lazy\" data-x=\"\(String(repeating: "a.jpg", count: Self.length / 5)) x\"></figure>"
        case .lazyPictureInNoscript: "<noscript><img class=\"lazy\" data-x=\"\(String(repeating: "a.jpg", count: Self.length / 5)) x\"></noscript>"
        case .titleAgainstHeading: "<h1>\(Self.words("b"))</h1>"
        case .metaProperty, .structuredDataName: ""
        }
    }
}
