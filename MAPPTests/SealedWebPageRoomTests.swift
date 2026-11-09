@testable import MAPP
import Foundation
import Testing
import WebKit

@Suite(.hangLimit)
@MainActor struct SealedWebPageRoomTests {
    private func padding(of page: SealedWebPage) async throws -> String {
        try await page.page.callJavaScript("return getComputedStyle(document.documentElement).paddingTop") as? String ?? ""
    }

    @Test func aDocumentStartsBelowTheRoomAndKeepsItWhenAnotherIsShown() async throws {
        let page = try await SealedWebPage.make(runsScripts: false)
        await page.leaveRoom(above: 120)
        try await page.show(Data("<html><head><style>html { padding-top: 3px !important }</style></head><body>One</body></html>".utf8))
        #expect(try await padding(of: page) == "120px")
        try await page.show(Data("<html><body>Two</body></html>".utf8))
        #expect(try await padding(of: page) == "120px")
    }

    @Test func theRoomChangesWithoutLoadingTheDocumentAgain() async throws {
        let page = try await SealedWebPage.make(runsScripts: false)
        try await page.show(Data("<html><body>One</body></html>".utf8))
        #expect(try await padding(of: page) == "0px")
        await page.leaveRoom(above: 80)
        #expect(try await padding(of: page) == "80px")
    }
}
