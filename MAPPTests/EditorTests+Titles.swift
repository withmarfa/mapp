import AppKit
import Foundation
import SwiftUI
import Testing
import WebKit
@testable import MAPP

/// Titles the library refuses, kept and told until they are saved or discarded.
extension EditorTests {
    @Test func aRefusedTitleInAClosedWindowNeverHoldsUpQuittingOrRenamesTheNote() async throws {
        let library = ItemPreviewFixtures.library
        let ticket = ItemPreviewFixtures.ticketID
        _ = try await Self.openAndClose(library, item: ticket) { editor, web in
            _ = try await web.evaluateJavaScript("""
                const title = document.getElementById('ItemPageTitle'); title.focus()
                document.execCommand('selectAll'); document.execCommand('delete')
                title.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true })); 0
                """)
            try #require(try await eventuallyAsking { try await web.evaluateJavaScript("!document.querySelector('.item-title-error').hidden") as? Bool == true })
            // Deleted from another window, so closing this one is allowed: the draft cannot be saved anywhere.
            library.delete([ticket], undoManager: nil)
            #expect(await eventually { !editor.isEditable }, "the page shows the note deleted")
        }
        library.recover([ticket], undoManager: nil)
        let kept = await withCheckedContinuation { continuation in EditorController.flushAll { continuation.resume(returning: $0) } }
        #expect(kept, "a draft no window holds cannot stop quitting")
        #expect(library.notices.waiting.last == nil)
        #expect(library.item(ticket)?.title == "Review the findings")
    }

    @Test func aRefusedEmptyTitleIsToldAsEmpty() async throws {
        let host = try await HostedPage()
        defer { host.close() }
        try await host.type("")
        try await host.pressReturn()
        try await host.waitFor("the page to show the refusal") { try await host.titleError() == true }
        #expect(await !host.flushAll())
        #expect(host.library.notices.waiting.last?.message == "The title for “Review the findings” is empty. Open the item to enter a title or discard your changes.")
    }

    @Test func aRefusedStatusIsForgottenOnMovingToAnotherItem() async throws {
        let host = try await HostedPage()
        defer { host.close() }
        let error = "!document.querySelectorAll('#item-header > .item-error')[0]?.hidden"
        host.drafts.draft(for: host.ticket, key: "status").rejected = true
        try await host.waitFor("the status refusal") { try await host.value(error) as? Bool == true }
        host.shown.id = ItemPreviewFixtures.noteID
        try await host.waitForTitle("Field notes")
        host.shown.id = host.ticket
        try await host.waitForTitle("Review the findings")
        try await host.waitFor("the page to settle") { try await host.value(error) as? Bool != nil }
        #expect(try await host.value(error) as? Bool == false, "a refused status belongs to the item's visit, as it did")
    }

    @Test func refusedTitlesInSeveralWindowsAreToldOnceAndShownWhereTheyAre() async throws {
        let library = ItemPreviewFixtures.library
        let first = try await HostedPage(library: library)
        defer { first.close() }
        let second = try await HostedPage(library: library, showing: ItemPreviewFixtures.noteID)
        defer { second.close() }
        var shown: [ItemID] = []
        first.page.editor.onShowRefusedTitle = { shown.append($0) }
        second.page.editor.onShowRefusedTitle = { shown.append($0) }
        first.drafts.draft(for: first.ticket, key: "title").text = ""
        first.drafts.draft(for: first.ticket, key: "title").isDirty = true
        second.drafts.draft(for: ItemPreviewFixtures.noteID, key: "title").text = ""
        second.drafts.draft(for: ItemPreviewFixtures.noteID, key: "title").isDirty = true
        let kept = await withCheckedContinuation { continuation in EditorController.flushAll { continuation.resume(returning: $0) } }
        #expect(!kept)
        #expect(shown.count == 1, "one refusal is told, and its window shows its item")
        let told = try #require(shown.first)
        let message = try #require(library.notices.waiting.last?.message)
        let window = told == first.ticket ? first.window : second.window
        #expect(message.contains(told == first.ticket ? "“Review the findings”" : "“Field notes”"), "\(message)")
        #expect(window.isKeyWindow || window.isMainWindow || NSApp.orderedWindows.first === window, "the window holding the draft comes forward")
    }

    @Test func aTitleTypedButNotLeftIsSavedBeforeQuittingAndARefusalStopsIt() async throws {
        let host = try await HostedPage()
        defer { host.close() }
        try await host.type("Review before quitting")
        #expect(await host.flushAll())
        try await host.page.wait { host.library.item(host.ticket)?.title == "Review before quitting" }
        #expect(host.library.notices.waiting.last == nil)

        try await host.type("")
        #expect(await !host.flushAll(), "a title that cannot be saved stops quitting rather than being lost")
        #expect(host.library.item(host.ticket)?.title == "Review before quitting")
        #expect(host.library.notices.waiting.last?.message.contains("“Review before quitting” is empty") == true)
        try await host.waitFor("the page to show the refusal") { try await host.titleError() == true }
    }

    @Test func aRefusedTitleForANoteNoLongerShownStillStopsQuittingAndNamesTheNote() async throws {
        let host = try await HostedPage()
        defer { host.close() }
        try await host.type("")
        try await host.pressReturn()
        try await host.waitFor("the page to show the refusal") { try await host.titleError() == true }
        host.shown.id = ItemPreviewFixtures.noteID
        try await host.waitForTitle("Field notes")
        #expect(await !host.flushAll())
        let message = try #require(host.library.notices.waiting.last?.message)
        #expect(message.contains("“Review the findings” is empty"), "\(message)")
        // Deleting a note keeps the window, so a refused title is tried again but stops nothing.
        host.library.notices.answerAll()
        #expect(await host.flushAll(leaving: false))
        #expect(host.library.notices.waiting.last == nil)
        #expect(host.drafts.draft(for: host.ticket, key: "title").rejected)
    }

    @Test func closingTheWindowWithARefusedTitleIsCancelledAndSaysWhy() async throws {
        let host = try await HostedPage()
        defer { host.close() }
        try await host.type("")
        try await host.pressReturn()
        try await host.waitFor("the page to show the refusal") { try await host.titleError() == true }
        host.window.performClose(nil)
        try await host.waitFor("the refusal to be told") { host.library.notices.waiting.last != nil }
        #expect(host.library.notices.waiting.last?.message.contains("“Review the findings” is empty") == true)
        #expect(host.window.isVisible, "the window stays open with the title that could not be saved")
    }

    @Test func aTitleTheLibraryCannotSetIsReadOnlyAndARefusalSaysWhyInItsTerms() async throws {
        let firstLine = FakeItemLibrary.note("Shopping list", modified: .now)
        var ticket = FakeItemLibrary.note("Review the findings", modified: .now)
        ticket.titleRule = .property("title")
        let library = FakeItemLibrary(items: [firstLine, ticket], bodies: [firstLine.id: "Shopping list\n", ticket.id: "Notes\n"])
        let editor = EditorController(library: library)
        let drafts = DetailsPresentation()
        editor.titleDrafts = drafts
        let shown = Shown(firstLine.id)
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PageHost(library: library, editor: editor, drafts: drafts, shown: shown)
            .environment(\.library, library))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        func value(_ script: String) async throws -> Any? { try await editor.webView.evaluateJavaScript(script) }
        func waitFor(_ what: String, _ condition: () async throws -> Bool) async throws {
            try #require(try await eventuallyAsking(condition), "waiting for \(what)")
        }
        let editable = "document.getElementById('ItemPageTitle').getAttribute('contenteditable')"
        try await waitFor("the first-line title") { try await value("document.getElementById('ItemPageTitle')?.textContent") as? String == "Shopping list" }
        #expect(try await value(editable) as? String == "false", "a library without files cannot give a first-line title another")

        shown.id = ticket.id
        try await waitFor("the property title") { try await value("document.getElementById('ItemPageTitle').textContent") as? String == "Review the findings" }
        #expect(try await value(editable) as? String == "plaintext-only")
        #expect(window.makeFirstResponder(editor.webView))
        _ = try await value("""
            const title = document.getElementById('ItemPageTitle'); title.focus()
            document.execCommand('selectAll'); document.execCommand('insertText', false, 'Review the photographs')
            title.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true })); 0
            """)
        try await waitFor("the refusal") { try await value("!document.querySelector('.item-title-error').hidden") as? Bool == true }
        let reason = try await value("document.querySelector('.item-title-error .item-error').textContent") as? String
        #expect(reason?.contains("file name") == false, "a library without files does not talk about file names: \(reason ?? "")")
    }
}
