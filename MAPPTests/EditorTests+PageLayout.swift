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

    /// The rows of a Readwise Highlight: many strings, short and long, an ISO date, a web address and a note with a break.
    static func highlightRows() -> [PropertyRow] {
        [
            PropertyRow(id: "account", label: "Account", value: .text("aicayzer")),
            PropertyRow(id: "author", label: "Author", value: .text("Sean Carroll and a second author with a long name")),
            PropertyRow(id: "category", label: "Category", value: .text("articles")),
            PropertyRow(id: "locator", label: "Locator Type", value: .text("order")),
            PropertyRow(id: "created", label: "Reader Created At", value: .text("2026-04-29T09:00:00.123456+00:00")),
            PropertyRow(id: "notes", label: "Reader Notes", value: .text("A note that runs to several words and is long enough to wrap on to a second line of the value column, at least once")),
            PropertyRow(id: "metadata", label: "Reader Metadata", value: .url("{\"a\": 1,\n \"b\": [1, 2, 3],\n \"c\": \"" + String(repeating: "word ", count: 30) + "\"}")),
            PropertyRow(id: "source", label: "Source", value: .url("https://readwise.io/open/" + String(repeating: "9", count: 60))),
            PropertyRow(id: "id", label: "Reader Id", value: .text("01hxyzabcdefghjkmnpqrstvwx")),
            PropertyRow(id: "date", label: "Highlighted At", value: .date("29 April 2026")),
        ]
    }

    /// A page that is drawn while it is a point wide, as the item page is when a sidebar or the inspector closes over it
    /// during an animation, must have rows of one line each once it is wide again.
    @Test(arguments: [0.0, 1.0]) func aHighlightsPropertyRowsLieCloseTogetherWhenTheHeaderIsDrawnWhileThePageIsNarrow(narrow: Double) async throws {
        let page = try await Page()
        try await page.load("A note.\n")
        var header = Self.header("A highlight")
        header.item = try #require(page.editor.noteID).rawValue
        header.properties = Self.highlightRows()
        header.foldAfter = 20
        let window = try await Self.show(page, width: 900)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        page.editor.setHeader(header)
        _ = try await eventuallyAsking {
            try await page.editor.webView.evaluateJavaScript("document.querySelectorAll('.item-prop').length") as? Int == 10
        }
        let container = page.editor.container
        let full = container.frame.size
        container.setFrameSize(NSSize(width: narrow, height: full.height))
        _ = try await eventuallyAsking { try await page.editor.webView.evaluateJavaScript("innerWidth") as? Int == Int(narrow) }
        // The app sends the next item's header while the page is narrow, so its rows are first laid out there.
        var next = header
        next.properties = Array(Self.highlightRows().reversed())
        page.editor.setHeader(next)
        _ = try await eventuallyAsking {
            try await page.editor.webView.evaluateJavaScript("document.querySelector('.item-prop')?.dataset.row") as? String == "date"
        }
        container.setFrameSize(full)
        let measured = try #require(try await settle(page.editor, Self.rowGaps, as: [Int].self) { $0 != nil })
        // Gives a late relayout time to run, which would show as rows still out of place in the second reading.
        try await Task.sleep(for: .milliseconds(300))
        let later = try #require(try await page.editor.webView.evaluateJavaScript(Self.rowGaps) as? [Int])
        for found in [measured, later] {
            // Each row is one line, or two for a long value, so at most 64 points; stale heights are hundreds.
            #expect(found[0] <= 64, "a row is \(found[0]) points tall")
            #expect(found[1] <= 1, "rows are \(found[1]) points apart")
        }
    }

    static let rowGaps = """
        (() => {
          const rows = [...document.querySelectorAll('.item-prop')].map(row => row.getBoundingClientRect())
          if (rows.length !== 10 || document.documentElement.clientWidth < 800) return null
          return [Math.round(Math.max(...rows.map(r => r.height))), Math.round(Math.max(...rows.slice(1).map((r, i) => r.top - rows[i].bottom)))]
        })()
        """

    @Test func everyKindOfChipIsOneHeightAndStaysInsideItsColumn() async throws {
        let page = try await Page()
        try await page.load("A note.\n")
        var header = Self.header("A highlight")
        header.item = try #require(page.editor.noteID).rawValue
        let source = PropertyRow.Target(title: "A source article", item: ItemID("source"), icon: "lucide:book-open")
        let person = PropertyRow.Target(title: "Mira Castell", item: ItemID("mira"), icon: "lucide:user", kind: .person)
        header.properties.append(PropertyRow(id: "about", label: "About", value: .items([source, person])))
        header.properties.append(PropertyRow(id: "priority", label: "Priority", value: .options(["High", String(repeating: "a very long option ", count: 20)])))
        header.properties.append(PropertyRow(id: "#tags", label: "Tags", value: .tags(["favorite"])))
        page.editor.setHeader(header)
        let window = try await Self.show(page, width: 900)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        // Every chip, the status and parent pins and the type chip among them: their heights, and whether each ends inside its row.
        let measured = try #require(try await settle(page.editor, """
            (() => {
              const chips = [...document.querySelectorAll('#item-header .item-chip')]
              const person = document.querySelector('.item-person')
              if (chips.length < 7 || !person) return null
              const heights = chips.map(chip => chip.getBoundingClientRect().height)
              const inside = chips.every(chip => {
                const row = chip.closest('.item-prop-value') || chip.parentElement
                return chip.getBoundingClientRect().right <= row.getBoundingClientRect().right + 0.5
              })
              const circle = person.querySelector('.item-person-initials').getBoundingClientRect()
              return [Math.min(...heights), Math.max(...heights), inside ? 1 : 0, circle.width, circle.height,
                      getComputedStyle(person).backgroundColor === 'rgba(0, 0, 0, 0)' ? 1 : 0]
            })()
            """, as: [Double].self) { $0 != nil })
        #expect(measured[0] == 22 && measured[1] == 22, "chips are \(measured[0]) to \(measured[1]) points high")
        #expect(measured[2] == 1, "a long value stays inside its column")
        #expect(measured[3] == 17 && measured[4] == 17, "the initials are in a 17 point circle")
        #expect(measured[5] == 1, "a person has no chip behind it")
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
