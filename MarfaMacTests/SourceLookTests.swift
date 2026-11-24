@testable import MarfaMac
import Foundation
import Testing
import WebKit

@Suite(.hangLimit)
@MainActor struct SourceLookTests {
    private func look(_ mode: SourceViewMode, mail: Bool = false, page: PageStyle = PageStyle()) -> SourceLook {
        SourceLook(mode: mode, isMail: mail, page: page)
    }

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
}
