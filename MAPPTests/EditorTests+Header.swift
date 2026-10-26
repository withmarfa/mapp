import AppKit
import Foundation
import SwiftUI
import Testing
import WebKit
@testable import MAPP

/// The item header the page draws above the note.
extension EditorTests {
    // MARK: The item header

    static func header(_ title: String, id: ItemID = ItemID("note"), hidden: Bool = false) -> PageHeader {
        PageHeader(item: id.rawValue, hidden: hidden, title: title, draft: nil, titleRejected: false,
                   titleRefusal: "The title could not be saved.", editable: true,
                   type: "Task", status: .init(label: "In Progress", enabled: true),
                   parent: .init(label: "Field Research", enabled: true), propertyRejected: false, parentRejected: false, interfaceTextSize: 13)
    }

    static func json(_ value: some Encodable) -> String {
        String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
    }

    /// An element's frame in the page's window, as left, top, width and height.
    static func rect(_ selector: String, in page: Page) async throws -> [Double] {
        try #require(try await page.editor.webView.evaluateJavaScript(
            "(() => { const r = document.querySelector(\(json(selector))).getBoundingClientRect(); return [r.left, r.top, r.width, r.height] })()"
        ) as? [Double])
    }

    @Test func aNewItemsTitleTakesTheKeyboardWhenThePageShowsThatItem() async throws {
        let page = try await Page()
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        let note = page.library.add("")
        page.editor.load(note)
        try await page.wait { page.editor.noteID == note.id }
        page.editor.focus(note.id, onTitle: true)
        page.editor.setHeader(Self.header("Untitled", id: note.id))
        var focused = ""
        var selected = ""
        _ = try await eventuallyAsking {
            focused = try await page.editor.webView.evaluateJavaScript("document.activeElement?.id ?? ''") as? String ?? ""
            selected = try await page.editor.webView.evaluateJavaScript("String(getSelection())") as? String ?? ""
            return focused == "ItemPageTitle" && selected == "Untitled"
        }
        #expect(focused == "ItemPageTitle")
        #expect(selected == "Untitled", "the title is selected, so typing names the item")
    }

    @Test func theItemHeaderScrollsWithTheTextInsideThePage() async throws {
        let page = try await Page()
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await page.load(Array(repeating: "A paragraph for the scrolling check.", count: 60).joined(separator: "\n\n") + "\n")
        page.editor.setHeader(Self.header("Review the findings"))
        _ = try await page.editor.webView.evaluateJavaScript("1")
        let shown = try await page.editor.webView.evaluateJavaScript(
            "[...document.querySelectorAll('#ItemPageTitle, #ItemTypePin, #ItemStatusPin, #ItemParentPin')].map(e => e.textContent)"
        ) as? [String]
        #expect(shown == ["Review the findings", "Task", "In Progress", "Field Research"])

        try await page.run("window.scrollTo(0, 0)")

        // One surface: the header moves exactly as far as the text, and the app hears only the crossing.
        try await page.run("""
            window.headerMessages = []
            const post = window.webkit.messageHandlers.host.postMessage.bind(window.webkit.messageHandlers.host)
            window.webkit.messageHandlers.host.postMessage = m => { if (m.type === 'headerScrolledAway') window.headerMessages.push(m.away); post(m) }
            """)
        let titleBefore = try await Self.rect("#ItemPageTitle", in: page)
        let textBefore = try await Self.rect(".ProseMirror p", in: page)
        try await page.run("window.scrollTo(0, 37)")
        let titleAfter = try await Self.rect("#ItemPageTitle", in: page)
        let textAfter = try await Self.rect(".ProseMirror p", in: page)
        #expect(titleBefore[1] - titleAfter[1] == 37)
        #expect(textBefore[1] - textAfter[1] == 37)
        #expect(!page.editor.isHeaderScrolledAway)
        for offset in stride(from: 40, through: 400, by: 20) {
            try await page.run("window.scrollTo(0, \(offset)); window.dispatchEvent(new Event('scroll'))")
        }
        try await page.wait { page.editor.isHeaderScrolledAway }
        for offset in stride(from: 400, through: 0, by: -20) {
            try await page.run("window.scrollTo(0, \(offset)); window.dispatchEvent(new Event('scroll'))")
        }
        try await page.wait { !page.editor.isHeaderScrolledAway }
        #expect(try await page.editor.webView.evaluateJavaScript("window.headerMessages") as? [Bool] == [true, false])

        // A deleted note's page has no header, so the toolbar holds its title from the start.
        page.editor.setHeader(Self.header("Review the findings", hidden: true))
        try await page.wait { page.editor.isHeaderScrolledAway }
        let hidden = try await page.editor.webView.evaluateJavaScript("document.getElementById('item-header').hidden") as? Bool
        #expect(hidden == true)
        #expect(try await page.markdown() == nil)
        #expect(page.library.notices.waiting.last == nil)
    }

    @Test func changingItemsAfterScrollingStartsAtTheTopAndStaysThere() async throws {
        let page = try await Page()
        let container = page.editor.container
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 700, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        container.topInset = 52
        container.layoutSubtreeIfNeeded()
        let paragraphs = Array(repeating: "A paragraph for the scrolling check.", count: 60).joined(separator: "\n\n") + "\n"
        try await page.load(paragraphs)
        page.editor.setHeader(Self.header("First item"))
        try await page.run("window.scrollTo(0, 240)")
        let scrolled = try await page.editor.webView.evaluateJavaScript("window.scrollY") as? Double
        #expect(scrolled == 240)

        for index in 0..<3 {
            page.editor.setHeader(Self.header(String(repeating: "A longer title ", count: index + 1)))
            try await page.load("Item \(index)\n\n" + paragraphs)
            try await page.run("0")
            #expect(try await page.editor.webView.evaluateJavaScript("window.scrollY") as? Double == 0)
            try await page.wait { !page.editor.isHeaderScrolledAway }
            window.setContentSize(NSSize(width: index.isMultiple(of: 2) ? 600 : 700, height: 500))
            container.layoutSubtreeIfNeeded()
            try await page.run("0")
            #expect(try await page.editor.webView.evaluateJavaScript("window.scrollY") as? Double == 0)
            try await page.run("window.scrollTo(0, 240)")
        }
        #expect(page.changes.isEmpty)
        #expect(page.library.notices.waiting.last == nil)
    }

    @Test func anUpdateForTheItemJustLeftCannotReloadIt() async throws {
        let library = FakeItemLibrary()
        let first = library.add("First item\n")
        let second = library.add("Second item\n")
        let page = try await Page(library: library)
        page.editor.load(try #require(library.item(first.id)))
        _ = try await page.editor.webView.evaluateJavaScript("1")
        page.editor.load(try #require(library.item(second.id)))
        try await page.wait { page.editor.noteID == second.id }
        _ = try await page.editor.webView.evaluateJavaScript("1")
        page.editor.noteChanged(try #require(library.item(first.id)))
        _ = try await page.editor.webView.evaluateJavaScript("1")
        _ = try await page.editor.webView.evaluateJavaScript("1")
        #expect(page.editor.noteID == second.id)
        #expect(try await page.editor.webView.evaluateJavaScript("window.editor.snapshot().text") as? String == "Second item\n")
        #expect(page.changes.isEmpty)
    }

    @Test(arguments: [false, true])
    func aSelectedItemLoadsWhenItsMissingBodyArrives(versionChanged: Bool) async throws {
        typealias F = LibraryFixture
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(F.snapshot))
        try #require(await eventually { library.isLoaded })
        let editor = EditorController(library: library)
        try #require(await eventually { editor.isReady })
        var item = try #require(library.item(F.n1))
        editor.load(item)
        #expect(editor.noteID == nil)
        #expect(!editor.hasNote)

        source.setBody("Recovered body\n", of: item.id, version: 2)
        if versionChanged {
            item.version = ItemVersion(2)
            source.send(.upserted([item]))
        } else {
            source.send(.bodyChanged(item.id, ItemVersion(2)))
        }
        try #require(await eventually { library.body(of: item.id)?.text == "Recovered body\n" })
        editor.noteChanged(try #require(library.item(item.id)))
        try #require(await eventually { editor.noteID == item.id })
        #expect(editor.hasNote)
        #expect(try await editor.webView.evaluateJavaScript("window.editor.snapshot().text") as? String == "Recovered body\n")
        #expect(source.writes.isEmpty)
    }

    @Test(arguments: [false, true])
    func aMissingBodyCannotReopenAnItemAfterLeavingIt(close: Bool) async throws {
        typealias F = LibraryFixture
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(F.snapshot))
        try #require(await eventually { library.isLoaded })
        let editor = EditorController(library: library)
        try #require(await eventually { editor.isReady })
        let item = try #require(library.item(F.n1))
        editor.load(item)
        if close {
            editor.close()
        } else {
            let other = try #require(library.items(in: .allNotes).first { $0.id != item.id && !$0.isFile })
            source.setBody("Other body\n", of: other.id)
            source.send(.bodyChanged(other.id, other.version))
            try #require(await eventually { library.body(of: other.id) != nil })
            editor.load(other)
            try #require(await eventually { editor.noteID == other.id })
        }
        let selected = editor.noteID
        source.setBody("Recovered body\n", of: item.id)
        source.send(.bodyChanged(item.id, item.version))
        try #require(await eventually { library.body(of: item.id) != nil })
        editor.noteChanged(item)
        _ = try await editor.webView.evaluateJavaScript("1")
        #expect(editor.noteID == selected)
        #expect(editor.hasNote == !close)
        if !close {
            #expect(try await editor.webView.evaluateJavaScript("window.editor.snapshot().text") as? String == "Other body\n")
        }
        #expect(source.writes.isEmpty)
    }

    @Test func textPastedIntoTheTitleComesInOnOneLineAndOneUndoTakesItOut() async throws {
        let page = try await Page()
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        window.makeKeyAndOrderFront(nil)
        let saved = NSPasteboard.general.string(forType: .string)
        defer {
            NSPasteboard.general.clearContents()
            if let saved { NSPasteboard.general.setString(saved, forType: .string) }
            window.orderOut(nil); window.contentView = nil; window.close()
        }
        try await page.load("Text\n")
        let id = try #require(page.editor.noteID)
        page.editor.setHeader(Self.header("Title", id: id))
        #expect(window.makeFirstResponder(page.editor.webView))
        func title() async throws -> String? {
            try await page.editor.webView.evaluateJavaScript("document.getElementById('ItemPageTitle').textContent") as? String
        }
        // The last is copied from a page, with its markup beside the plain text.
        let cases = ["one\ntwo", "one\r\ntwo", "one\u{2028}two", "one\u{2029}two", "one\n\n\ntwo", "one \n \ntwo", "<p>one</p><p>two</p>"]
        // Pasted over the whole title, and at its end.
        for (pasted, replacing) in cases.map({ ($0, true) }) + cases.map({ ($0, false) }) {
            let expected = replacing ? "one two" : "Titleone two"
            let caret = replacing ? "document.execCommand('selectAll')" : "getSelection().collapse(document.getElementById('ItemPageTitle'), 1)"
            try await page.run("document.getElementById('ItemPageTitle').focus(); \(caret)")
            try await page.wait { page.editor.isEditingTitle }
            NSPasteboard.general.clearContents()
            if pasted.hasPrefix("<") {
                NSPasteboard.general.setString(pasted, forType: .html)
                NSPasteboard.general.setString("one\ntwo", forType: .string)
            } else {
                NSPasteboard.general.setString(pasted, forType: .string)
            }
            NSApp.sendAction(#selector(NSText.paste(_:)), to: page.editor.webView, from: nil)
            _ = try await eventuallyAsking { try await title() != "Title" }
            let markup = try await page.editor.webView.evaluateJavaScript("document.getElementById('ItemPageTitle').innerHTML") as? String
            #expect(markup == expected, "pasting \(pasted.unicodeScalars.map { String($0.value, radix: 16) }) left \(markup ?? "")")
            page.editor.webView.undo(nil)
            _ = try await eventuallyAsking { try await title() == "Title" }
            #expect(try await title() == "Title", "one Undo takes out what was pasted")
        }
    }

    /// The paste itself is Inkkit's; this holds that it works through the pasteboard, the web view and the bridge.
    @Test func htmlCopiedFromAWebPageIsPastedIntoTheNoteAsReadableText() async throws {
        let page = try await Page()
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        window.makeKeyAndOrderFront(nil)
        let saved = NSPasteboard.general.string(forType: .string)
        defer {
            NSPasteboard.general.clearContents()
            if let saved { NSPasteboard.general.setString(saved, forType: .string) }
            window.orderOut(nil); window.contentView = nil; window.close()
        }
        try await page.load("Start\n")
        #expect(window.makeFirstResponder(page.editor.webView))
        // As a browser puts it on the pasteboard: source indentation and line breaks inside the text, styling,
        // and a script, beside a plain-text flattening. It has no link: WebKit turns the spaces beside an inline
        // element into non-breaking ones before the page sees them, whatever the package does.
        let html = """
            <meta charset='utf-8'><style>p { color: red }</style>
            <h2 style="margin: 0">Oak and iron</h2>
            <p>The quote for the
                alcove is
                ready to read.</p>
            <ul>
              <li>Measure</li>
              <li>Book a visit</li>
            </ul>
            <script>window.pastedScriptRan = true</script>
            """
        try await page.run("document.querySelector('.ProseMirror').focus(); getSelection().selectAllChildren(document.querySelector('.ProseMirror'))")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(html, forType: .html)
        NSPasteboard.general.setString("Oak and iron\nThe quote", forType: .string)
        NSApp.sendAction(#selector(NSText.paste(_:)), to: page.editor.webView, from: nil)
        try await page.wait { !page.changes.isEmpty }
        #expect(page.changes.last == "## Oak and iron\n\nThe quote for the alcove is ready to read.\n\n- Measure\n- Book a visit\n")
        #expect(try await page.editor.webView.evaluateJavaScript("window.pastedScriptRan === undefined") as? Bool == true)
    }

    @Test func aPinAsksForItsMenuUnderItsFrameInTheEditor() async throws {
        let page = try await Page()
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        page.editor.container.topInset = 52
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await page.load(Array(repeating: "Some text.", count: 80).joined(separator: "\n\n") + "\n")
        let id = try #require(page.editor.noteID)
        page.editor.setHeader(Self.header("Review the findings", id: id))
        var menus: [(PageHeaderMenu, ItemID, CGRect)] = []
        page.editor.onHeaderEvent = { if case .menu(let menu, let item, let rect) = $0 { menus.append((menu, item, rect)) } }
        try await page.run("window.scrollTo(0, 30)")
        let pin = try await Self.rect("#ItemStatusPin", in: page)
        let viewport = try #require(try await page.editor.webView.evaluateJavaScript("window.innerHeight") as? Double)
        try await page.run("document.getElementById('ItemStatusPin').dispatchEvent(new PointerEvent('pointerdown', { button: 0, bubbles: true, cancelable: true }))")
        try await page.run("document.getElementById('ItemParentPin').click()")
        try await page.wait { menus.count == 2 }
        #expect(menus.map(\.0) == [.status, .parent])
        #expect(menus.allSatisfy { $0.1 == id })
        // The page's window starts below what covers the web view's top; the frame is in the container's terms.
        let covered = page.editor.webView.bounds.height - viewport
        let expected = page.editor.container.convert(CGRect(x: pin[0], y: pin[1] + covered, width: pin[2], height: pin[3]), from: page.editor.webView)
        #expect(abs(menus[0].2.minX - expected.minX) < 0.5 && abs(menus[0].2.minY - expected.minY) < 0.5)
        #expect(abs(menus[0].2.width - pin[2]) < 0.5 && abs(menus[0].2.height - pin[3]) < 0.5)
        #expect(menus[0].2.minY > 52 - 30, "the pin lies below the covered top, less what has scrolled")
    }

    /// An item's page as the app shows it: the native view, reading the item from the library, over the page.
    @Observable final class Shown {
        var id: ItemID
        init(_ id: ItemID) { self.id = id }
    }

    struct PageHost: View {
        let library: any ItemLibrary
        let editor: EditorController
        let drafts: DetailsPresentation
        let shown: Shown

        var body: some View {
            if let item = library.item(shown.id) {
                NotePage(item: item, editor: editor, headerDrafts: drafts)
            }
        }
    }

    /// The preview library's ticket on a page in a window of its own, driven through the page.
    final class HostedPage {
        let library: MarfaLibrary
        let ticket = ItemPreviewFixtures.ticketID
        let page: Harness<MarfaLibrary>
        let drafts = DetailsPresentation()
        let shown: Shown
        let window: NSWindow

        init(library: MarfaLibrary = ItemPreviewFixtures.library, showing id: ItemID = ItemPreviewFixtures.ticketID) async throws {
            self.library = library
            page = try await Harness(library: library)
            // The preview library reads its copy as it opens.
            try await page.wait { library.isLoaded }
            page.editor.titleDrafts = drafts
            shown = Shown(id)
            window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PageHost(library: library, editor: page.editor, drafts: drafts, shown: shown)
                .environment(\.library, library))
            window.makeKeyAndOrderFront(nil)
            try await waitForTitle(try #require(library.item(id)).title)
        }

        func close() {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }

        /// Hands over every page's edits, as quitting or changing library does, or as deleting a note does when
        /// `leaving` is false.
        func flushAll(leaving: Bool = true) async -> Bool {
            await withCheckedContinuation { continuation in EditorController.flushAll(leaving: leaving) { continuation.resume(returning: $0) } }
        }

        func value(_ script: String) async throws -> Any? {
            try await page.editor.webView.evaluateJavaScript(script)
        }

        func shownTitle() async throws -> String? {
            try await value("document.getElementById('ItemPageTitle')?.textContent") as? String
        }

        func titleError() async throws -> Bool? {
            try await value("!document.querySelector('.item-title-error').hidden") as? Bool
        }

        func type(_ text: String) async throws {
            #expect(window.makeFirstResponder(page.editor.webView))
            try await page.run("""
                document.getElementById('ItemPageTitle').focus()
                document.execCommand('selectAll'); document.execCommand('insertText', false, \(EditorTests.json(text)))
                """)
            try await page.wait { self.drafts.draft(for: self.ticket, key: "title").text == text }
        }

        func pressReturn() async throws {
            try await page.run("document.getElementById('ItemPageTitle').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }))")
        }

        /// Waits for something the page or the window does in its own time.
        func waitFor(_ what: String, _ condition: () async throws -> Bool) async throws {
            try #require(try await eventuallyAsking(condition), "waiting for \(what)")
        }

        func waitForTitle(_ title: String) async throws {
            try await waitFor("the page to show the title \(title)") { try await self.shownTitle() == title }
        }
    }

    @Test func theTitleIsSavedFromThePageAndARefusalIsShownThere() async throws {
        let host = try await HostedPage()
        defer { host.close() }
        let library = host.library, ticket = host.ticket, page = host.page
        let status = try await host.value("document.querySelector('#ItemStatusPin .item-pin-label').textContent") as? String
        #expect(status == "In Progress")

        // Return saves the title as the item's, once, and the note's text takes the keyboard.
        var commits = 0
        let handler = page.editor.onHeaderEvent
        page.editor.onHeaderEvent = { event in
            if case .titleCommit = event { commits += 1 }
            handler(event)
        }
        try await host.type("Review the photographs")
        try await page.wait { page.editor.isEditingTitle }
        try await host.pressReturn()
        try await page.wait { library.item(ticket)?.title == "Review the photographs" }
        try await page.wait { !page.editor.isEditingTitle }
        let writing = try await host.value("document.activeElement?.matches('.ProseMirror') === true") as? Bool
        #expect(writing == true)
        #expect(!host.drafts.draft(for: ticket, key: "title").isDirty)
        // Anything the blur posted arrives before the answer to a script run after it.
        _ = try await host.value("1")
        #expect(commits == 1, "leaving the title after Return does not save it again")

        // The change is undone as the app's own, from the window's undo manager, and the page shows it.
        #expect(host.window.undoManager?.canUndo == true)
        host.window.undoManager?.undo()
        try await page.wait { library.item(ticket)?.title == "Review the findings" }
        try await host.waitForTitle("Review the findings")

        // A title the library refuses, as a Marfa library does an empty one, stays as typed, with the reason, and
        // survives moving to another note and back.
        try await host.type("")
        try await host.pressReturn()
        try await host.waitFor("the page to show the refusal") { try await host.titleError() == true }
        #expect(library.item(ticket)?.title == "Review the findings")
        #expect(try await host.shownTitle() == "")
        host.shown.id = ItemPreviewFixtures.noteID
        try await host.waitForTitle("Field notes")
        #expect(try await host.titleError() == false)
        host.shown.id = ticket
        try await host.waitForTitle("")
        #expect(try await host.titleError() == true)

        // Discard Changes gives the saved title back.
        try await page.run("document.querySelector('.item-title-error button').click()")
        try await host.waitForTitle("Review the findings")
        #expect(try await host.titleError() == false)
        #expect(library.item(ticket)?.title == "Review the findings")
    }

    @Test func aChangeFromOutsideReachesThePageAsItIsNow() async throws {
        let host = try await HostedPage()
        defer { host.close() }
        for round in 1...5 {
            let title = "Outside title \(round)"
            #expect(host.library.setItemProperty(host.ticket, key: "title", value: .string(title), undoManager: nil))
            try await host.waitForTitle(title)
        }
        // Deleted elsewhere, the note becomes read-only and its header gives way to the banner.
        host.library.delete([host.ticket], undoManager: nil)
        try await host.page.wait { !host.page.editor.isEditable }
        try await host.waitFor("the header to hide") { try await host.value("document.getElementById('item-header').hidden") as? Bool == true }
        host.library.recover([host.ticket], undoManager: nil)
        try await host.page.wait { host.page.editor.isEditable }
        try await host.waitFor("the header to show") { try await host.value("document.getElementById('item-header').hidden") as? Bool == false }
    }
}
