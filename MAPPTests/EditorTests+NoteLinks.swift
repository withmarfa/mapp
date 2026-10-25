import AppKit
import Foundation
import Testing
import WebKit
@testable import MAPP

/// Linking to notes from the page.
extension EditorTests {
    // MARK: Notes the page links to

    private func addNotes(_ titles: [String], to page: Page) -> [ItemID] {
        titles.map { page.library.add($0 + "\n").id }
    }

    private func ask(_ page: Page, _ request: String) async throws -> Any? {
        try await page.editor.webView.callAsyncJavaScript(
            "return await window.webkit.messageHandlers.notes.postMessage(\(request))", arguments: [:], in: nil, contentWorld: .page)
    }

    @Test func theNotesAreOfferedAfterDoubleBracketsFromTheLibrary() async throws {
        let page = try await Page()
        _ = addNotes(["Garden ideas", "Bike service", "Gardening tools"], to: page)
        try await page.load("Intro\n")
        let names = try await ask(page, "{ type: 'suggest', query: 'gard' }") as? [String]
        #expect(Set(names ?? []) == ["Garden ideas", "Gardening tools"])
        #expect(try await ask(page, "{ type: 'suggest', query: 'zzz' }") as? [String] == [])
        let unread = try await ask(page, "{ type: 'nonsense' }")
        #expect(unread == nil || unread is NSNull, "a request that cannot be read is answered, not left waiting")
    }

    @Test func linkToNoteWaitsForTheChoiceAndAnswersWithTheLink() async throws {
        let page = try await Page()
        let ids = addNotes(["Garden ideas"], to: page)
        try await page.load("Intro\n")
        let current = try #require(page.editor.noteID)
        try await page.run("window.pick = window.webkit.messageHandlers.notes.postMessage({ type: 'pick', item: '\(current.rawValue)' })")
        try await page.wait { page.editor.linkRequest != nil }
        #expect(page.editor.linkRequest?.note == current)
        page.editor.finishLinkRequest(choosing: ids[0])
        #expect(page.editor.linkRequest == nil)
        let link = try await page.editor.webView.callAsyncJavaScript("return await window.pick", arguments: [:], in: nil, contentWorld: .page)
        #expect(link as? String == "[[Garden ideas]]")
    }

    @Test func linkToNoteDeclinedClosedOrAskedFromAnotherNoteAnswersWithNothing() async throws {
        let page = try await Page()
        let ids = addNotes(["Garden ideas"], to: page)
        try await page.load("Intro\n")
        let current = try #require(page.editor.noteID)
        func ask(from item: ItemID) async throws {
            try await page.run("window.pick = window.webkit.messageHandlers.notes.postMessage({ type: 'pick', item: '\(item.rawValue)' })")
        }
        func answered() async throws -> Bool {
            let value = try await page.editor.webView.callAsyncJavaScript("return await window.pick", arguments: [:], in: nil, contentWorld: .page)
            return value == nil || value is NSNull
        }
        try await ask(from: current)
        try await page.wait { page.editor.linkRequest != nil }
        page.editor.cancelLinkRequest()
        #expect(try await answered(), "declining answers the page with nothing")

        try await ask(from: current)
        try await page.wait { page.editor.linkRequest != nil }
        page.editor.close()
        #expect(page.editor.linkRequest == nil)
        #expect(try await answered(), "leaving the note answers the page with nothing")

        try await page.load("Another\n")
        try await ask(from: ids[0])
        #expect(try await answered())
        #expect(page.editor.linkRequest == nil, "a command typed in a note no longer shown opens nothing")

        let editor = page.editor
        try await ask(from: try #require(editor.noteID))
        try await page.wait { editor.linkRequest != nil }
        editor.windowWent()
        #expect(try await answered(), "closing the window answers the page with nothing")
    }

    @Test func theSlashMenuAndItsWordsComeFromTheAppsStrings() async throws {
        let page = try await Page()
        try await page.load("\n")
        let labels = try await page.editor.webView.evaluateJavaScript("window.mappLabels") as? [String: String]
        #expect(labels?["linkToNote"] == "Link to Note")
        #expect(labels?["slashTable"] == "Table")
        #expect(labels?["suggestionsLoading"] == "Loading…")
        #expect(labels?["suggestionsEmpty"] == "No Results")
    }

    @Test func quotesAndDashesStayAsTypedBecauseSmartPunctuationIsOff() async throws {
        let page = try await Page()
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await page.load("\n")
        page.editor.focus()
        // WebKit applies the system's smart quotes and dashes to editing commands, as to any Mac text field. That is
        // the person's setting, not the page's, so it is turned off here to see what the page itself does.
        let substitutions = [#selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)), #selector(NSTextView.toggleAutomaticDashSubstitution(_:))]
        let switchedOff = substitutions.filter { action in
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            _ = page.editor.webView.validateUserInterfaceItem(item)
            guard item.state == .on else { return false }
            _ = page.editor.webView.perform(action, with: nil)
            return true
        }
        defer { for action in switchedOff { _ = page.editor.webView.perform(action, with: nil) } }
        // One character at a time through the editing commands, as the keyboard's text input reaches the page.
        for character in "\"quoted\" it's -- done" {
            _ = try await page.editor.webView.evaluateJavaScript("document.execCommand('insertText', false, \(json(String(character)))); 0")
        }
        try await page.wait { page.changes.last?.contains("done") == true }
        #expect(page.changes.last == "\"quoted\" it's -- done\n")
    }

    // MARK: Link to Note keeps which note was chosen

    private func pending(_ page: Page) async throws -> ItemID {
        let current = try #require(page.editor.noteID)
        try await page.run("window.pick = window.webkit.messageHandlers.notes.postMessage({ type: 'pick', item: '\(current.rawValue)' })")
        try await page.wait { page.editor.linkRequest != nil }
        return current
    }

    /// What the page was answered, or "PENDING" if it is still waiting after a moment.
    private func answer(_ page: Page) async throws -> String? {
        let script = "return await Promise.race([window.pick, new Promise(done => setTimeout(() => done('PENDING'), 1500))])"
        let value = try await page.editor.webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        return value as? String
    }

    /// What the library resolves a `[[link]]` to.
    private func resolution(of link: String, in library: FakeItemLibrary) -> NoteReferenceResolution? {
        guard link.hasPrefix("[["), link.hasSuffix("]]") else { return nil }
        return library.resolveLink(NoteLink(reading: String(link.dropFirst(2).dropLast(2))), in: .mint())
    }

    @Test func choosingBetweenNotesWithTheSameTitleLinksToTheOneChosen() async throws {
        let page = try await Page()
        let older = page.library.add("Garden\n")
        page.library.add("garden\n")
        try await page.load("Intro\n")
        _ = try await pending(page)
        page.editor.finishLinkRequest(choosing: older.id)
        let link = try #require(try await answer(page), "a note that can be named is linked")
        #expect(resolution(of: link, in: page.library) == .resolved(older.id), "\(link) names the note chosen and no other")
    }

    @Test func aTargetRenamedWhileThePickerIsOpenIsLinkedByItsNewTitle() async throws {
        let page = try await Page()
        let target = page.library.add("Garden\n")
        try await page.load("Intro\n")
        _ = try await pending(page)
        let index = try #require(page.library.items.firstIndex { $0.id == target.id })
        page.library.items[index].title = "Allotment"
        try #require(page.library.item(target.id)?.title == "Allotment")
        page.editor.finishLinkRequest(choosing: target.id)
        #expect(try await answer(page) == "[[Allotment]]")
    }

    @Test func everySuggestionAndTheLinkForAnyNoteResolvesToThatNote() async throws {
        let page = try await Page()
        let identity = "11111111-1111-4111-8111-111111111111"
        let chosen = page.library.add("\(identity)\nBody\n")
        page.library.add("Garden\n")
        try await page.load("Intro\n")
        let library = page.library
        let index = NoteLinks.Index()
        for query in ["", "1111", "gar", "oth"] {
            for name in await library.noteNames(matching: query, using: index) {
                let owner = try #require(library.items.first { $0.title == name }, "\(name)")
                #expect(!name.isEmpty)
                #expect(resolution(of: "[[\(name)]]", in: library) == .resolved(owner.id), "suggesting \(name) for \(query)")
            }
        }
        _ = try await pending(page)
        #expect(page.editor.finishLinkRequest(choosing: chosen.id))
        let link = try #require(try await answer(page))
        #expect(resolution(of: link, in: library) == .resolved(chosen.id), "\(link) names the note chosen")
    }

    @Test func aLinkByIdentityWithAnEscapedTitleResolvesToTheNoteThatDeclaresIt() async throws {
        let page = try await Page()
        let identity = "22222222-2222-4222-8222-222222222222"
        let declared = page.library.add("Work on it\n", id: ItemID(identity))
        for title in ["A|B", "A#B", "A]B", "[Draft]", "back\\slash", "Café 日本語", "line\nbreak"] {
            let link = NoteLinks.identityLink(to: identity, titled: title)
            #expect(resolution(of: link, in: page.library) == .resolved(declared.id), "\(link)")
        }
        #expect(NoteLinks.identityLink(to: identity, titled: "A]B") == "[[\(identity)|A\\]B]]")
    }

    @Test func aLinkRequestAfterTheWindowWentIsAnsweredWithNothing() async throws {
        let page = try await Page()
        try await page.load("Intro\n")
        let editor = page.editor
        editor.windowWent()
        let current = try #require(editor.noteID)
        try await page.run("window.pick = window.webkit.messageHandlers.notes.postMessage({ type: 'pick', item: '\(current.rawValue)' })")
        #expect(try await answer(page) == nil)
        #expect(editor.linkRequest == nil)
    }

    @Test func loadingAnotherNoteAnswersAPendingLinkRequestOnce() async throws {
        let page = try await Page()
        page.library.add("Garden\n")
        try await page.load("Intro\n")
        _ = try await pending(page)
        try await page.load("Another note\n")
        #expect(page.editor.linkRequest == nil, "the request ended with the note it was typed in")
        #expect(try await answer(page) == nil, "the page was answered")
    }

    private func json(_ text: String) -> String {
        String(decoding: (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8), as: UTF8.self)
    }
}
