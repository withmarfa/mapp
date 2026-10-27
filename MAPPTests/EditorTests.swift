import AppKit
import Foundation
import PDFKit
import SwiftUI
import Testing
import WebKit
@testable import MAPP

/// The editor's page running in real WebKit, driven through the same bridge the app uses.
@Suite(.serialized)
struct EditorTests {
    /// An editor whose page has loaded, reporting each change it makes.
    final class Harness<Library: ItemLibrary> {
        /// The editor holds its library weakly, so the harness keeps the one it loads from.
        let library: Library
        let editor: EditorController
        var changes: [String] = []

        init(library: Library, pictures: WebPictures = .standard) async throws {
            self.library = library
            editor = EditorController(library: library, pictures: pictures)
            editor.onChange = { [unowned self] _, markdown, _ in changes.append(markdown) }
            try await wait { self.editor.isReady }
        }

        /// Shows the item and waits until the page holds it.
        func show(_ id: ItemID) async throws {
            editor.load(try #require(library.item(id)))
            try await wait { self.editor.noteID == id }
            // The page answers every load with its caret; a round trip through it means the load has landed.
            _ = try await editor.webView.evaluateJavaScript("1")
        }

        /// What the page would save, or nil while the note is as it was loaded.
        func markdown() async throws -> String? {
            try await editor.webView.evaluateJavaScript("window.editor.markdown()") as? String
        }

        func run(_ script: String) async throws {
            _ = try await editor.webView.evaluateJavaScript("\(script); 0")
        }

        /// The page's text, once it reads `expected` or when the wait for it gives up.
        func shownText(until expected: String) async throws -> String {
            var shown = ""
            _ = try await eventuallyAsking {
                shown = try await editor.webView.evaluateJavaScript("document.querySelector('.ProseMirror').textContent") as? String ?? ""
                return shown == expected
            }
            return shown
        }

        /// Waits for something the page does in its own time, such as reporting an edit after a pause.
        func wait(_ condition: () -> Bool) async throws {
            try #require(await eventually(condition))
        }
    }

    typealias Page = Harness<FakeItemLibrary>

    let kitchen = """
    # Kitchen quotes

    | Supplier | Quote |
    | --- | ---: |
    | Oak & Iron | £11,850 |

    - [x] Measure the alcove
    - [ ] Book a site visit

    """

    /// A panel that takes the keyboard without activating the app, transparent like `TestWindow`.
    private final class ReadingPanel: NSPanel {
        override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
            super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
            alphaValue = 0
        }

        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    @Test func selectingAnotherItemReturnsTheBodyToReading() async throws {
        let page = try await Page()
        try await page.load("First item")
        try await page.run("window.editor.focus()")
        let editing = try await page.editor.webView.evaluateJavaScript(
            "document.activeElement?.matches('.ProseMirror, .inkkit-plain') === true"
        ) as? Bool
        #expect(editing == true)
        try await page.load("Second item")
        let reading = try await page.editor.webView.evaluateJavaScript(
            "document.activeElement?.matches('.ProseMirror, .inkkit-plain') === true"
        ) as? Bool
        #expect(reading == false)
        let outline = try await page.editor.webView.evaluateJavaScript(
            "getComputedStyle(document.querySelector('.ProseMirror')).outlineStyle"
        ) as? String
        #expect(outline == "none")
    }

    @Test func deferredFocusBelongsToTheRequestedItem() async throws {
        let library = FakeItemLibrary()
        let first = library.add("First")
        let second = library.add("Second")
        let page = try await Page(library: library)
        page.editor.load(try #require(library.item(first.id)))
        page.editor.focus(first.id)
        page.editor.load(try #require(library.item(second.id)))
        try await page.wait { page.editor.noteID == second.id }
        _ = try await page.editor.webView.evaluateJavaScript("1")
        let window = ReadingPanel(contentRect: NSRect(x: 100, y: 100, width: 500, height: 600),
                                  styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        let content = NSView(frame: window.contentLayoutRect)
        let search = NSTextField(frame: NSRect(x: 20, y: 540, width: 250, height: 28))
        content.addSubview(search)
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        #expect(window.makeFirstResponder(search))
        page.editor.webView.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        content.addSubview(page.editor.webView)
        page.editor.pageDidMoveToWindow()
        #expect(window.firstResponder === search.currentEditor())
        let reading = try await page.editor.webView.evaluateJavaScript(
            "document.activeElement?.matches('.ProseMirror, .inkkit-plain') === true"
        ) as? Bool
        #expect(reading == false)
        page.editor.focus(first.id)
        page.editor.load(try #require(library.item(first.id)))
        try await page.wait { page.editor.noteID == first.id }
        let composing = try await page.editor.webView.evaluateJavaScript(
            "document.activeElement?.matches('.ProseMirror, .inkkit-plain') === true"
        ) as? Bool
        #expect(composing == true)
        page.editor.releaseFocus()
        window.contentView = nil
        window.contentView = page.editor.webView
        page.editor.noteChanged(try #require(library.item(first.id)))
        page.editor.pageDidMoveToWindow()
        let reopened = try await page.editor.webView.evaluateJavaScript(
            "document.activeElement?.matches('.ProseMirror, .inkkit-plain') === true"
        ) as? Bool
        #expect(reopened == false)
    }

    @Test func initialLoadingCannotBlockChoosingAnotherNote() async throws {
        let library = FakeItemLibrary()
        let first = library.add("First\n")
        let second = library.add("Second\n")
        let editor = EditorController(library: library)
        editor.load(try #require(library.item(first.id)))
        #expect(!editor.isReady)
        editor.load(try #require(library.item(second.id)))
        #expect(editor.noteID == second.id)
        try #require(await eventually { editor.isReady })
        let source = try await editor.webView.evaluateJavaScript("window.editor.snapshot().text") as? String
        #expect(source == "Second\n")
    }

    @Test func aCapturedFlushReplyIsSavedUnderItsOriginalVersionAfterReload() async throws {
        let library = FakeItemLibrary()
        let note = library.add("Original\n")
        let page = try await Page(library: library)
        page.editor.load(try #require(library.item(note.id)))
        _ = try await page.editor.webView.evaluateJavaScript("1")
        var captured: [String] = []
        page.editor.onChange = { id, text, read in captured.append(text); library.updateBody(of: id, to: text, readAt: read) }
        try await page.run("window.editor.flush = () => 'Pending\\n'")
        let kept = await withCheckedContinuation { continuation in
            page.editor.flush { continuation.resume(returning: $0) }
            library.updateBody(of: note.id, to: "Outside\n")
            page.editor.noteChanged(library.item(note.id)!)
        }
        // The note is still the one being left, so leaving goes ahead.
        #expect(kept)
        #expect(library.notices.waiting.isEmpty)
        #expect(captured == ["Pending\n"])
        // Sent as typed on the version before the outside change, so the source keeps both rather than one over the other.
        #expect(library.bodyWrites.contains { $0.text == "Pending\n" && $0.readAt == note.version })
    }

    /// The page puts a reload off while the person composes, so after outside text reloads the note it can still hold
    /// text of the generation the flush began on, which the flush must still ask for.
    @Test func aFlushRetriedAfterOutsideTextReloadsTheNoteStillAsksThePage() async throws {
        let library = FakeItemLibrary()
        let note = library.add("Original\n")
        let page = try await Page(library: library)
        page.editor.load(try #require(library.item(note.id)))
        _ = try await page.editor.webView.evaluateJavaScript("1")
        var captured: [String] = []
        page.editor.onChange = { id, text, read in captured.append(text); library.updateBody(of: id, to: text, readAt: read) }
        try await page.run("""
            window.flushes = 0
            window.editor.flush = () => { if (window.flushes++ === 0) throw new Error('composition'); return 'Composed\\n' }
            """)
        let kept = await withCheckedContinuation { continuation in
            page.editor.flush { continuation.resume(returning: $0) }
            library.updateBody(of: note.id, to: "Outside\n")
            page.editor.noteChanged(library.item(note.id)!)
        }
        #expect(kept)
        #expect(captured == ["Composed\n"])
        #expect(library.bodyWrites.contains { $0.text == "Composed\n" && $0.readAt == note.version })
    }

    @Test func aRejectedFlushCannotApproveLeavingOrSaveAnotherNotesText() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        try await page.run("window.savedFlush = window.editor.flush; window.editor.flush = () => { throw new Error('composition') }")
        let originalID = page.editor.noteID
        let replacement = page.library.add("Replacement\n")
        let kept = await withCheckedContinuation { continuation in
            page.editor.flush { continuation.resume(returning: $0) }
            page.editor.load(page.library.item(replacement.id)!)
        }
        #expect(page.editor.noteID == originalID)
        #expect(page.changes.isEmpty)
        #expect(!kept)
        #expect(!page.library.notices.waiting.isEmpty)
        try await page.run("window.editor.flush = window.savedFlush")
        let oldGeneration = try await page.editor.webView.evaluateJavaScript("window.editor.snapshot().generation") as? Int
        try await page.load("Replacement\n")
        // The page hands back no text of the note it replaced.
        let handedBack = try await page.editor.webView.callAsyncJavaScript("return window.editor.flush(expected)", arguments: ["expected": try #require(oldGeneration)], in: nil, contentWorld: .page) as? String
        #expect(handedBack == nil)
        #expect(try await page.markdown() == nil)
    }

    /// The page reports each change as it is made, so one whose process ended holds nothing back while it reloads.
    @Test func aPageWhoseProcessEndedDoesNotHoldUpLeaving() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        page.editor.webViewWebContentProcessDidTerminate(page.editor.webView)
        let kept = await withCheckedContinuation { continuation in page.editor.flush { continuation.resume(returning: $0) } }
        #expect(kept)
        try await page.wait { page.editor.isReady }
    }

    /// A page that stops answering is given up on once: the person is told, and trying again goes ahead without
    /// waiting. The text it last reported is already saved, so it is not given back.
    @Test func aPageThatStopsAnsweringIsGivenUpOnAndTold() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        try await page.run("window.editor.flush = () => { const end = Date.now() + 4000; while (Date.now() < end) {} }")
        let kept = await withCheckedContinuation { continuation in page.editor.flush { continuation.resume(returning: $0) } }
        #expect(!kept)
        #expect(page.library.notices.waiting.map(\.text) == [nil])
        let clock = ContinuousClock()
        let start = clock.now
        let keptAgain = await withCheckedContinuation { continuation in page.editor.flush { continuation.resume(returning: $0) } }
        #expect(keptAgain)
        #expect(clock.now - start < .seconds(1))
    }

    @Test func reselectingTheNoteAfterAFailedSwitchRestoresItsUpdatesWithoutReloading() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        let originalID = try #require(page.editor.noteID)
        let original = try #require(page.library.item(originalID))
        let generation = try await page.editor.webView.evaluateJavaScript("window.editor.snapshot().generation") as? Int
        let replacement = page.library.add("Replacement\n")
        let replacementItem = try #require(page.library.item(replacement.id))
        try await page.run("window.savedFlush = window.editor.flush; window.editor.flush = () => { throw new Error('composition') }")
        page.editor.select(replacementItem)
        try await page.wait { !page.library.notices.waiting.isEmpty }
        #expect(page.editor.noteID == originalID)

        page.editor.select(original)
        try await page.run("window.editor.flush = window.savedFlush")
        #expect(try await page.editor.webView.evaluateJavaScript("window.editor.snapshot().generation") as? Int == generation)
        #expect(try await page.editor.webView.evaluateJavaScript("window.editor.snapshot().text") as? String == "Original\n")
        page.editor.noteChanged(replacementItem)
        #expect(page.editor.noteID == originalID)

        page.library.updateBody(of: originalID, to: "Outside\n")
        page.editor.noteChanged(try #require(page.library.item(originalID)))
        #expect(try await page.shownText(until: "Outside") == "Outside")
        #expect(page.editor.noteID == originalID)
        #expect(page.changes.isEmpty)
    }

    @Test func aHiddenNoteRetainsFailedEditsWithoutOfferingCommands() async throws {
        let page = try await Page()
        try await page.load("Original\n")
        let id = page.editor.noteID
        try await page.run("window.savedFlush = window.editor.flush; window.editor.flush = () => { throw new Error('composition') }")
        page.editor.close()
        #expect(!page.editor.hasNote)
        try await page.wait { !page.library.notices.waiting.isEmpty }
        #expect(page.editor.noteID == id)
        #expect(!page.editor.hasNote)
        let retainedID = try #require(id)
        let item = try #require(page.library.item(retainedID))
        page.library.updateBody(of: item.id, to: "Outside\n")
        page.editor.noteChanged(item)
        #expect(!page.editor.hasNote)
        try await page.run("window.editor.flush = window.savedFlush")
        page.editor.load(item)
        #expect(page.editor.hasNote)
    }

    @Test func anAutomaticDiagramFallbackDoesNotPresentAnActionFailure() async throws {
        let page = try await Page()
        try await page.load("```mermaid\nnot a valid diagram [\n```\n")
        // Time for the diagram's failure to reach the app, which nothing signals when it does not.
        try await Task.sleep(for: .milliseconds(300))
        #expect(page.library.notices.waiting.last == nil)
        #expect(try await page.markdown() == nil)
    }

    @Test func nativeFindReplacementBatchUsesScopedReadableTextAndEmojiGeometry() async throws {
        let page = try await Page()
        let window = TestWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.webView
        defer { window.close() }
        try await page.load("one 😀 one\n")
        try await page.run("window.originalPost = window.webkit.messageHandlers.host.postMessage; window.webkit.messageHandlers.host.postMessage = message => { if (message.type === 'find') window.capturedFind = message; window.originalPost(message) }; window.editor.setFinding(true)")
        let body = try await page.editor.webView.evaluateJavaScript("window.capturedFind")
        let capturedBody = try #require(body)
        guard case .find(let state) = try #require(EditorMessage(body: capturedBody)) else { Issue.record("Missing Find snapshot"); return }
        let emoji = (state.text as NSString).range(of: "😀")
        let finder = PageFinder(controller: page.editor)
        finder.update(state)
        let rects = try #require(finder.rects(forCharacterRange: emoji))
        #expect(rects.contains { $0.rectValue.width > 0 && $0.rectValue.height > 0 })
        let first = NSRange(location: 0, length: 3)
        let last = (state.text as NSString).range(of: "one", options: .backwards)
        #expect(finder.shouldReplaceCharacters(inRanges: [NSValue(range: first), NSValue(range: last)], with: ["two", "two"]))
        finder.replaceCharacters(in: first, with: "two")
        finder.replaceCharacters(in: last, with: "two")
        _ = try await page.editor.webView.evaluateJavaScript("1")
        #expect(try await page.markdown() == "two 😀 two\n")
    }

    @Test func closeProxyRestoresTheHostDelegateAndNeverReusesARejectedApproval() async throws {
        final class HostDelegate: NSObject, NSWindowDelegate {
            var permitsClose = true
            func windowShouldClose(_ sender: NSWindow) -> Bool { permitsClose }
        }
        let page = try await Page()
        try await page.load("Draft\n")
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = HostDelegate()
        window.delegate = host
        let proxy = EditorCloseDelegate(editor: page.editor, window: window)
        let rejected = proxy.windowShouldClose(window)
        #expect(!rejected)
        host.permitsClose = false
        try await page.wait { !proxy.awaiting }
        try await page.run("0")
        host.permitsClose = true
        try await page.run("window.editor.flush = () => { throw new Error('composition') }")
        let laterRejected = proxy.windowShouldClose(window)
        #expect(!laterRejected)
        #expect(await eventually { !page.library.notices.waiting.isEmpty })
        proxy.detach()
        #expect(window.delegate === host)
        window.delegate = nil
        window.close()
    }

    @Test func aNoteOpenedAndLeftAloneIsNotRewritten() async throws {
        let page = try await Page()
        try await page.load(kitchen)
        #expect(try await page.markdown() == nil)
        // Longer than the pause after which the page reports an edit.
        try await Task.sleep(for: .milliseconds(400))
        #expect(page.changes.isEmpty)
    }

    @Test func aHeadingHasNativeFormatStateAndItsAuthoredSource() async throws {
        let page = try await Page()
        let window = TestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        try await page.load("A paragraph.\n\n## Closing\n")
        page.editor.focus()
        try await page.run("(() => { const snapshot = window.editor.readableSnapshot(); const at = snapshot.text.indexOf('Closing'); window.editor.findSelect(at, at, snapshot.generation, snapshot.snapshotId); window.editor.focus() })()")
        try await page.wait { page.editor.caret.block == .heading(2) }
        #expect(Format.heading.isActive(in: page.editor.caret))
        page.editor.setSourceMode(true)
        try await page.wait { page.editor.caret.sourceMode }
        let source = try await page.editor.webView.evaluateJavaScript("document.querySelector('textarea').value") as? String
        #expect(source == "A paragraph.\n\n## Closing\n")
        page.editor.setSourceMode(false)
        try await page.wait { !page.editor.caret.sourceMode }
        #expect(try await page.shownText(until: "A paragraph.Closing") == "A paragraph.Closing")
        #expect(try await page.markdown() == nil)
        #expect(page.changes.isEmpty)
    }

    @Test func formattingReportsTheNoteAsMarkdown() async throws {
        let page = try await Page()
        try await page.load("Milk\n")
        page.editor.format(.checklist)
        try await page.wait { !page.changes.isEmpty }
        #expect(page.changes.last == "- [ ] Milk\n")
    }

    @Test func aTableMadeInThePageIsWrittenWithoutAlignment() async throws {
        let page = try await Page()
        try await page.load("Quotes\n")
        page.editor.format(.table)
        try await page.wait { !page.changes.isEmpty }
        let markdown = try #require(page.changes.last)
        // The delimiter row is any run of dashes per column; Inkkit writes the shortest, `| - | - |`.
        #expect(markdown.split(separator: "\n").contains { $0.hasPrefix("|") && $0.contains("-") && $0.allSatisfy { "|- ".contains($0) } })
        #expect(!markdown.contains(":-"))
    }

    @Test func undoAndRedoGoThroughThePagesOwnHistory() async throws {
        let page = try await Page()
        try await page.load("Milk\n")
        page.editor.format(.checklist)
        try await page.wait { page.editor.caret.canUndo }
        page.editor.undo()
        try await page.wait { page.editor.caret.canRedo }
        #expect(try await page.markdown() == nil)
    }

    @Test func aDeletedNoteCannotBeEdited() async throws {
        let page = try await Page()
        try await page.load("Old list\n", deleted: true)
        #expect(!page.editor.isEditable)
        try await page.run("document.querySelector('.ProseMirror').focus(); document.execCommand('insertText', false, 'x')")
        page.editor.format(.checklist)
        page.editor.format(.table)
        #expect(try await page.markdown() == nil)
    }

    @Test func anEditNotYetReportedIsHandedOverOnFlush() async throws {
        let page = try await Page()
        try await page.load("Draft\n")
        page.editor.format(.title)
        page.editor.flush()
        try await page.wait { !page.changes.isEmpty }
        #expect(page.changes == ["# Draft\n"])
    }

    @Test func aNoteWhoseTextCannotBeReadIsNotOpenedForWriting() async throws {
        let page = try await Page()
        try await page.load("Kept\n")
        let item = FakeItemLibrary.note("Plan", modified: .now)
        // The editor's library has no text for this item, so the page must not open an empty note to type into.
        page.editor.load(item)
        _ = try await page.editor.webView.evaluateJavaScript("1")
        #expect(page.editor.noteID != item.id)
        page.editor.noteChanged(item)
        #expect(page.editor.noteID != item.id)
        // Nor does the page keep the note it showed before, which typing would then change out of sight.
        #expect(try await page.shownText(until: "") == "")
        try await page.run("document.querySelector('.ProseMirror').focus(); document.execCommand('insertText', false, 'X')")
        page.editor.flush()
        _ = try await page.editor.webView.evaluateJavaScript("1")
        // Gives a report from the page, had it taken the typing, time to arrive.
        try await Task.sleep(for: .milliseconds(500))
        #expect(page.changes.isEmpty)
    }

    /// The page reports a heading's availability by its level, so the Format menu offers Title, Heading, and
    /// Subheading in an editable note.
    @Test func headingCommandsAreAvailableInANote() async throws {
        let page = try await Page()
        try await page.load("Milk\n")
        try await page.wait { page.editor.canApply(.title) }
        #expect(page.editor.canApply(.heading))
        #expect(page.editor.canApply(.subheading))
    }

    /// An edit still waiting to be reported when another device's text is taken in was typed on the text before it,
    /// so it is sent as typed on that older version and the server keeps both. The page shows the other device's
    /// text rather than taking the edit back over it.
    @Test func anEditOverlappingAnotherDevicesTextIsSentAsTypedOnTheOlderVersion() async throws {
        typealias F = LibraryFixture
        let source = FakeItemSource()
        for (id, text) in F.texts { source.setBody(text, of: id) }
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(F.snapshot))
        try #require(await eventually { library.isLoaded })
        let editor = EditorController(library: library)
        editor.onChange = { id, markdown, read in library.updateBody(of: id, to: markdown, readAt: read) }
        try #require(await eventually { editor.isReady })
        let item = try #require(library.item(F.n1))
        editor.load(item)
        _ = try await editor.webView.evaluateJavaScript("1")
        editor.format(.checklist)
        var theirs = item
        theirs.version = ItemVersion(2)
        source.setBody("Theirs", of: F.n1, version: 2)
        source.send(.upserted([theirs]))
        try #require(await eventually { library.body(of: F.n1)?.text == "Theirs" })
        editor.noteChanged(try #require(library.item(F.n1)))
        let typed = await eventually {
            source.writes.contains { if case .editBody = $0 { true } else { false } }
        }
        try #require(typed)
        guard case .editBody(F.n1, let text, let base, let merge) = source.writes.last else {
            Issue.record("sent \(source.writes)")
            return
        }
        #expect(text.contains("[ ] Note body"))
        #expect(base == ItemVersion(1))
        #expect(merge == .asRead)
        #expect(library.body(of: F.n1)?.text == "Theirs")
        #expect(try await eventuallyAsking {
            try await editor.webView.evaluateJavaScript("document.querySelector('.ProseMirror').textContent") as? String == "Theirs"
        })
    }

    @Test func anImageInTheFilesShowsAndOneLinkedFromOutsideDoesNot() async throws {
        let root = try TemporaryFolder()
        let outside = try TemporaryFolder()
        let png = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )?.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: root.url.appending(path: "Attachments"), withIntermediateDirectories: true)
        try png.write(to: root.url.appending(path: "Attachments/Photo 1.png"))
        try png.write(to: outside.url.appending(path: "secret.png"))
        try FileManager.default.createSymbolicLink(
            at: root.url.appending(path: "Attachments/link.png"), withDestinationURL: outside.url.appending(path: "secret.png")
        )
        let page = try await Page()
        let library = page.library
        let note = library.add("![a](Attachments/Photo%201.png)\n\n![b](Attachments/link.png)\n")
        library.bindEmbed("![a](Attachments/Photo%201.png)", in: note.id, file: root.url.appending(path: "Attachments/Photo 1.png"))
        library.bindEmbed("![b](Attachments/link.png)", in: note.id, file: root.url.appending(path: "Attachments/link.png"))
        page.editor.load(note)
        let widths = try await settle(page.editor,
            "[...document.querySelectorAll('.inkkit-image img')].map((image) => image.naturalWidth)",
            as: [Int].self) { $0 == [4] }
        #expect(widths == [4])
        let expectedRefused = [["name": "b", "status": "This file can’t be opened."]]
        let refused = try await settle(page.editor,
            "[...document.querySelectorAll('.inkkit-file[data-inkkit-file-kind=error]')].map(card => ({ name: card.querySelector('.inkkit-file-label')?.textContent, status: card.querySelector('.inkkit-file-status')?.textContent }))",
            as: [[String: String]].self) { $0 == expectedRefused }
        #expect(refused == expectedRefused, "a file reached through a link is not opened")
        let rejected = try await page.editor.webView.callAsyncJavaScript("return await window.editor.printable()", arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        #expect(rejected?["snapshotError"] == nil)
        #expect(rejected?["assetCount"] as? Int == 1)
        #expect((rejected?["html"] as? String)?.contains("mapp-embed:") == false)
        library.updateBody(of: note.id, to: "![a](Attachments/Photo%201.png)\n")
        page.editor.noteChanged(try #require(library.item(note.id)))
        _ = try await page.editor.webView.evaluateJavaScript("1")
        let printable = try await page.editor.webView.callAsyncJavaScript("return await window.editor.printable()", arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        let html = try #require(printable?["html"] as? String)
        #expect(html.contains("data:image/png;base64,"))
        #expect(!html.contains("mapp-embed:"))
    }

    @Test func anEditRewritesOnlyTheBlockItTouched() async throws {
        let page = try await Page()
        let written = "Title\n=====\n\n* star bullet\n* another\n\n| a | b |\n|:--|--:|\n| 1 | 2 |\n\n\n\nMilk\n"
        try await page.load(written)
        page.editor.format(.checklist)
        try await page.wait { !page.changes.isEmpty }
        #expect(page.changes.last == written.replacingOccurrences(of: "Milk", with: "- [ ] Milk"))
    }

    @Test func aNoteExportsAsAPDFOfItsTextAndPageStyle() async throws {
        let page = try await Page()
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        defer { window.close() }
        page.editor.setStyle(PageStyle(textSize: 20, checksSpelling: false))
        try await page.load(kitchen)
        page.editor.setHeader(Self.header("Header only words"))
        let size = try await page.editor.webView.evaluateJavaScript("getComputedStyle(document.documentElement).fontSize") as? String
        #expect(size == "20px")
        let spellcheck = try await page.editor.webView.evaluateJavaScript("document.querySelector('.ProseMirror').getAttribute('spellcheck')") as? String
        #expect(spellcheck == "false")

        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "Kitchen quotes.pdf")
        page.editor.exportPDF(to: url)
        // The size is watched rather than the file read, and a PDF far larger than one short note's fails at once,
        // so pagination that runs away cannot fill the disk before the test gives up.
        var bytes = 0, runaway = 0
        _ = await eventually {
            let now = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            defer { bytes = now }
            if now > 5_000_000 {
                runaway = now
                return true
            }
            return now > 0 && now == bytes
        }
        try #require(runaway == 0, "the PDF has grown to \(runaway) bytes")
        try #require(bytes > 0, "no PDF was written")
        let document = try #require(PDFDocument(url: url))
        #expect((1...2).contains(document.pageCount), "a short note prints on a page or two")
        #expect(document.string?.contains("Kitchen quotes") == true)
        #expect(document.string?.contains("Book a site visit") == true)
        #expect(document.string?.contains("Header only words") == false, "the page's header is not part of the note")
    }
}

extension EditorTests.Harness where Library == FakeItemLibrary {
    convenience init() async throws {
        try await self.init(library: FakeItemLibrary())
    }

    /// A page whose web pictures are `pictures`, as a test with its own cache, fetcher and setting has.
    convenience init(pictures: WebPictures) async throws {
        try await self.init(library: FakeItemLibrary(), pictures: pictures)
    }

    /// Adds a note holding `body` and shows it.
    func load(_ body: String, deleted: Bool = false) async throws {
        try await show(library.add(body, state: deleted ? .trashed : .active).id)
    }
}
