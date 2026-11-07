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
            "<html><head><link rel=\"stylesheet\" href=\"https://example.com/site.css\"></head><body><p>Words</p></body></html>",
        ] {
            let scheme = try await value("return getComputedStyle(document.documentElement).colorScheme + ' ' + getComputedStyle(document.body).fontSize", in: styled, look: look(.original))
            #expect(scheme as? String == "normal 16px", "\(styled)")
        }
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

    // MARK: Reader

    @Test func theReaderLookIsNamedByItsSettings() {
        var page = PageStyle()
        page.textSize = 16
        let reader = look(.reader, page: page)
        #expect(reader.css.contains("18.0px"), "the prose is 14.6 for every 13 of the page's text size")
        #expect(reader != look(.reader))
    }
}
