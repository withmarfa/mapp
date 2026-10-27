import Foundation
import Marfa
import Testing
import UniformTypeIdentifiers
@testable import MAPP

struct BrowserTargetTests {
    private static let file = URL(filePath: "/library/files/abc")

    private static func page(_ properties: [String: PropertyValue] = [:]) -> MAPP.Item {
        MAPP.Item(
            id: ItemID("10000000-0000-0000-0000-000000000002"), type: TypeID("core.file.webpage"), title: "Quarterly Report",
            titleRule: .property("title"), properties: properties.map { Property(key: $0, value: $1) }, content: .file(.html, byteCount: 10),
            version: ItemVersion(1), created: .distantPast, modified: .distantPast)
    }

    @Test func theAddressThePageCameFromIsOpenedInPreferenceToItsFile() {
        let item = Self.page(["url": .string(" https://example.com/report ")])
        #expect(BrowserTarget.of(item, fetchedFile: Self.file) == .address(URL(string: "https://example.com/report")!))
    }

    @Test func theSourceAddressIsTheSecondChoice() {
        let item = Self.page(["source_url": .string("https://example.com/source"), "url": .string("not an address")])
        #expect(BrowserTarget.of(item, fetchedFile: nil) == .address(URL(string: "https://example.com/source")!))
    }

    @Test func aPageWithNoAddressOpensItsFile() {
        #expect(BrowserTarget.of(Self.page(), fetchedFile: Self.file) == .file(Self.file))
        // An address a browser should not be sent to is not one.
        let local = Self.page(["url": .string("file:///etc/passwd")])
        #expect(BrowserTarget.of(local, fetchedFile: Self.file) == .file(Self.file))
    }

    @Test func aPageWithNothingToOpenHasNoTarget() {
        #expect(BrowserTarget.of(Self.page(), fetchedFile: nil) == nil)
    }

    @Test func onlyHTMLIsShownAsAPage() {
        #expect(WebPageFile.isHTML(.html))
        #expect(WebPageFile.isHTML(UTType(mimeType: "application/xhtml+xml")))
        #expect(WebPageFile.isHTML(.data))
        #expect(WebPageFile.isHTML(nil))
        #expect(!WebPageFile.isHTML(.pdf))
        #expect(!WebPageFile.isHTML(.plainText))
    }

    @Test func aFileIsNamedAfterThePageWithAnHTMLExtension() {
        #expect(QuickLookFile.name(for: "Quarterly Report", type: .html) == "Quarterly Report.html")
        #expect(QuickLookFile.name(for: "a/b: c.html", type: .html) == "a-b- c.html")
    }
}
