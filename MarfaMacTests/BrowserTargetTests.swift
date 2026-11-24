import Foundation
import Marfa
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

struct BrowserTargetTests {
    private static let file = URL(filePath: "/library/files/abc")

    @Test func aFileIsNamedAfterThePageWithAnHTMLExtension() {
        #expect(QuickLookFile.name(for: "Quarterly Report", type: .html) == "Quarterly Report.html")
        #expect(QuickLookFile.name(for: "a/b: c.html", type: .html) == "a-b- c.html")
    }

    @Test func openingAPageAgainReplacesItsCopyInsteadOfAddingOne() throws {
        let source = URL.temporaryDirectory.appending(path: "BrowserCopy-\(UUID().uuidString)")
        try Data("<p>One</p>".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let key = "page-\(UUID().uuidString)"
        let first = try #require(QuickLookFile.copy(of: source, titled: "Report", as: .html, in: "Web Pages Test", key: key))
        defer { first.remove() }
        try Data("<p>Two</p>".utf8).write(to: source)
        let second = try #require(QuickLookFile.copy(of: source, titled: "Report", as: .html, in: "Web Pages Test", key: key))
        #expect(second.url == first.url)
        #expect(second.url.lastPathComponent == "Report.html")
        #expect(try String(contentsOf: second.url, encoding: .utf8) == "<p>Two</p>")
        #expect(try FileManager.default.contentsOfDirectory(at: second.folder.deletingLastPathComponent(), includingPropertiesForKeys: nil).count == 1)
    }
}
