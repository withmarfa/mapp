@testable import MAPP
import Foundation
import Testing

@Suite(.hangLimit)
@MainActor struct LinkIconsTests {
    @Test func aTypeIconIsDrawnAsASquarePNGAndKeptForTheNextAsk() throws {
        let url = try #require(LinkIcons.dataURL(for: "lucide:user"))
        #expect(url.hasPrefix("data:image/png;base64,"))
        #expect(LinkIcons.dataURL(for: "lucide:user") == url)
    }

    @Test func theHeaderAndALinkDrawAnIconWithTheSameShape() throws {
        let square = try #require(PageHeaderIcons.typeIcon("lucide:user", size: 16, square: true))
        #expect(square.width == square.height)
    }
}
