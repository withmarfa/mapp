import AppKit
import Foundation
import Testing
import WebKit
@testable import MAPP

/// How the header's blocks are laid out in real WebKit, which a browser engine of another kind does not predict.
extension EditorTests {
    static func rows(_ values: [String]) -> [PropertyRow] {
        values.enumerated().map { PropertyRow(id: "field-\($0.offset)", label: "Field \($0.offset)", value: .text($0.element)) }
    }

    @Test func propertyRowsStayShortWhenTheHeaderIsFirstLaidOutBeforeThePageHasAWidth() async throws {
        let page = try await Page()
        try await page.load("A note.\n")
        var header = Self.header("A comment")
        header.item = try #require(page.editor.noteID).rawValue
        header.properties = Self.rows(["aicayzer", "IC_kwDOVBCCyc8AAAABgosEEg", "aicayzer/inkkit"])
        // The app sends the header as soon as an item is chosen, before the window has sized the page.
        page.editor.setHeader(header)
        _ = try await eventuallyAsking {
            try await page.editor.webView.evaluateJavaScript("document.querySelectorAll('.item-prop').length") as? Int == 3
        }
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        _ = try await eventuallyAsking { try await page.editor.webView.evaluateJavaScript("innerWidth") as? Int == 900 }
        let heights = try await settle(page.editor,
            "[...document.querySelectorAll('.item-prop')].map(row => Math.round(row.getBoundingClientRect().height))",
            as: [Int].self) { $0?.count == 3 }
        // A row is one line of text with its padding; a value that wraps at every character would be ten times that.
        for height in try #require(heights) { #expect(height <= 64, "a property row is at most two lines tall, not \(height) points") }
    }
}
