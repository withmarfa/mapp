@testable import MAPP
import Foundation
import Testing
import WebKit

@Suite(.hangLimit)
@MainActor struct SourceLookTests {
    private let title = "CaMeL offers a promising new direction for mitigating prompt injection attacks"

    private var article: Data {
        Data("""
            <html><body><h1>CaMeL offers a promising new direction for mitigating prompt injection attacks</h1>
            <p>It said \\"I don't know\\" and stopped.</p>
            <h2 id="why">Why it matters<a href="#why">#</a></h2>
            <p>Body. <a href="https://example.com/x">A link</a></p>
            <pre>keep \\"this\\"</pre>
            <h2>Second heading</h2></body></html>
            """.utf8)
    }

    private func text(of look: SourceLook) async throws -> String {
        let page = try await SealedWebPage.make(runsScripts: false)
        try await page.show(article, look: look)
        return try #require(try await page.page.callJavaScript("return document.body.innerText") as? String)
    }

    private func look(_ mode: SourceViewMode, wide: Bool = false, title: String? = nil) -> SourceLook {
        SourceLook(mode: mode, title: title ?? self.title, page: PageStyle(), originalWide: wide)
    }

    @Test func theReaderViewDropsTheRepeatedTitleAndTheSourcesArtifacts() async throws {
        let text = try await text(of: look(.reader))
        #expect(!text.contains("CaMeL"), "the heading that repeats the title is gone")
        #expect(text.contains("Why it matters") && !text.contains("Why it matters#"), "the # link is gone")
        #expect(text.contains("\"I don't know\"") && !text.contains("\\\""), "escaped quotes are plain")
        #expect(text.contains("keep \\\"this\\\""), "code is left as written")
        #expect(text.contains("A link"))
    }

    @Test func aHeadingThatIsNotTheTitleStays() async throws {
        #expect(try await text(of: look(.reader, title: "Something else")).contains("CaMeL offers"))
    }

    @Test func theOriginalViewKeepsTheSourcesOwnContent() async throws {
        let text = try await text(of: look(.original))
        #expect(text.contains("CaMeL offers") && text.contains("Why it matters#") && text.contains("\\\"I don't know"))
    }

    @Test func theWideSettingFreesOnlyTheOriginalViewFromTheColumn() {
        #expect(look(.original, wide: true).inset == "39px")
        #expect(look(.original, wide: false).inset.contains("100vw - 702px"))
        // The reader view follows the page's own width setting, not the original's.
        #expect(look(.reader, wide: true).inset.contains("100vw - 702px"))
    }
}
