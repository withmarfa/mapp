import AppKit
import Foundation
import Marfa
import Testing
import WebKit
@testable import MAPP

/// How the header's blocks are laid out in real WebKit, which a browser engine of another kind does not predict.
extension EditorTests {
    static func rows(_ values: [String]) -> [PropertyRow] {
        values.enumerated().map { PropertyRow(id: "field-\($0.offset)", label: "Field \($0.offset)", value: .text($0.element)) }
    }

    /// Puts the page in a window of this width, so it lays out at a real width.
    static func show(_ page: Page, width: Int) async throws -> TestWindow {
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        window.orderFrontRegardless()
        _ = try await eventuallyAsking { try await page.editor.webView.evaluateJavaScript("innerWidth") as? Int == width }
        return window
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
        let window = try await Self.show(page, width: 900)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        let heights = try await settle(page.editor,
            "[...document.querySelectorAll('.item-prop')].map(row => Math.round(row.getBoundingClientRect().height))",
            as: [Int].self) { $0?.count == 3 && $0?.max() ?? 0 <= 64 }
        // The page draws the rows again once it has a width, a frame after the window sizes it, so wait for that. A row is
        // one line of text with its padding; a value that wraps at every character would be ten times that.
        for height in try #require(heights) { #expect(height <= 64, "a property row is at most two lines tall, not \(height) points") }
    }

    @Test func longUnbrokenValuesWrapInsideTheColumnInsteadOfWideningThePage() async throws {
        let page = try await Page()
        try await page.load("A note.\n")
        var header = Self.header("A comment")
        header.item = try #require(page.editor.noteID).rawValue
        let address = "https://example.com/" + String(repeating: "a", count: 150)
        header.properties = [
            PropertyRow(id: "text", label: "Text", value: .text(String(repeating: "x", count: 110))),
            PropertyRow(id: "url", label: "Link", value: .url(address)),
            PropertyRow(id: "email", label: "Mail", value: .email(String(repeating: "m", count: 90) + "@example.com")),
            PropertyRow(id: "short", label: "Short", value: .text("aicayzer")),
        ]
        page.editor.setHeader(header)
        let window = try await Self.show(page, width: 700)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        // For each row, how far past its column the furthest thing in the value reaches and how tall the row is, then
        // the width the page scrolls to and the width it shows, which leaves out a scroll bar that takes up room.
        let measured = try #require(try await settle(page.editor, """
            (() => {
              const rows = [...document.querySelectorAll('.item-prop')]
              if (rows.length !== 4) return null
              const numbers = rows.flatMap(row => {
                const value = row.querySelector('.item-prop-value')
                const range = document.createRange()
                range.selectNodeContents(value)
                const column = value.getBoundingClientRect().right
                const reach = range.getBoundingClientRect().right
                return [Math.round(reach - column), Math.round(row.getBoundingClientRect().height)]
              })
              return [...numbers, document.documentElement.scrollWidth, document.documentElement.clientWidth]
            })()
            """, as: [Int].self) { $0?.count == 10 && $0?[7] ?? 0 <= 64 })
        let rows = ["text", "url", "email", "short"]
        for (index, name) in rows.enumerated() {
            #expect(measured[index * 2] <= 0, "the \(name) value stays inside its column, not \(measured[index * 2]) points past it")
        }
        #expect(measured[8] == measured[9], "the page scrolls no wider than it shows: \(measured[8]) against \(measured[9])")
        #expect(measured[7] <= 64, "a short value stays one line, not \(measured[7]) points tall")
    }

    @Test func anEventsDetailLineWrapsOnANarrowPageAndStaysBesideItsCalendarTile() async throws {
        let page = try await Page()
        try await page.load("A note.\n")
        var header = Self.header("A meeting")
        header.item = try #require(page.editor.noteID).rawValue
        header.kind = .event
        let item = MAPP.Item(
            id: ItemID("10000000-0000-0000-0000-000000000002"), type: TypeID("core.event"), title: "A meeting", titleRule: .property("title"),
            properties: [
                Property(key: "starts_at", value: .string("2027-04-29T09:00:00Z")), Property(key: "ends_at", value: .string("2027-04-29T10:00:00Z")),
                Property(key: "timezone", value: .string("Pacific/Auckland")),
            ], version: ItemVersion(1), created: .distantPast, modified: .distantPast)
        header.event = try #require(EventHeader(item: item, now: Date()))
        page.editor.setHeader(header)
        let window = try await Self.show(page, width: 260)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        // Whether the detail line is cut off, and how far its tile's middle is from the middle of the two lines.
        let measured = try #require(try await settle(page.editor, """
            (() => {
              const detail = document.querySelector('.item-when-detail')
              const text = document.querySelector('.item-when-text')
              const tile = document.querySelector('.item-calendar')
              if (!detail || !text || !tile || !detail.textContent) return null
              const middle = rect => rect.top + rect.height / 2
              return [detail.scrollWidth - detail.clientWidth, Math.round(Math.abs(middle(text.getBoundingClientRect()) - middle(tile.getBoundingClientRect()))),
                      document.documentElement.scrollWidth - document.documentElement.clientWidth]
            })()
            """, as: [Int].self) { $0?.count == 3 })
        #expect(measured[0] <= 0, "the detail line is cut off by \(measured[0]) points instead of wrapping")
        #expect(measured[1] <= 1, "the tile is \(measured[1]) points off the middle of the text beside it")
        #expect(measured[2] <= 0, "the page is \(measured[2]) points wider than it shows")
    }
}
