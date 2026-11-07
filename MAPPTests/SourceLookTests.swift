@testable import MAPP
import Foundation
import Testing
import WebKit

@Suite(.hangLimit)
@MainActor struct SourceLookTests {
    private func look(_ mode: SourceViewMode, mail: Bool = false, page: PageStyle = PageStyle()) -> SourceLook {
        SourceLook(mode: mode, isMail: mail, page: page)
    }

    private func value(_ script: String, in html: String, look: SourceLook, runsScripts: Bool = false) async throws -> Any? {
        let page = try await SealedWebPage.make(runsScripts: runsScripts)
        try await page.show(Data(html.utf8), look: look)
        return try await page.page.callJavaScript(script)
    }

    private let plain = "<html><body><p>Some words in a document that says nothing about how it looks.</p></body></html>"

    // MARK: The column

    @Test func theTextColumnFollowsThePagesWidthSetting() {
        #expect(look(.reader).inset.contains("100vw - 702px"))
        var full = PageStyle()
        full.fullWidth = true
        #expect(look(.reader, page: full).inset == "39px")
    }

    // MARK: A document that says nothing about its look

    @Test func aPlainDocumentGetsTheBaselineInTheTextColumn() async throws {
        let size = try await value("return getComputedStyle(document.body).fontSize + ' ' + getComputedStyle(document.documentElement).colorScheme", in: plain, look: look(.original))
        #expect(size as? String == "13px light dark")
    }

    @Test func aStyledDocumentIsLeftAsWritten() async throws {
        // Its own light background must not meet a text color that follows the system into dark mode.
        for styled in [
            "<html><head><style>body { background: #fff }</style></head><body><p>Words</p></body></html>",
            "<html><body style=\"background:#fff\"><p>Words</p></body></html>",
            "<html><body bgcolor=\"#ffffff\"><p>Words</p></body></html>",
            "<html><head><link rel=\"stylesheet\" href=\"data:text/css,body%7Bbackground%3A%23fff%7D\"></head><body><p>Words</p></body></html>",
        ] {
            let scheme = try await value("return getComputedStyle(document.documentElement).colorScheme + ' ' + getComputedStyle(document.body).fontSize", in: styled, look: look(.original))
            #expect(scheme as? String == "normal 16px", "\(styled)")
        }
    }

    @Test func aDocumentWhoseOnlyStylesAreOnTheWebStillGetsTheBaseline() async throws {
        // The sheet is blocked like everything else that is not in the file, so the document is as bare as without it.
        let html = "<html><head><link rel=\"stylesheet\" href=\"https://example.com/site.css\"></head><body><p>Words</p></body></html>"
        let size = try await value("return getComputedStyle(document.body).fontSize + ' ' + getComputedStyle(document.documentElement).colorScheme", in: html, look: look(.original))
        #expect(size as? String == "13px light dark")
    }

    @Test func theOriginalLookKeepsEverythingTheSourceWrote() async throws {
        let html = "<html><head><style>p { color: rgb(1, 2, 3) }</style></head><body><h1>Title</h1><p>It said \\\"hi\\\"<a href=\"#x\">#</a></p></body></html>"
        let text = try #require(try await value("return document.body.innerText + '|' + getComputedStyle(document.querySelector('p')).color", in: html, look: look(.original)) as? String)
        #expect(text.contains("Title") && text.contains("It said \\\"hi\\\"#") && text.hasSuffix("|rgb(1, 2, 3)"))
    }

    // MARK: A mail

    private let mail = """
        <html><body><table width="100%"><tr><td align="center"><table id="column" width="600"><tr><td>\
        <p>The mail's own words, at the width its sender gave them.</p></td></tr></table></td></tr></table></body></html>
        """

    @Test func theMailsColumnIsMarkedAndCentered() async throws {
        let marked = try await value("return document.querySelector('[data-mapp-mail]')?.id", in: mail, look: look(.original, mail: true))
        #expect(marked as? String == "column")
        let unmarked = try await value("return document.querySelector('[data-mapp-mail]')?.id ?? 'none'", in: mail, look: look(.original))
        #expect(unmarked as? String == "none")
    }

    @Test func aMailSitsOnTheSurfaceBehindItUnlessItPaintsItsOwn() async throws {
        let backdrop = "return getComputedStyle(document.documentElement).backgroundColor + '|' + getComputedStyle(document.getElementById('column')).backgroundColor"
        #expect(try await value(backdrop, in: mail, look: look(.original, mail: true)) as? String == "rgba(0, 0, 0, 0)|rgb(255, 255, 255)")
        let own = mail.replacingOccurrences(of: "<body>", with: "<body style=\"background:rgb(10, 20, 30)\">")
            .replacingOccurrences(of: "id=\"column\"", with: "id=\"column\" bgcolor=\"#ff0000\"")
        let kept = try await value(backdrop, in: own, look: look(.original, mail: true)) as? String
        #expect(kept == "rgba(0, 0, 0, 0)|rgb(255, 0, 0)", "the mail's own color wins on its column; the page behind it is the surface")
    }

    @Test func aMailIsNeverRestyledAsReaderIs() async throws {
        let font = try await value("return getComputedStyle(document.querySelector('p')).fontFamily", in: mail, look: look(.original, mail: true))
        #expect(!((font as? String) ?? "").contains("New York"))
        #expect(look(.original, mail: true).css.contains("data-mapp-mail"))
    }

    @Test func theSurfaceIsAskedForOnlyWhereTheLookNeedsIt() {
        #expect(look(.original, mail: true).isOnSurface)
        #expect(!look(.original).isOnSurface)
        #expect(!look(.reader, mail: true).isOnSurface, "a mail read in Reader is an article like any other")
        #expect(look(.reader).leavesBackground && look(.original, mail: true).leavesBackground)
        #expect(!look(.original).leavesBackground, "a page paints its own background")
    }

    // MARK: A mail that paints its own page

    /// The column's own background, then the page behind it, as the document computes them.
    private let paint = "return getComputedStyle(document.getElementById('column')).backgroundColor + '|' + getComputedStyle(document.body).backgroundColor"

    @Test func aDarkMailKeepsItsDarkPageAndItsLightText() async throws {
        let table = "<table id=\"column\" width=\"600\"><tr><td><p>Words that are light on a dark page.</p></td></tr></table>"
        let darkMails: [(String, String)] = [
            ("a body with bgcolor and text", "<html><body bgcolor=\"#111111\" text=\"#eeeeee\">\(table)</body></html>"),
            ("a body in an inline style", "<html><body style=\"background:#111111;color:#eeeeee\">\(table)</body></html>"),
            ("a body in a style sheet", "<html><head><style>body { background: #111111; color: #eeeeee }</style></head><body>\(table)</body></html>"),
            ("a table that spans the page", "<html><body><table width=\"100%\" bgcolor=\"#111111\"><tr><td align=\"center\">" +
                "<table id=\"column\" width=\"600\"><tr><td><font color=\"#eeeeee\">Words that are light on a dark page.</font></td></tr></table></td></tr></table></body></html>"),
        ]
        for (name, html) in darkMails {
            let marked = try await value("return document.getElementById('column').hasAttribute('data-mapp-mail')", in: html, look: look(.original, mail: true))
            try #require(marked as? Bool == true, "\(name): the column is found")
            let colors = try await value(paint, in: html, look: look(.original, mail: true)) as? String ?? ""
            #expect(!colors.hasPrefix("rgb(255, 255, 255)"), "\(name) was painted white: \(colors)")
        }
    }

    @Test func aMailWithLightTextAndNoPageOfItsOwnIsNotPaintedWhite() async throws {
        // White under light text is unreadable; the surface behind the page shows instead.
        let html = "<html><body text=\"#eeeeee\"><table id=\"column\" width=\"600\"><tr><td><p>Words in a light color.</p></td></tr></table></body></html>"
        let colors = try await value(paint, in: html, look: look(.original, mail: true)) as? String
        #expect(colors == "rgba(0, 0, 0, 0)|rgba(0, 0, 0, 0)")
    }

    @Test func aMailWithDarkTextAndNoPageOfItsOwnIsPaintedWhite() async throws {
        let html = "<html><head><style>p { color: #222222 }</style></head><body><table id=\"column\" width=\"600\"><tr><td><p>Words in a dark color.</p></td></tr></table></body></html>"
        let colors = try await value(paint, in: html, look: look(.original, mail: true)) as? String
        #expect(colors == "rgb(255, 255, 255)|rgba(0, 0, 0, 0)")
    }

    // MARK: Documents that name their elements after the page's methods

    @Test func aDocumentWhoseImagesAreNamedAfterItsMethodsIsStillGivenItsLook() async throws {
        let names = ["querySelector", "createElement", "body", "head", "documentElement", "createTreeWalker"]
        let clobbers = names.map { "<img name=\"\($0)\" width=\"1\" height=\"1\">" }.joined()
        let html = "<html><body>\(clobbers)<form><input name=\"children\"><input name=\"parentElement\"><input name=\"matches\"></form><p>Some words in a document that says nothing about how it looks.</p></body></html>"
        // The probe reads the document through the prototypes too, since the names hide the document's own.
        let q = "const q = s => Document.prototype.querySelector.call(document, s);"
        let size = try await value(q + "return getComputedStyle(q('body')).fontSize + ' ' + getComputedStyle(q('html')).colorScheme", in: html, look: look(.original))
        #expect(size as? String == "13px light dark")
        let reader = try await value(q + "return getComputedStyle(q('p')).fontFamily", in: html, look: look(.reader))
        #expect((reader as? String)?.contains("New York") == true)
    }

    @Test func aMailInsideAFormThatNamesItsControlsAfterItsPropertiesIsStillFound() async throws {
        let html = "<html><body><form><input type=\"hidden\" name=\"children\"><input type=\"hidden\" name=\"parentElement\"><input type=\"hidden\" name=\"style\">" +
            "<table width=\"100%\"><tr><td align=\"center\"><table id=\"column\" width=\"600\"><tr><td><p>The mail's own words, at the width its sender gave them.</p></td></tr></table></td></tr></table></form></body></html>"
        let marked = try await value("return document.querySelector('[data-mapp-mail]')?.id", in: html, look: look(.original, mail: true))
        #expect(marked as? String == "column")
    }

    // MARK: Documents that would keep the page busy

    @MainActor private final class Showing {
        var shown = false
    }

    @Test func aPageWhoseFormsHideTheirChildrenIsShownAtOnce() async throws {
        // `form.children` is the fieldset that belongs to the form, which holds the form: a walk down the children
        // never ends. The page's process stays busy with it for as long as the app runs, so the look must not walk that way.
        let html = "<html><body><fieldset form=\"f\" name=\"children\"><form id=\"f\"><table width=\"600\"><tr><td><p>The mail's own words, at the width its sender gave them.</p></td></tr></table></form></fieldset></body></html>"
        let page = try await SealedWebPage.make(runsScripts: false)
        let showing = Showing()
        let task = Task {
            try await page.show(Data(html.utf8), look: look(.original, mail: true))
            showing.shown = true
        }
        defer { task.cancel() }
        let ended = await eventually(within: .seconds(20)) { showing.shown }
        #expect(ended, "the look ended")
        guard ended else { return }
        let answered = try? await page.page.callJavaScript("return 1") as? Int
        #expect(answered == 1, "the page answers")
    }

    // MARK: Reader

    @Test func theReaderLookIsNamedByItsSettings() {
        var page = PageStyle()
        page.textSize = 16
        let reader = look(.reader, page: page)
        #expect(reader.css.contains("18.0px"), "the prose is 14.6 for every 13 of the page's text size")
        #expect(reader != look(.reader))
    }
}
