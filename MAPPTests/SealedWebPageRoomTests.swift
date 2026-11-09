@testable import MAPP
import Foundation
import Testing
import WebKit

@Suite(.hangLimit)
@MainActor struct SealedWebPageRoomTests {
    private func read(_ property: String, of page: SealedWebPage) async throws -> String {
        try await page.page.callJavaScript("return getComputedStyle(document.documentElement)[name]", arguments: ["name": property]) as? String ?? ""
    }

    @Test func aDocumentStartsBelowTheRoomAndKeepsItsOwnPadding() async throws {
        let page = try await SealedWebPage.make(runsScripts: false)
        await page.leaveRoom(above: 120)
        try await page.show(Data("<html><head><style>html { padding-top: 3px !important }</style></head><body>One</body></html>".utf8))
        #expect(try await read("borderTopWidth", of: page) == "120px")
        #expect(try await read("paddingTop", of: page) == "3px")
        try await page.show(Data("<html><body>Two</body></html>".utf8))
        #expect(try await read("borderTopWidth", of: page) == "120px")
    }

    @Test func theRoomChangesWithoutLoadingTheDocumentAgain() async throws {
        let page = try await SealedWebPage.make(runsScripts: false)
        try await page.show(Data("<html><body>One</body></html>".utf8))
        #expect(try await read("borderTopWidth", of: page) == "0px")
        await page.leaveRoom(above: 80)
        #expect(try await read("borderTopWidth", of: page) == "80px")
    }

    @Test func aPageScriptThatRewritesTheRootStyleDoesNotTakeTheRoomAway() async throws {
        let page = try await SealedWebPage.make(runsScripts: true)
        await page.leaveRoom(above: 60)
        try await page.show(Data("<html><body>One<script>setTimeout(() => document.documentElement.removeAttribute('style'), 0)</script></body></html>".utf8))
        try await eventually { try await read("borderTopWidth", of: page) == "60px" }
    }
}
