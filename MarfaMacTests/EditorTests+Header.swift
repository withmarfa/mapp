import AppKit
import Foundation
import SwiftUI
import Testing
import WebKit
@testable import MarfaMac

/// The item header the page draws above the item.
extension EditorTests {
    // MARK: The item header

    /// A new selection in the main window leaves the head on the item whose text the page still holds until that text
    /// is handed over, so typing in the wait never shows under the head of an item it does not reach.
    @Test @MainActor func theHeadStaysOnTheItemThePageHoldsUntilItsTextIsHandedOver() async throws {
        let library = FakeItemLibrary()
        let first = library.add("First\n")
        let second = library.add("Second\n")
        let page = try await Page(library: library)
        page.editor.onChange = { [library] id, text, read in library.updateBody(of: id, to: text, readAt: read) }
        page.editor.showHeader(ItemPageHeader.heldHeader(of: page.editor, in: library, drafts: DetailsPresentation()))
        try await page.show(first.id)
        try await page.wait { page.editor.header?.item == first.id.rawValue }
        let leaving = page.editor.generation
        try await page.run("""
            window.held = true
            const flush = window.editor.flush.bind(window.editor)
            window.editor.flush = generation => {
                if (window.held) return { commandError: 'composition', message: 'Text composition is in progress' }
                return generation === \(leaving) ? 'First, typed\\n' : flush(generation)
            }
            """)

        // As the main window's page does when the selection moves.
        page.editor.select(try #require(library.item(second.id)))
        try await Task.sleep(for: .milliseconds(300))
        #expect(page.editor.header?.item == first.id.rawValue, "the head waits for the text on the page")
        #expect(page.editor.pageItemID == first.id)

        try await page.run("window.held = false")
        try await page.wait { page.editor.pageItemID == second.id && page.editor.header?.item == second.id.rawValue }
        #expect(library.body(of: first.id)?.text == "First, typed\n")
        #expect(library.body(of: second.id)?.text == "Second\n")
    }

    static func header(_ title: String, id: ItemID = ItemID("note")) -> PageHeader {
        PageHeader(item: id.rawValue, title: title, draft: nil, titleRejected: false,
                   titleRefusal: "The title could not be saved.", editable: true,
                   kicker: .init(PageHead.Kicker(typeName: "Task", typeIcon: "lucide:list-checks", changesType: true, flags: [.readOnly])),
                   status: .init(label: "In Progress", enabled: true), parent: .init(label: "Field Research", enabled: true),
                   pins: [],
                   rows: [PropertyRow(id: "status", label: "Status", value: .status), PropertyRow(id: "child-of", label: "Parent", value: .parent)],
                   showMore: "Show 0 More", linked: [], showsText: true, showMoreLinked: "Show 0 More", interfaceTextSize: 13, titleLines: 2,
                   chips: .init(looks: .defaults))
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
        try await page.wait { page.editor.pageItemID == note.id }
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

    @Test func anUpdateForTheItemJustLeftCannotReloadIt() async throws {
        let library = FakeItemLibrary()
        let first = library.add("First item\n")
        let second = library.add("Second item\n")
        let page = try await Page(library: library)
        page.editor.load(try #require(library.item(first.id)))
        _ = try await page.editor.webView.evaluateJavaScript("1")
        page.editor.load(try #require(library.item(second.id)))
        try await page.wait { page.editor.pageItemID == second.id }
        _ = try await page.editor.webView.evaluateJavaScript("1")
        page.editor.itemChanged(try #require(library.item(first.id)))
        _ = try await page.editor.webView.evaluateJavaScript("1")
        _ = try await page.editor.webView.evaluateJavaScript("1")
        #expect(page.editor.pageItemID == second.id)
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
        #expect(editor.pageItemID == nil)
        #expect(!editor.hasItem)

        source.setBody("Recovered body\n", of: item.id, version: 2)
        if versionChanged {
            item.version = ItemVersion(2)
            source.send(.upserted([item]))
        } else {
            source.sendBody(of: item.id)
        }
        try #require(await eventually { library.body(of: item.id)?.text == "Recovered body\n" })
        editor.itemChanged(try #require(library.item(item.id)))
        try #require(await eventually { editor.pageItemID == item.id })
        #expect(editor.hasItem)
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
            let other = try #require(library.items(in: .library).first { $0.id != item.id && !$0.isFile })
            source.setBody("Other body\n", of: other.id)
            source.sendBody(of: other.id)
            try #require(await eventually { library.body(of: other.id) != nil })
            editor.load(other)
            try #require(await eventually { editor.pageItemID == other.id })
        }
        let selected = editor.pageItemID
        source.setBody("Recovered body\n", of: item.id)
        source.sendBody(of: item.id)
        try #require(await eventually { library.body(of: item.id) != nil })
        editor.itemChanged(item)
        _ = try await editor.webView.evaluateJavaScript("1")
        #expect(editor.pageItemID == selected)
        #expect(editor.hasItem == !close)
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
        let id = try #require(page.editor.pageItemID)
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
    @Test func htmlCopiedFromAWebPageIsPastedIntoTheItemAsReadableText() async throws {
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

    @Test func aRightClickOnARowOpensTheRowsMenuInPlaceOfWebKits() async throws {
        let page = try await Page()
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await page.load("Some text.\n")
        let id = try #require(page.editor.pageItemID)
        var header = Self.header("Review the findings", id: id)
        header.rows.append(PropertyRow(id: "repo", label: "Repo", value: .text("withmarfa/marfa-mac")))
        page.editor.setHeader(header)
        var menus: [String] = []
        page.editor.onHeaderEvent = { event in
            if case .fieldMenu(let row, _, _, _) = event { menus.append(row) }
        }
        try #require(await eventuallyAsking { (try? await Self.rect("[data-row='repo']", in: page)) != nil })
        let prevented = try await page.editor.webView.evaluateJavaScript("""
            (() => { const e = new MouseEvent('contextmenu', { bubbles: true, cancelable: true });
              document.querySelector('[data-row="repo"] .item-prop-value').dispatchEvent(e); return e.defaultPrevented })()
            """) as? Bool
        #expect(prevented == true, "WebKit's own menu does not open")
        try await page.wait { menus == ["repo"] }
        #expect(page.editor.menuRow == nil)
        try await page.run("document.querySelector('p').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true }))")
        _ = try await page.editor.webView.evaluateJavaScript("1")
        #expect(page.editor.menuRow == nil, "a menu elsewhere offers no row")
        #expect(menus == ["repo"])
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
                ItemPage(item: item, editor: editor, headerDrafts: drafts)
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

        /// Hands over every page's edits, as quitting or changing library does, or as deleting an item does when
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

        // Return saves the title as the item's, once, and the item's text takes the keyboard.
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
        // survives moving to another item and back.
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
        // Deleted elsewhere, the item becomes read-only and its head stays, with the title locked.
        let titleEditable = "document.getElementById('ItemPageTitle').getAttribute('contenteditable')"
        host.library.delete([host.ticket], undoManager: nil)
        try await host.page.wait { !host.page.editor.isEditable }
        try await host.waitFor("the title to lock") { try await host.value(titleEditable) as? String == "false" }
        #expect(try await host.value("document.getElementById('item-header').hidden") as? Bool == false)
        host.library.recover([host.ticket], undoManager: nil)
        try await host.page.wait { host.page.editor.isEditable }
        try await host.waitFor("the title to unlock") { try await host.value(titleEditable) as? String == "plaintext-only" }
    }
}
