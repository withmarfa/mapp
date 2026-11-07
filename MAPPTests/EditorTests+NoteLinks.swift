import AppKit
import Foundation
import Marfa
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

    @Test func aLinkTheCoreReadsAsTwoDoesNotDropTheMarksOfTheNotesOtherLinks() async throws {
        let page = try await Page()
        _ = addNotes(["Plan"], to: page)
        try await page.load("Intro\n")
        let note = try #require(page.editor.noteID)
        // Inkkit read `[[Plan\]] and [[B]]` as one link with an escape; the core finds two in the text it is posted.
        let links = "[{ raw: \(json("[[Plan\\]] and [[B]]")) }, { raw: \(json("[[Plan]]")) }, { raw: \(json("[[Nowhere]]")) }]"
        let answer = try await resolve(page, note, links)
        #expect(answer.links.map(\.missing) == [false, false, true], "one answer for each link posted, the unreadable one not marked missing")
    }

    /// The `resolve` reply: an entry for each link posted, and the icon images those entries name.
    private struct Resolved {
        struct Entry { var missing: Bool; var icon: String?; var tone: String? }
        var links: [Entry]
        var icons: [String: String]
    }

    private func resolve(_ page: Page, _ note: ItemID, _ links: String) async throws -> Resolved {
        let reply = try #require(try await ask(page, "{ type: 'resolve', item: \(json(note.rawValue)), links: \(links) }") as? [String: Any])
        let entries = try #require(reply["links"] as? [[String: Any]])
        let icons = try #require(reply["icons"] as? [String: String])
        return Resolved(
            links: entries.map { Resolved.Entry(missing: $0["missing"] as? Bool ?? false, icon: $0["icon"] as? String, tone: $0["tone"] as? String) },
            icons: icons)
    }

    private func raw(_ texts: String...) -> String { "[" + texts.map { "{ raw: \(json($0)) }" }.joined(separator: ", ") + "]" }

    @Test func aLinkAnswerNamesTheTypeIconAndToneOfTheNoteItBinds() async throws {
        let page = try await Page()
        let ids = addNotes(["Plan", "Errands", "Chores"], to: page)
        for id in ids.dropFirst() { page.library.items[page.library.items.firstIndex { $0.id == id }!].type = TypeID("core.task") }
        try await page.load("Intro\n")
        let note = try #require(page.editor.noteID)
        let icon = TypeIconKey.value(for: "lucide:list-checks")
        let answer = try await resolve(page, note, raw("[[Plan]]", "[[Errands]]", "[[Chores]]", "[[Nowhere]]"))
        #expect(answer.links.map(\.missing) == [false, false, false, true])
        #expect(answer.links[0].icon == TypeIconKey.value(for: nil), "a type with no icon of its own gets the glyph every list gives it")
        #expect(answer.links[0].tone == TypeTone.neutral.rawValue)
        #expect(answer.links[1].icon == icon && answer.links[2].icon == icon)
        #expect(answer.links[1].tone == TypeTone(icon: "lucide:list-checks").rawValue)
        #expect(answer.links[3].icon == nil && answer.links[3].tone == nil, "a missing link names no type")
        #expect(answer.icons.count == 2, "each icon's image goes once however many links name it")
        #expect(answer.icons[icon]?.hasPrefix("data:image/png;base64,") == true)
    }

    @Test func aLinkToAnAmbiguousUnresolvedOrBinnedNoteNamesNoType() async throws {
        let page = try await Page()
        let twins = addNotes(["Twin", "Twin", "Gone"], to: page)
        let gone = try #require(page.library.items.firstIndex { $0.id == twins[2] })
        page.library.items[gone].state = .trashed
        try await page.load("Intro\n")
        let note = try #require(page.editor.noteID)
        let answer = try await resolve(page, note, raw("[[Twin]]", "[[Gone]]"))
        #expect(answer.links[0].missing == false && answer.links[0].tone == nil, "two notes answer to it, so there is no one type")
        #expect(answer.links[1].missing == true && answer.links[1].icon == nil && answer.links[1].tone == nil)
        #expect(answer.icons.isEmpty)
    }

    @Test func anIconThatCannotBeDrawnLeavesTheToneAndAnswersEveryLink() async throws {
        let requests = NoteRequests()
        requests.readings = { links, _ in
            links.map { _ in LinkReading(missing: false, type: .init(icon: "lucide:list-checks", tone: .teal)) }
        }
        requests.drawIcon = { _ in nil }
        let links = [NoteLink(linkText: "[[A]]"), nil, NoteLink(linkText: "[[B]]")]
        let reply = await requests.answerLinks(links, in: ItemID("n"))
        #expect(reply.links.map(\.tone) == ["teal", nil, "teal"])
        #expect(reply.links.allSatisfy { $0.icon == nil } && reply.icons.isEmpty)
        requests.readings = { _, _ in [] }
        let short = await requests.answerLinks(links, in: ItemID("n"))
        #expect(short.links.count == 3 && short.links.allSatisfy { !$0.missing && $0.tone == nil }, "a count that does not line up marks nothing")
    }

    @Test func linkToNoteWaitsForTheChoiceAndAnswersWithTheLink() async throws {
        let page = try await Page()
        let ids = addNotes(["Garden ideas"], to: page)
        try await page.load("Intro\n")
        let current = try #require(page.editor.noteID)
        try await page.run("window.pick = window.webkit.messageHandlers.notes.postMessage({ type: 'pick', item: '\(current.rawValue)' })")
        try await page.wait { page.editor.linkRequest != nil }
        #expect(page.editor.linkRequest?.note == current)
        await page.editor.finishLinkRequest(choosing: ids[0])
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

    /// The note the library binds a `[[link]]` to, or nil where it binds none.
    private func bound(_ link: String, in library: FakeItemLibrary) async -> ItemID? {
        guard let target = linkParts(in: link).first?.target else { return nil }
        let answer = await library.linkAnswers(of: [target], in: nil)?.first
        return answer?.state == .bound ? answer?.item : nil
    }

    @Test func choosingBetweenNotesWithTheSameTitleLinksToTheOneChosen() async throws {
        let page = try await Page()
        let older = page.library.add("Garden\n")
        page.library.add("garden\n")
        try await page.load("Intro\n")
        _ = try await pending(page)
        await page.editor.finishLinkRequest(choosing: older.id)
        let link = try #require(try await answer(page), "a note that can be named is linked")
        #expect(await bound(link, in: page.library) == older.id, "\(link) names the note chosen and no other")
    }

    @Test func aTargetRenamedWhileThePickerIsOpenIsLinkedByItsNewTitle() async throws {
        let page = try await Page()
        let target = page.library.add("Garden\n")
        try await page.load("Intro\n")
        _ = try await pending(page)
        let index = try #require(page.library.items.firstIndex { $0.id == target.id })
        page.library.items[index].title = "Allotment"
        try #require(page.library.item(target.id)?.title == "Allotment")
        await page.editor.finishLinkRequest(choosing: target.id)
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
                #expect(await bound("[[\(name)]]", in: library) == owner.id, "suggesting \(name) for \(query)")
            }
        }
        _ = try await pending(page)
        #expect(await page.editor.finishLinkRequest(choosing: chosen.id))
        let link = try #require(try await answer(page))
        #expect(await bound(link, in: library) == chosen.id, "\(link) names the note chosen")
    }

    @Test func aLinkByIdentityShowsAnyTitleAndNamesTheNoteThatDeclaresIt() async throws {
        let page = try await Page()
        let titles = ["A|B", "A#B", "A]B", "[Draft]", "[[c", "c[[", "a]]b", "back\\slash", "Café 日本語", "line\nbreak"]
        for title in titles {
            let note = page.library.add("\(title)\nBody\n")
            // A title a link cannot spell is named by identity; nothing is escaped, since a link has no escape.
            let link = try #require(await page.library.bodyLink(to: note.id, in: nil), "\(title.debugDescription)")
            let parts = try #require(linkParts(in: link).first)
            #expect(parts.text == link)
            #expect(await bound(link, in: page.library) == note.id, "\(link)")
        }
        let tricky = try #require(page.library.items.first { $0.title == "A]B" })
        #expect(await page.library.bodyLink(to: tricky.id, in: nil) == "[[A]B]]", "Inkkit 0.7.2 and the core both read a lone bracket as part of the name")
        let slash = try #require(page.library.items.first { $0.title == "back\\slash" })
        #expect(await page.library.bodyLink(to: slash.id, in: nil) == "[[back\\slash]]", "a backslash is part of the name")
        let bar = try #require(page.library.items.first { $0.title == "A|B" })
        #expect(await page.library.bodyLink(to: bar.id, in: nil) == "[[\(bar.id.rawValue)|A|B]]", "the bar splits a title link, so the identity names it and the label keeps the bar")
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
