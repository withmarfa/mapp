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
    final class Harness {
        /// The editor holds its library weakly, so the harness keeps the one it loads from.
        let library: NoteLibrary
        let editor: EditorController
        var changes: [String] = []

        init(library: NoteLibrary = NoteLibrary()) async throws {
            self.library = library
            editor = EditorController(library: library)
            editor.onChange = { [unowned self] _, markdown, _ in changes.append(markdown) }
            try await wait { self.editor.isReady }
        }

        func load(_ body: String, deleted: Bool = false) async throws {
            let note = Note(body: body, created: .now, deleted: deleted ? .now : nil)
            library.notes.append(note)
            editor.load(try #require(library.item(note.id)))
            try await wait { self.editor.noteID == note.id }
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

        /// Waits until the page has drawn two more frames, so what it does in the next frame has been done and
        /// anything it posted then has arrived.
        func frames() async throws {
            _ = try await editor.webView.callAsyncJavaScript(
                "await new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done)))",
                arguments: [:], in: nil, contentWorld: .page)
            _ = try await editor.webView.evaluateJavaScript("1")
        }

        /// The page's text, once it reads `expected` or after a couple of seconds.
        func shownText(until expected: String) async throws -> String {
            var shown = ""
            for _ in 0..<40 {
                shown = try await editor.webView.evaluateJavaScript("document.querySelector('.ProseMirror').textContent") as? String ?? ""
                if shown == expected { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            return shown
        }

        /// Waits for something the page does in its own time, such as reporting an edit after a pause.
        func wait(_ condition: () -> Bool) async throws {
            for _ in 0..<100 where !condition() {
                try await Task.sleep(for: .milliseconds(50))
            }
            try #require(condition())
        }
    }

    let kitchen = """
    # Kitchen quotes

    | Supplier | Quote |
    | --- | ---: |
    | Oak & Iron | £11,850 |

    - [x] Measure the alcove
    - [ ] Book a site visit

    """

    private final class ReadingPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    @Test func selectingAnotherItemReturnsTheBodyToReading() async throws {
        let page = try await Harness()
        let window = ReadingPanel(contentRect: NSRect(x: 100, y: 100, width: 500, height: 600),
                                  styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.webView
        let other = ReadingPanel(contentRect: NSRect(x: 650, y: 100, width: 250, height: 200),
                                 styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer {
            window.orderOut(nil); window.contentView = nil; window.close()
            other.orderOut(nil); other.close()
        }
        window.makeKeyAndOrderFront(nil)
        #expect(window.isKeyWindow)
        try await page.load("First item")
        try await page.run("window.editor.focus()")
        let editing = try await page.editor.webView.evaluateJavaScript(
            "document.activeElement?.matches('.ProseMirror, .inkkit-plain') === true"
        ) as? Bool
        #expect(editing == true)
        other.makeKeyAndOrderFront(nil)
        #expect(other.isKeyWindow)
        try await page.load("Second item")
        #expect(other.isKeyWindow)
        #expect(!window.isKeyWindow)
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
        let first = Note(body: "First", created: .now)
        let second = Note(body: "Second", created: .now)
        let library = NoteLibrary(notes: [first, second])
        let page = try await Harness(library: library)
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
        let first = Note(body: "First\n", created: .now)
        let second = Note(body: "Second\n", created: .now)
        let library = NoteLibrary(notes: [first, second])
        let editor = EditorController(library: library)
        editor.load(try #require(library.item(first.id)))
        #expect(!editor.isReady)
        editor.load(try #require(library.item(second.id)))
        #expect(editor.noteID == second.id)
        for _ in 0..<100 where !editor.isReady { try await Task.sleep(for: .milliseconds(50)) }
        try #require(editor.isReady)
        let source = try await editor.webView.evaluateJavaScript("window.editor.snapshot().text") as? String
        #expect(source == "Second\n")
    }

    @Test func aCapturedFlushReplyIsSavedUnderItsOriginalVersionAfterReload() async throws {
        let note = Note(body: "Original\n", created: .now)
        let library = NoteLibrary(notes: [note], store: RecordingStore())
        let page = try await Harness(library: library)
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
        #expect(!kept)
        #expect(captured == ["Pending\n"])
        #expect(library.note(note.id)?.body == "Outside\n")
        #expect(library.notes.contains { $0.id != note.id && $0.body == "Pending\n" })
    }

    @Test func aRejectedFlushCannotApproveLeavingOrSaveAnotherNotesText() async throws {
        let page = try await Harness()
        try await page.load("Original\n")
        var left = false
        page.editor.onLeave = { _ in left = true }
        try await page.run("window.savedFlush = window.editor.flush; window.editor.flush = () => { throw new Error('composition') }")
        let originalID = page.editor.noteID
        let replacement = Note(body: "Replacement\n", created: .now)
        page.library.notes.append(replacement)
        let kept = await withCheckedContinuation { continuation in
            page.editor.flush { continuation.resume(returning: $0) }
            page.editor.load(page.library.item(replacement.id)!)
        }
        #expect(page.editor.noteID == originalID)
        #expect(page.changes.isEmpty)
        #expect(!kept)
        #expect(!left)
        #expect(page.library.failure != nil)
        try await page.run("window.editor.flush = window.savedFlush")
        let oldGeneration = try await page.editor.webView.evaluateJavaScript("window.editor.snapshot().generation") as? Int
        try await page.load("Replacement\n")
        let rejected = try await page.editor.webView.callAsyncJavaScript("try { window.editor.flush(expected); return false } catch { return true }", arguments: ["expected": try #require(oldGeneration)], in: nil, contentWorld: .page) as? Bool
        #expect(rejected == true)
        #expect(try await page.markdown() == nil)
    }

    @Test func aHiddenNoteRetainsFailedEditsWithoutOfferingCommands() async throws {
        let page = try await Harness()
        try await page.load("Original\n")
        let id = page.editor.noteID
        try await page.run("window.savedFlush = window.editor.flush; window.editor.flush = () => { throw new Error('composition') }")
        page.editor.close()
        #expect(!page.editor.hasNote)
        try await page.wait { page.library.failure != nil }
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
        let page = try await Harness()
        try await page.load("```mermaid\nnot a valid diagram [\n```\n")
        try await Task.sleep(for: .milliseconds(300))
        #expect(page.library.failure == nil)
        #expect(try await page.markdown() == nil)
    }

    @Test func nativeFindReplacementBatchUsesScopedReadableTextAndEmojiGeometry() async throws {
        let page = try await Harness()
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

    @Test func nativeFindGeometryFollowsViewportAndAppearanceChanges() async throws {
        let page = try await Harness()
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await page.load(String(repeating: "Wrap these words around the native Find markings. ", count: 30) + "\n")
        try await page.run("window.editor.setFinding(true)")
        let client = try #require(page.editor.pageFinder)
        let range = NSRange(location: 50, length: 100)
        func rects() -> [NSRect] { client.rects(forCharacterRange: range)?.map(\.rectValue) ?? [] }
        try await page.wait { !rects().isEmpty }
        for source in [false, true] {
            page.editor.setSourceMode(source)
            try await page.frames()
            for width in [CGFloat(360), 900, 500] {
                let before = rects()
                window.setContentSize(NSSize(width: width, height: 600))
                #expect(page.editor.webView.frame.width == width)
                try await page.wait { rects() != before }
                try await page.frames()
                #expect(rects().contains { $0.width > 0 && $0.height > 0 })
                #expect(try await page.editor.webView.evaluateJavaScript("window.innerWidth") as? Double == Double(width))
            }
            // A header that wraps differently moves the text below it.
            let header = Self.header(source ? "A short title" : String(repeating: "A title long enough to wrap ", count: 2))
            for command in ["setTextSize(\(source ? 20 : 18))", "setHeader(\(Self.json(header)))"] {
                let before = rects()
                try await page.run("window.editor.\(command)")
                try await page.wait { rects() != before }
                try await page.frames()
            }
            if !source {
                let before = rects()
                window.setContentSize(NSSize(width: 1400, height: 600))
                try await page.wait { rects() != before }
                try await page.frames()
                for command in ["setFullWidth(true)", "setFullWidth(false)", "setReadingWidth(24)"] {
                    let before = rects()
                    try await page.run("window.editor.\(command)")
                    try await page.wait { rects() != before }
                    try await page.frames()
                }
            }
        }
        try await page.run("window.editor.setFinding(false)")
        let stopped = rects()
        try await page.run("window.editor.setHeader(\(Self.json(Self.header(String(repeating: "Another title ", count: 12)))))")
        try await page.frames()
        #expect(rects() == stopped)
        #expect(try await page.markdown() == nil)
    }

    @Test func closeProxyRestoresTheHostDelegateAndNeverReusesARejectedApproval() async throws {
        final class HostDelegate: NSObject, NSWindowDelegate {
            var permitsClose = true
            func windowShouldClose(_ sender: NSWindow) -> Bool { permitsClose }
        }
        let page = try await Harness()
        try await page.load("Draft\n")
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = HostDelegate()
        window.delegate = host
        let proxy = EditorCloseDelegate(editor: page.editor, window: window)
        var left = false
        page.editor.onLeave = { _ in left = true }
        let rejected = proxy.windowShouldClose(window)
        #expect(!rejected)
        host.permitsClose = false
        try await page.wait { left }
        try await page.run("0")
        host.permitsClose = true
        try await page.run("window.editor.flush = () => { throw new Error('composition') }")
        let laterRejected = proxy.windowShouldClose(window)
        #expect(!laterRejected)
        try await Task.sleep(for: .milliseconds(2200))
        #expect(page.library.failure != nil)
        proxy.detach()
        #expect(window.delegate === host)
        window.delegate = nil
        window.close()
    }

    @Test func aNoteOpenedAndLeftAloneIsNotRewritten() async throws {
        let page = try await Harness()
        try await page.load(kitchen)
        #expect(try await page.markdown() == nil)
        // Longer than the pause after which the page reports an edit.
        try await Task.sleep(for: .milliseconds(400))
        #expect(page.changes.isEmpty)
    }

    @Test func aHeadingHasNativeFormatStateAndItsAuthoredSource() async throws {
        let page = try await Harness()
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
        let page = try await Harness()
        try await page.load("Milk\n")
        page.editor.format(.checklist)
        try await page.wait { !page.changes.isEmpty }
        #expect(page.changes.last == "- [ ] Milk\n")
    }

    @Test func aTableMadeInThePageIsWrittenWithoutAlignment() async throws {
        let page = try await Harness()
        try await page.load("Quotes\n")
        page.editor.format(.table)
        try await page.wait { !page.changes.isEmpty }
        let markdown = try #require(page.changes.last)
        // The delimiter row is any run of dashes per column; InkKit writes the shortest, `| - | - |`.
        #expect(markdown.split(separator: "\n").contains { $0.hasPrefix("|") && $0.contains("-") && $0.allSatisfy { "|- ".contains($0) } })
        #expect(!markdown.contains(":-"))
    }

    @Test func undoAndRedoGoThroughThePagesOwnHistory() async throws {
        let page = try await Harness()
        try await page.load("Milk\n")
        page.editor.format(.checklist)
        try await page.wait { page.editor.caret.canUndo }
        page.editor.undo()
        try await page.wait { page.editor.caret.canRedo }
        #expect(try await page.markdown() == nil)
    }

    @Test func aDeletedNoteCannotBeEdited() async throws {
        let page = try await Harness()
        try await page.load("Old list\n", deleted: true)
        #expect(!page.editor.isEditable)
        try await page.run("document.querySelector('.ProseMirror').focus(); document.execCommand('insertText', false, 'x')")
        page.editor.format(.checklist)
        page.editor.format(.table)
        #expect(try await page.markdown() == nil)
    }

    @Test func anEditNotYetReportedIsHandedOverOnFlush() async throws {
        let page = try await Harness()
        try await page.load("Draft\n")
        page.editor.format(.title)
        page.editor.flush()
        try await page.wait { !page.changes.isEmpty }
        #expect(page.changes == ["# Draft\n"])
    }

    @Test func aNoteWhoseTextCannotBeReadIsNotOpenedForWriting() async throws {
        let page = try await Harness()
        try await page.load("Kept\n")
        let note = Note(body: "Plan\n", created: .now)
        let item = try #require(NoteLibrary(notes: [note]).item(note.id))
        // The editor's library has no text for this item, so the page must not open an empty note to type into.
        page.editor.load(item)
        _ = try await page.editor.webView.evaluateJavaScript("1")
        #expect(page.editor.noteID != item.id)
        page.editor.noteChanged(item)
        #expect(page.editor.noteID != item.id)
    }

    @Test func aFirstLineTypedWithASpaceAtItsEndNamesTheFileWithoutIt() async throws {
        let store = RecordingStore()
        let note = Note(body: "Plan\n", created: .now)
        let library = NoteLibrary(notes: [note], store: store)
        let page = try await Harness(library: library)
        page.editor.onChange = { id, markdown, read in library.updateBody(of: id, to: markdown, readAt: read) }
        page.editor.onLeave = { library.leave($0) }
        page.editor.load(try #require(library.item(note.id)))
        _ = try await page.editor.webView.evaluateJavaScript("1")
        try await page.run("document.querySelector('.ProseMirror').focus(); document.execCommand('selectAll'); document.execCommand('insertText', false, 'R&D plan ')")
        // Leaving the note renames its file after its first line.
        page.editor.flush()
        try await page.wait { library.note(note.id)?.path != "Plan.md" }
        #expect(library.note(note.id)?.path == "R&D plan.md")
        #expect(library.note(note.id)?.title == "R&D plan")
    }

    /// The page reports a heading's availability by its level, so the Format menu offers Title, Heading, and
    /// Subheading in an editable note.
    @Test func headingCommandsAreAvailableInANote() async throws {
        let note = Note(body: "Milk\n", created: .now)
        let library = NoteLibrary(notes: [note], store: RecordingStore())
        let page = try await Harness(library: library)
        page.editor.load(try #require(library.item(note.id)))
        try await page.wait { page.editor.canApply(.title) }
        #expect(page.editor.canApply(.heading))
        #expect(page.editor.canApply(.subheading))
    }

    /// An edit still waiting to be reported when another change to the note is taken in was typed on the text
    /// before that change. Laid over the note it would replace text the person never saw, so it is kept beside the
    /// note as a copy, and the note and the page keep the other change.
    @Test func anEditOverlappingAnOutsideChangeIsKeptAsACopy() async throws {
        let note = Note(body: "Milk\n", created: .now)
        let library = NoteLibrary(notes: [note], store: RecordingStore())
        let page = try await Harness(library: library)
        var reported: [String] = []
        page.editor.onChange = { id, markdown, read in reported.append(markdown); library.updateBody(of: id, to: markdown, readAt: read) }
        page.editor.load(try #require(library.item(note.id)))
        _ = try await page.editor.webView.evaluateJavaScript("1")
        try await page.wait { page.editor.canApply(.checklist) }
        page.editor.format(.checklist)
        // Another window's text, typed on the text it held.
        library.updateBody(of: note.id, to: "Outside\n")
        page.editor.noteChanged(try #require(library.item(note.id)))
        for _ in 0..<100 where library.notes.count == 1 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(reported == ["- [ ] Milk\n"])
        try #require(library.notes.count == 2)
        #expect(library.note(note.id)?.body == "Outside\n")
        let copy = try #require(library.notes.first { $0.id != note.id })
        #expect(copy.body == "- [ ] Milk\n")
        #expect(copy.path == "Milk (Conflicted Copy).md")
        #expect(library.failure?.title == String(localized: "Saved as a Copy"))
        #expect(try await page.shownText(until: "Outside") == "Outside")
    }

    /// The same in a Marfa library: the edit is sent as typed on the version before the other device's text, so the
    /// server keeps both, and the page shows the other device's text rather than taking the edit back over it.
    @Test func anEditOverlappingAnotherDevicesTextIsSentAsTypedOnTheOlderVersion() async throws {
        typealias F = LibraryFixture
        let source = FakeItemSource()
        for (id, text) in F.texts { source.setBody(text, of: id) }
        let library = MarfaLibrary(source: source)
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
        var shown = ""
        for _ in 0..<20 {
            shown = try await editor.webView.evaluateJavaScript("document.querySelector('.ProseMirror').textContent") as? String ?? ""
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(shown == "Theirs")
    }

    @Test func anImageInTheNotesFolderShowsAndOneLinkedFromOutsideDoesNot() async throws {
        let root = try TemporaryFolder()
        let bin = try TemporaryFolder()
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
        let note = Note(body: "![a](Attachments/Photo%201.png)\n\n![b](Attachments/link.png)\n", created: .now)
        let library = NoteLibrary(notes: [note], store: FolderStore(root: root.url, bin: bin.url))
        let page = try await Harness(library: library)
        page.editor.load(try #require(library.item(note.id)))
        var widths: [Int] = []
        for _ in 0..<40 {
            widths = try await page.editor.webView.evaluateJavaScript(
                "[...document.querySelectorAll('.inkkit-image img')].map((image) => image.naturalWidth)"
            ) as? [Int] ?? []
            if widths == [4] { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(widths == [4])
        let expectedMissing = [["name": "b", "status": "File Not Found"]]
        let absent = try await settle(page.editor,
            "[...document.querySelectorAll('.inkkit-file[data-inkkit-file-kind=missing]')].map(card => ({ name: card.querySelector('.inkkit-file-label')?.textContent, status: card.querySelector('.inkkit-file-status')?.textContent }))",
            as: [[String: String]].self) { $0 == expectedMissing }
        #expect(absent == expectedMissing)
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

    // MARK: Embedded files of any kind

    /// Evaluates a script until it answers what `done` accepts, as a page loading files takes its own time.
    func settle<T>(_ editor: EditorController, _ script: String, as: T.Type = T.self, until done: (T?) -> Bool) async throws -> T? {
        var value: T?
        for _ in 0..<100 {
            value = try await editor.webView.evaluateJavaScript(script) as? T
            if done(value) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        return value
    }

    @Test func eachKindOfEmbeddedFileShowsAsWhatItIs() async throws {
        let root = try TemporaryFolder()
        let bin = try TemporaryFolder()
        let attachments = root.url.appending(path: "Attachments")
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        try EmbedFixtures.png(width: 5, height: 2).write(to: attachments.appending(path: "Photo.png"))
        try EmbedFixtures.wav().write(to: attachments.appending(path: "Tone.wav"))
        try EmbedFixtures.movie(to: attachments.appending(path: "Clip.mov"))
        try EmbedFixtures.pdf(to: attachments.appending(path: "Plan.pdf"))
        try Data("Item,Cost\nOak,11850\n".utf8).write(to: attachments.appending(path: "Budget.csv"))
        let body = """
        ![[Photo.png|3]] ![](../Attachments/Tone.wav)

        ![[Clip.mov]]

        ![[Plan.pdf]]

        ![[Budget.csv]] ![[Missing.zip]] ![far](../../outside.png) ![[A note]]

        """
        let note = Note(path: "Projects/Embeds.md", text: body, created: .now)
        let library = NoteLibrary(notes: [note], store: FolderStore(root: root.url, bin: bin.url))
        let page = try await Harness(library: library)
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 1400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        defer {
            window.contentView = nil
            window.close()
        }
        page.editor.load(try #require(library.item(note.id)))
        let editor = page.editor

        let image = try await settle(editor, "(() => { const i = document.querySelector('.inkkit-image img'); return i ? [i.naturalWidth, Math.round(i.getBoundingClientRect().width)] : [] })()", as: [Int].self) { $0 == [5, 3] }
        #expect(image == [5, 3], "the image loads through the scheme at the width its embed gives")

        let audio = try await settle(editor, "(() => { const a = document.querySelector('.inkkit-file audio'); return a && a.readyState >= 1 ? a.duration : -1 })()", as: Double.self) { ($0 ?? -1) > 0 }
        #expect(abs((audio ?? 0) - 0.5) < 0.05, "the sound's length is read through ranges of the file")

        let video = try await settle(editor, "(() => { const v = document.querySelector('.inkkit-file video'); return v && v.readyState >= 1 ? [v.videoWidth, v.videoHeight] : [] })()", as: [Int].self) { $0 == [64, 64] }
        #expect(video == [64, 64])

        let labels = try await settle(editor, "[...document.querySelectorAll('.inkkit-file-label')].map(e => e.textContent)", as: [String].self) { $0?.contains("Budget.csv") == true }
        #expect(labels?.contains("Budget.csv") == true)
        #expect(labels?.contains("Note reference: A note. Open to edit source.") == true)
        let expectedMissing = [
            ["name": "Missing.zip", "status": "File Not Found"],
            ["name": "far", "status": "File Not Found"],
        ]
        let missing = try await settle(editor,
            "[...document.querySelectorAll('.inkkit-file[data-inkkit-file-kind=missing]')].map(card => ({ name: card.querySelector('.inkkit-file-label')?.textContent, status: card.querySelector('.inkkit-file-status')?.textContent }))",
            as: [[String: String]].self) { $0 == expectedMissing }
        #expect(missing == expectedMissing)

        #expect(labels?.contains("Plan.pdf: Open to view this PDF") == true)
        #expect(await library.embeddedFile(.name("Plan.pdf"), in: note.id)?.lastPathComponent == "Plan.pdf")
        #expect(try await editor.webView.evaluateJavaScript("!!document.querySelector('.inkkit-file iframe')") as? Bool == false)

        #expect(try await page.markdown() == nil, "showing the files changes nothing in the note")
    }

    @Test func aVideoLargerThanOneAnswerPlaysToItsEnd() async throws {
        let root = try TemporaryFolder()
        let bin = try TemporaryFolder()
        let movie = root.url.appending(path: "Long.mov")
        try EmbedFixtures.longMovie(to: movie, padding: Int(2 * EmbeddedFiles.window))
        let size = try #require(try movie.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        try #require(UInt64(size) > 2 * EmbeddedFiles.window, "the movie is \(size) bytes")
        let note = Note(path: "Embeds.md", text: "![[Long.mov]]\n", created: .now)
        let library = NoteLibrary(notes: [note], store: FolderStore(root: root.url, bin: bin.url))
        let page = try await Harness(library: library)
        // WebKit loads no media for a page outside a window.
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        defer {
            window.contentView = nil
            window.close()
        }
        page.editor.load(try #require(library.item(note.id)))
        let duration = try await settle(page.editor, "(() => { const v = document.querySelector('video'); return v && v.readyState >= 1 ? v.duration : -1 })()", as: Double.self) { ($0 ?? -1) > 0 }
        try #require((duration ?? 0) > 3)
        try await page.run("const v = document.querySelector('video'); v.currentTime = v.duration - 0.1")
        let shown = try await settle(page.editor, "(() => { const v = document.querySelector('video'); return !v.seeking && v.readyState >= 2 && v.currentTime > v.duration - 0.5 })()", as: Bool.self) { $0 == true }
        #expect(shown == true, "the frames past the first answer load")
    }

    @Test func theContextMenuOverAnEmbeddedFileKnowsWhichFile() async throws {
        let root = try TemporaryFolder()
        let bin = try TemporaryFolder()
        try FileManager.default.createDirectory(at: root.url.appending(path: "Attachments"), withIntermediateDirectories: true)
        try Data("a,b\n".utf8).write(to: root.url.appending(path: "Attachments/Budget.csv"))
        let note = Note(path: "Embeds.md", text: "A sheet: ![[Budget.csv]]\n", created: .now)
        let library = NoteLibrary(notes: [note], store: FolderStore(root: root.url, bin: bin.url))
        let page = try await Harness(library: library)
        page.editor.load(try #require(library.item(note.id)))
        _ = try await settle(page.editor, "!!document.querySelector('.inkkit-file')", as: Bool.self) { $0 == true }
        try await page.run("document.querySelector('.inkkit-file').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true }))")
        try await page.wait { page.editor.menuEmbed != nil }
        #expect(page.editor.menuEmbed?.item == note.id)
        #expect(page.editor.menuEmbed?.reference == .name("Budget.csv"))
        #expect(await library.embeddedFile(.name("Budget.csv"), in: note.id)?.lastPathComponent == "Budget.csv")
        _ = page.editor.takeMenuEmbed()
        try await page.run("document.querySelector('p').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true }))")
        _ = try await page.editor.webView.evaluateJavaScript("1")
        #expect(page.editor.menuEmbed == nil, "a menu elsewhere offers no file")
    }

    // MARK: Attaching images through any library

    /// An editor over a library held in memory, showing `notes[0]` once its page has loaded.
    func attachingEditor(_ library: FakeItemLibrary) async throws -> EditorController {
        let editor = EditorController(library: library)
        for _ in 0..<100 where !editor.isReady { try await Task.sleep(for: .milliseconds(50)) }
        try #require(editor.isReady)
        editor.load(library.items[0])
        _ = try await editor.webView.evaluateJavaScript("1")
        return editor
    }

    static let pasted = [PastedImages.Source.data(name: "Photo.png", Data("png".utf8))]

    /// What the page would save once the images have had time to land, or nil while it is as loaded.
    func settledMarkdown(_ editor: EditorController) async throws -> String? {
        try await Task.sleep(for: .milliseconds(300))
        return try await editor.webView.evaluateJavaScript("window.editor.markdown()") as? String
    }

    @Test func attachedImagesAreInsertedIntoTheNote() async throws {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Plan", modified: .now)])
        library.attaching = { [Embed(link: "Attachments/Photo.png", name: "Photo")] }
        let editor = try await attachingEditor(library)
        #expect(editor.insertImages(Self.pasted))
        #expect(try await settledMarkdown(editor)?.contains("![Photo](Attachments/Photo.png)") == true)
        #expect(library.failure == nil)
    }

    @Test func imagesTheLibraryCannotKeepAreReportedInThePersonsWords() async throws {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Plan", modified: .now)])
        library.attaching = { throw SourceFailure(kind: .failed, message: "The server is out of space.") }
        let editor = try await attachingEditor(library)
        #expect(editor.insertImages(Self.pasted))
        #expect(try await settledMarkdown(editor) == nil, "nothing is inserted")
        #expect(library.failure?.title == "Can’t Attach Images")
        #expect(library.failure?.message == "The images weren’t added to the note. The server is out of space.")
    }

    @Test func imagesAttachedAfterTheNoteChangesAreNotInsertedIntoTheNextOne() async throws {
        let first = FakeItemLibrary.note("Plan", modified: .now)
        let second = FakeItemLibrary.note("Other", modified: .now)
        let library = FakeItemLibrary(items: [first, second])
        let (gate, open) = AsyncStream<Void>.makeStream()
        var started = false
        library.attaching = {
            started = true
            for await _ in gate { break }
            return [Embed(link: "Attachments/Photo.png", name: "Photo")]
        }
        let editor = try await attachingEditor(library)
        #expect(editor.insertImages(Self.pasted))
        for _ in 0..<100 where !started { try await Task.sleep(for: .milliseconds(10)) }
        try #require(started)
        editor.load(second)
        _ = try await editor.webView.evaluateJavaScript("1")
        open.yield()
        open.finish()
        #expect(try await settledMarkdown(editor) == nil, "the note now on the page takes nothing")
        #expect(editor.noteID == second.id)
        #expect(library.failure == nil)
    }

    @Test func anEditRewritesOnlyTheBlockItTouched() async throws {
        let page = try await Harness()
        let written = "Title\n=====\n\n* star bullet\n* another\n\n| a | b |\n|:--|--:|\n| 1 | 2 |\n\n\n\nMilk\n"
        try await page.load(written)
        page.editor.format(.checklist)
        try await page.wait { !page.changes.isEmpty }
        #expect(page.changes.last == written.replacingOccurrences(of: "Milk", with: "- [ ] Milk"))
    }

    @Test func aNoteExportsAsAPDFOfItsTextAndPageStyle() async throws {
        let page = try await Harness()
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
        var bytes = 0
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            let now = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            try #require(now <= 5_000_000, "the PDF has grown to \(now) bytes")
            if now > 0, now == bytes { break }
            bytes = now
        }
        try #require(bytes > 0, "no PDF was written")
        let document = try #require(PDFDocument(url: url))
        #expect((1...2).contains(document.pageCount), "a short note prints on a page or two")
        #expect(document.string?.contains("Kitchen quotes") == true)
        #expect(document.string?.contains("Book a site visit") == true)
        #expect(document.string?.contains("Header only words") == false, "the page's header is not part of the note")
    }

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
    static func rect(_ selector: String, in page: Harness) async throws -> [Double] {
        try #require(try await page.editor.webView.evaluateJavaScript(
            "(() => { const r = document.querySelector(\(json(selector))).getBoundingClientRect(); return [r.left, r.top, r.width, r.height] })()"
        ) as? [Double])
    }

    @Test func theItemHeaderScrollsWithTheTextInsideThePageAndKeepsItsMargins() async throws {
        let page = try await Harness()
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

        // The title and the text start at the same margin whatever the width, the reading width or Full Width.
        for (width, full) in [(CGFloat(360), false), (900, false), (1400, false), (1400, true)] {
            window.setContentSize(NSSize(width: width, height: 500))
            page.editor.setStyle(PageStyle(fullWidth: full))
            try await page.frames()
            let title = try await Self.rect("#ItemPageTitle", in: page)
            let text = try await Self.rect(".ProseMirror p", in: page)
            #expect(abs(title[0] - text[0]) < 0.5, "at \(width) points the title starts at \(title[0]) and the text at \(text[0])")
            #expect(abs(title[2] - text[2]) < 0.5)
            #expect(text[1] >= title[1] + title[3] + 20, "the text starts below the header")
        }
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
        // Resizing the header and the window raises nothing in the page.
        #expect(page.library.failure == nil)
    }

    @Test func changingItemsAfterScrollingStartsAtTheTopAndStaysThere() async throws {
        let page = try await Harness()
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
        try await page.frames()
        try await page.run("window.scrollTo(0, 240)")
        try await page.frames()
        let scrolled = try await page.editor.webView.evaluateJavaScript("window.scrollY") as? Double
        #expect(scrolled == 240)

        for index in 0..<3 {
            page.editor.setHeader(Self.header(String(repeating: "A longer title ", count: index + 1)))
            try await page.load("Item \(index)\n\n" + paragraphs)
            try await page.frames()
            #expect(try await page.editor.webView.evaluateJavaScript("window.scrollY") as? Double == 0)
            #expect(!page.editor.isHeaderScrolledAway)
            window.setContentSize(NSSize(width: index.isMultiple(of: 2) ? 600 : 700, height: 500))
            container.layoutSubtreeIfNeeded()
            try await page.frames()
            #expect(try await page.editor.webView.evaluateJavaScript("window.scrollY") as? Double == 0)
            try await page.run("window.scrollTo(0, 240)")
            try await page.frames()
        }
        #expect(page.changes.isEmpty)
        #expect(page.library.failure == nil)
    }

    @Test func anUpdateForTheItemJustLeftCannotReloadIt() async throws {
        let first = Note(body: "First item\n", created: .now)
        let second = Note(body: "Second item\n", created: .now)
        let library = NoteLibrary(notes: [first, second])
        let page = try await Harness(library: library)
        page.editor.load(try #require(library.item(first.id)))
        _ = try await page.editor.webView.evaluateJavaScript("1")
        page.editor.load(try #require(library.item(second.id)))
        try await page.wait { page.editor.noteID == second.id }
        _ = try await page.editor.webView.evaluateJavaScript("1")
        page.editor.noteChanged(try #require(library.item(first.id)))
        _ = try await page.editor.webView.evaluateJavaScript("1")
        _ = try await page.editor.webView.evaluateJavaScript("1")
        #expect(page.editor.noteID == second.id)
        #expect(try await page.editor.webView.evaluateJavaScript("window.editor.snapshot().text") as? String == second.body)
        #expect(page.changes.isEmpty)
    }

    @Test(arguments: [false, true])
    func aSelectedItemLoadsWhenItsMissingBodyArrives(versionChanged: Bool) async throws {
        typealias F = LibraryFixture
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source)
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
        let library = MarfaLibrary(source: source)
        source.send(.loaded(F.snapshot))
        try #require(await eventually { library.isLoaded })
        let editor = EditorController(library: library)
        try #require(await eventually { editor.isReady })
        let item = try #require(library.item(F.n1))
        editor.load(item)
        if close {
            editor.close()
        } else {
            let other = try #require(library.items.first { $0.id != item.id && !$0.isFile })
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
        let page = try await Harness()
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
            for _ in 0..<60 where try await title() == "Title" { try await Task.sleep(for: .milliseconds(50)) }
            let markup = try await page.editor.webView.evaluateJavaScript("document.getElementById('ItemPageTitle').innerHTML") as? String
            #expect(markup == expected, "pasting \(pasted.unicodeScalars.map { String($0.value, radix: 16) }) left \(markup ?? "")")
            page.editor.webView.undo(nil)
            for _ in 0..<60 where try await title() != "Title" { try await Task.sleep(for: .milliseconds(50)) }
            #expect(try await title() == "Title", "one Undo takes out what was pasted")
        }
    }

    /// The paste itself is InkKit's; this holds that it works through the pasteboard, the web view and the bridge.
    @Test func htmlCopiedFromAWebPageIsPastedIntoTheNoteAsReadableText() async throws {
        let page = try await Harness()
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
        let page = try await Harness()
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
        let library: NoteLibrary
        let ticket = ItemPreviewFixtures.ticketID
        let page: Harness
        let drafts = DetailsPresentation()
        let shown: Shown
        let window: NSWindow

        init(library: NoteLibrary = ItemPreviewFixtures.library, showing id: ItemID = ItemPreviewFixtures.ticketID) async throws {
            self.library = library
            page = try await Harness(library: library)
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

        /// Waits for something the page or the window does in its own time, for up to ten seconds.
        func waitFor(_ what: String, _ condition: () async throws -> Bool) async throws {
            for _ in 0..<200 where try await !condition() { try await Task.sleep(for: .milliseconds(50)) }
            try #require(try await condition(), "waiting for \(what)")
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

        // A title the library refuses stays as typed, with the reason, and survives moving to another note and back.
        try await host.type("Review/photographs")
        try await host.pressReturn()
        try await host.waitFor("the page to show the refusal") { try await host.titleError() == true }
        #expect(library.item(ticket)?.title == "Review the findings")
        #expect(try await host.shownTitle() == "Review/photographs")
        host.shown.id = ItemPreviewFixtures.noteID
        try await host.waitForTitle("Field notes")
        #expect(try await host.titleError() == false)
        host.shown.id = ticket
        try await host.waitForTitle("Review/photographs")
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
        host.library.delete([host.ticket])
        try await host.page.wait { !host.page.editor.isEditable }
        try await host.waitFor("the header to hide") { try await host.value("document.getElementById('item-header').hidden") as? Bool == true }
        host.library.recover([host.ticket])
        try await host.page.wait { host.page.editor.isEditable }
        try await host.waitFor("the header to show") { try await host.value("document.getElementById('item-header').hidden") as? Bool == false }
    }

    static func editorWebView(in view: NSView?) -> EditorWebView? {
        guard let view else { return nil }
        if let web = view as? EditorWebView { return web }
        for sub in view.subviews { if let web = editorWebView(in: sub) { return web } }
        return nil
    }

    /// What a window held, by weak references, so a test can see what outlives it.
    struct Released {
        weak var editor: EditorController?
        weak var webView: EditorWebView?
        weak var library: NoteLibrary?
        var isEmpty: Bool { editor == nil && webView == nil && library == nil }
    }

    /// Opens the item in a window of its own, as the app's item window shows it, sets its title as `edit` says,
    /// and closes the window the way ⌘W does.
    static func openAndClose(_ library: NoteLibrary, item: ItemID, edit: (EditorController, EditorWebView) async throws -> Void = { _, _ in }) async throws -> Released {
        // The app's run loop empties its autorelease pool after every event; a test's await does not, so the
        // window's own steps are made in pools of their own.
        let window = autoreleasepool {
            let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: NoteWindow(id: .constant(item)).environment(\.library, library))
            window.makeKeyAndOrderFront(nil)
            return window
        }
        for _ in 0..<200 where editorWebView(in: window.contentView)?.controller?.isReady != true {
            try await Task.sleep(for: .milliseconds(50))
        }
        let web = try #require(editorWebView(in: window.contentView))
        let editor = try #require(web.controller)
        for _ in 0..<200 where try await web.evaluateJavaScript("document.getElementById('ItemPageTitle')?.textContent") as? String != library.item(item)?.title {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await edit(editor, web)
        autoreleasepool { window.performClose(nil) }
        for _ in 0..<200 where window.isVisible { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!window.isVisible, "the window closes")
        // What SwiftUI does with a window it closes.
        autoreleasepool {
            window.toolbar = nil
            window.contentView = nil
        }
        return Released(editor: editor, webView: web, library: library)
    }

    /// An item's page in a window of its own, with an editor and drafts of its own, through to its window closing.
    static func openAndCloseAPage(_ library: NoteLibrary, item: ItemID) async throws -> Released {
        let editor = EditorController(library: library)
        let drafts = DetailsPresentation()
        editor.titleDrafts = drafts
        let window = autoreleasepool {
            let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PageHost(library: library, editor: editor, drafts: drafts, shown: Shown(item))
                .environment(\.library, library))
            window.makeKeyAndOrderFront(nil)
            return window
        }
        for _ in 0..<200 where try await editor.webView.evaluateJavaScript("document.getElementById('ItemPageTitle')?.textContent") as? String != library.item(item)?.title {
            try await Task.sleep(for: .milliseconds(50))
        }
        // Typing in the title goes through the window's handler, as a person's does.
        editor.onHeaderEvent(.titleInput(item, "Review the findings"))
        drafts.draft(for: item, key: "title").isDirty = false
        autoreleasepool { window.performClose(nil) }
        for _ in 0..<200 where window.isVisible { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!window.isVisible, "the window closes")
        autoreleasepool { window.contentView = nil }
        return Released(editor: editor, webView: editor.webView, library: library)
    }

    @Test func aClosedWindowLetsGoOfItsEditorPageAndLibrary() async throws {
        let released = try await Self.openAndCloseAPage(ItemPreviewFixtures.library, item: ItemPreviewFixtures.ticketID)
        for _ in 0..<200 where !released.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        #expect(released.editor == nil, "a closed window's editor is released")
        #expect(released.webView == nil, "a closed window's web view is released")
        #expect(released.library == nil, "a library no window shows is released")
    }

    @Observable final class Ticks {
        var count = 0
    }

    /// Makes its content again whenever `ticks` changes, as a window's parent does each time its body runs.
    struct Remaking<Content: View>: View {
        let ticks: Ticks
        @ViewBuilder let content: () -> Content

        var body: some View {
            let _ = ticks.count
            content()
        }
    }

    /// Hosts `content` in a window, has its parent make it again `times` times, and returns every editor made
    /// meanwhile, held so none can go unseen, the one the window shows, and the drafts it held while shown.
    static func editorsMade<Content: View>(remaking times: Int, _ content: @escaping () -> Content) async throws -> (made: [EditorController], shown: EditorController, drafts: DetailsPresentation?) {
        let before = EditorController.open.allObjects
        var made: [EditorController] = []
        func gather() {
            for editor in EditorController.open.allObjects where !before.contains(where: { $0 === editor }) && !made.contains(where: { $0 === editor }) {
                made.append(editor)
            }
        }
        let ticks = Ticks()
        let window = autoreleasepool {
            let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 1100, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: Remaking(ticks: ticks, content: content))
            window.makeKeyAndOrderFront(nil)
            return window
        }
        for _ in 0..<200 where editorWebView(in: window.contentView)?.controller?.isReady != true {
            try await Task.sleep(for: .milliseconds(50))
        }
        gather()
        for _ in 0..<times {
            ticks.count += 1
            try await Task.sleep(for: .milliseconds(100))
            gather()
        }
        let shown = try #require(editorWebView(in: window.contentView)?.controller)
        let drafts = shown.titleDrafts
        autoreleasepool { window.performClose(nil) }
        for _ in 0..<200 where window.isVisible { try await Task.sleep(for: .milliseconds(50)) }
        autoreleasepool {
            window.toolbar = nil
            window.contentView = nil
        }
        return (made, shown, drafts)
    }

    /// An editor is a web view with a page process of its own, so a window makes one, however often SwiftUI makes
    /// the window's view again.
    @Test func aMainWindowMakesOneEditorHoweverOftenItsViewIsMadeAgain() async throws {
        let library = ItemPreviewFixtures.library
        let browser = ItemPreviewFixtures.browser
        let details = DetailsPresentation()
        let libraries = ItemPreviewFixtures.libraries(named: "MAPP.EditorTests")
        let (made, shown, drafts) = try await Self.editorsMade(remaking: 5) {
            MainView(browser: browser, details: details, restoresWindow: false)
                .environment(\.library, library)
                .environment(libraries)
        }
        #expect(made.count == 1, "one editor for the window, not one for each time its view is made")
        #expect(made.first === shown)
        #expect(drafts === details, "the editor holds the window's drafts")
        #expect(shown.titleDrafts == nil, "the window's drafts leave with it")
        withExtendedLifetime(library) {}
    }

    @Test func anItemWindowMakesOneEditorHoweverOftenItsViewIsMadeAgain() async throws {
        let library = ItemPreviewFixtures.library
        let (made, shown, drafts) = try await Self.editorsMade(remaking: 5) {
            NoteWindow(id: .constant(ItemPreviewFixtures.ticketID))
                .environment(\.library, library)
        }
        #expect(made.count == 1, "one editor for the window, not one for each time its view is made")
        #expect(made.first === shown)
        #expect(drafts != nil, "the editor holds the window's drafts")
        #expect(shown.titleDrafts == nil, "the window's drafts leave with it")
        withExtendedLifetime(library) {}
    }

    @Test func aRefusedTitleInAClosedWindowNeverHoldsUpQuittingOrRenamesTheNote() async throws {
        let library = ItemPreviewFixtures.library
        let ticket = ItemPreviewFixtures.ticketID
        _ = try await Self.openAndClose(library, item: ticket) { editor, web in
            _ = try await web.evaluateJavaScript("""
                const title = document.getElementById('ItemPageTitle'); title.focus()
                document.execCommand('selectAll'); document.execCommand('insertText', false, 'Review/photos')
                title.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true })); 0
                """)
            for _ in 0..<200 where try await web.evaluateJavaScript("!document.querySelector('.item-title-error').hidden") as? Bool != true {
                try await Task.sleep(for: .milliseconds(50))
            }
            // Deleted from another window, so closing this one is allowed: the draft cannot be saved anywhere.
            library.delete([ticket], undoManager: nil)
            for _ in 0..<200 where editor.isEditable { try await Task.sleep(for: .milliseconds(50)) }
            #expect(!editor.isEditable, "the page shows the note deleted")
        }
        library.recover([ticket], undoManager: nil)
        let kept = await withCheckedContinuation { continuation in EditorController.flushAll { continuation.resume(returning: $0) } }
        #expect(kept, "a draft no window holds cannot stop quitting")
        #expect(library.failure == nil)
        #expect(library.item(ticket)?.title == "Review the findings")
    }

    @Test func aRefusedEmptyTitleIsToldAsEmpty() async throws {
        let host = try await HostedPage()
        defer { host.close() }
        try await host.type("")
        try await host.pressReturn()
        try await host.waitFor("the page to show the refusal") { try await host.titleError() == true }
        #expect(await !host.flushAll())
        #expect(host.library.failure?.message == "The title for “Review the findings” is empty. Open the item to enter a title or discard your changes.")
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
        first.drafts.draft(for: first.ticket, key: "title").text = "Review/photos"
        first.drafts.draft(for: first.ticket, key: "title").isDirty = true
        second.drafts.draft(for: ItemPreviewFixtures.noteID, key: "title").text = "Field/notes"
        second.drafts.draft(for: ItemPreviewFixtures.noteID, key: "title").isDirty = true
        let kept = await withCheckedContinuation { continuation in EditorController.flushAll { continuation.resume(returning: $0) } }
        #expect(!kept)
        #expect(shown.count == 1, "one refusal is told, and its window shows its item")
        let told = try #require(shown.first)
        let message = try #require(library.failure?.message)
        let window = told == first.ticket ? first.window : second.window
        #expect(message.contains(told == first.ticket ? "“Review/photos”" : "“Field/notes”"), "\(message)")
        #expect(window.isKeyWindow || window.isMainWindow || NSApp.orderedWindows.first === window, "the window holding the draft comes forward")
    }

    @Test func aTitleTypedButNotLeftIsSavedBeforeQuittingAndARefusalStopsIt() async throws {
        let host = try await HostedPage()
        defer { host.close() }
        try await host.type("Review before quitting")
        #expect(await host.flushAll())
        #expect(host.library.item(host.ticket)?.title == "Review before quitting")
        #expect(host.library.failure == nil)

        try await host.type("Review/before quitting")
        #expect(await !host.flushAll(), "a title that cannot be saved stops quitting rather than being lost")
        #expect(host.library.item(host.ticket)?.title == "Review before quitting")
        #expect(host.library.failure?.message.contains("“Review/before quitting”") == true)
        try await host.waitFor("the page to show the refusal") { try await host.titleError() == true }
    }

    @Test func aRefusedTitleForANoteNoLongerShownStillStopsQuittingAndNamesTheNote() async throws {
        let host = try await HostedPage()
        defer { host.close() }
        try await host.type("Review/photos")
        try await host.pressReturn()
        try await host.waitFor("the page to show the refusal") { try await host.titleError() == true }
        host.shown.id = ItemPreviewFixtures.noteID
        try await host.waitForTitle("Field notes")
        #expect(await !host.flushAll())
        let message = try #require(host.library.failure?.message)
        #expect(message.contains("“Review/photos”") && message.contains("“Review the findings”"), "\(message)")
        // Deleting a note keeps the window, so a refused title is tried again but stops nothing.
        host.library.failure = nil
        #expect(await host.flushAll(leaving: false))
        #expect(host.library.failure == nil)
        #expect(host.drafts.draft(for: host.ticket, key: "title").rejected)
    }

    @Test func aTitleRefusedBecauseTheNameWasTakenIsSavedOnceTheNameIsFree() async throws {
        let host = try await HostedPage()
        defer { host.close() }
        let taken = Note(path: "Tickets/Taken.md", text: "Taken\n", created: .now)
        host.library.notes.append(taken)
        try await host.type("Taken")
        try await host.pressReturn()
        try await host.waitFor("the page to show the refusal") { try await host.titleError() == true }
        host.shown.id = ItemPreviewFixtures.noteID
        try await host.waitForTitle("Field notes")
        #expect(host.library.setItemProperty(taken.id, key: "title", value: .string("Taken before"), undoManager: nil))
        #expect(await host.flushAll())
        #expect(host.library.item(host.ticket)?.title == "Taken")
        #expect(!host.drafts.draft(for: host.ticket, key: "title").isDirty)
    }

    @Test func closingTheWindowWithARefusedTitleIsCancelledAndSaysWhy() async throws {
        let host = try await HostedPage()
        defer { host.close() }
        try await host.type("Review/photos")
        try await host.pressReturn()
        try await host.waitFor("the page to show the refusal") { try await host.titleError() == true }
        host.window.performClose(nil)
        try await host.waitFor("the refusal to be told") { host.library.failure != nil }
        #expect(host.library.failure?.message.contains("“Review/photos”") == true)
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
            for _ in 0..<200 where try await !condition() { try await Task.sleep(for: .milliseconds(50)) }
            try #require(try await condition(), "waiting for \(what)")
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

    // MARK: Notes the page links to

    private func addNotes(_ titles: [String], to page: Harness) -> [ItemID] {
        titles.map { title in
            let note = Note(body: title + "\n", created: .now)
            page.library.notes.append(note)
            return note.id
        }
    }

    private func ask(_ page: Harness, _ request: String) async throws -> Any? {
        try await page.editor.webView.callAsyncJavaScript(
            "return await window.webkit.messageHandlers.notes.postMessage(\(request))", arguments: [:], in: nil, contentWorld: .page)
    }

    @Test func theNotesAreOfferedAfterDoubleBracketsFromTheLibrary() async throws {
        let page = try await Harness()
        _ = addNotes(["Garden ideas", "Bike service", "Gardening tools"], to: page)
        try await page.load("Intro\n")
        let names = try await ask(page, "{ type: 'suggest', query: 'gard' }") as? [String]
        #expect(Set(names ?? []) == ["Garden ideas", "Gardening tools"])
        #expect(try await ask(page, "{ type: 'suggest', query: 'zzz' }") as? [String] == [])
        let unread = try await ask(page, "{ type: 'nonsense' }")
        #expect(unread == nil || unread is NSNull, "a request that cannot be read is answered, not left waiting")
    }

    @Test func linkToNoteWaitsForTheChoiceAndAnswersWithTheLink() async throws {
        let page = try await Harness()
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
        let page = try await Harness()
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
        let page = try await Harness()
        try await page.load("\n")
        let labels = try await page.editor.webView.evaluateJavaScript("window.mappLabels") as? [String: String]
        #expect(labels?["linkToNote"] == "Link to Note")
        #expect(labels?["slashTable"] == "Table")
        #expect(labels?["suggestionsLoading"] == "Loading…")
        #expect(labels?["suggestionsEmpty"] == "No Results")
    }

    @Test func quotesAndDashesStayAsTypedBecauseSmartPunctuationIsOff() async throws {
        let page = try await Harness()
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

    private func pending(_ page: Harness) async throws -> ItemID {
        let current = try #require(page.editor.noteID)
        try await page.run("window.pick = window.webkit.messageHandlers.notes.postMessage({ type: 'pick', item: '\(current.rawValue)' })")
        try await page.wait { page.editor.linkRequest != nil }
        return current
    }

    /// What the page was answered, or "PENDING" if it is still waiting after a moment.
    private func answer(_ page: Harness) async throws -> String? {
        let script = "return await Promise.race([window.pick, new Promise(done => setTimeout(() => done('PENDING'), 1500))])"
        let value = try await page.editor.webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        return value as? String
    }

    /// What the library resolves a link to, written on a note of its own so the library reads it as a person's would.
    private func resolution(of link: String, in library: NoteLibrary) -> NoteReferenceResolution? {
        let reader = Note(body: "See \(link)\n", path: "Reader of links.md", created: .now)
        library.notes.append(reader)
        defer { library.notes.removeAll { $0.id == reader.id } }
        return library.connectionIndex.referencesBySource[reader.id]?.first?.resolution
    }

    @Test func choosingBetweenNotesWithTheSameTitleLinksToTheOneChosen() async throws {
        let page = try await Harness()
        let older = Note(body: "Garden\n", path: "Home/Garden.md", created: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = Note(body: "garden\n", path: "Work/garden.md", created: Date(timeIntervalSince1970: 1_800_000_000))
        page.library.notes += [older, newer]
        try await page.load("Intro\n")
        _ = try await pending(page)
        page.editor.finishLinkRequest(choosing: older.id)
        let link = try #require(try await answer(page), "a note that can be named is linked")
        #expect(resolution(of: link, in: page.library) == .resolved(older.id), "\(link) names the note chosen and no other")
    }

    @Test func aTargetRenamedWhileThePickerIsOpenIsLinkedByItsNewTitle() async throws {
        let page = try await Harness()
        let target = Note(body: "Garden\n", path: "Garden.md", created: .now)
        page.library.notes.append(target)
        try await page.load("Intro\n")
        _ = try await pending(page)
        page.library.renameNote(target.id, to: "Allotment", undoManager: nil)
        try #require(page.library.item(target.id)?.title == "Allotment")
        page.editor.finishLinkRequest(choosing: target.id)
        #expect(try await answer(page) == "[[Allotment]]")
    }

    @Test func everySuggestionAndTheLinkForAnyNoteResolvesToThatNote() async throws {
        let page = try await Harness()
        let identity = "11111111-1111-4111-8111-111111111111"
        let chosen = Note(body: "---\ntitle: \(identity)\n---\nBody\n", path: "Chosen.md", created: .now)
        let other = Note(body: "---\nmarfa_id: \(identity)\n---\nOther\n", path: "Other.md", created: .now)
        let plain = Note(body: "Garden\n", path: "Garden.md", created: .now)
        page.library.notes += [chosen, other, plain]
        try await page.load("Intro\n")
        let library = page.library
        let index = NoteLinks.Index()
        for query in ["", "1111", "gar", "oth"] {
            for name in await library.noteNames(matching: query, using: index) {
                let owner = try #require(library.notes.first { $0.title == name }, "\(name)")
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
        let page = try await Harness()
        let identity = "22222222-2222-4222-8222-222222222222"
        let declared = Note(body: "---\nmarfa_id: \(identity)\n---\nWork on it\n", path: "Home/Chosen.md", created: .now)
        page.library.notes.append(declared)
        for title in ["A|B", "A#B", "A]B", "[Draft]", "back\\slash", "Café 日本語", "line\nbreak"] {
            let link = NoteLinks.identityLink(to: identity, titled: title, readsBrackets: false)
            #expect(resolution(of: link, in: page.library) == .resolved(declared.id), "\(link)")
        }
        #expect(NoteLinks.identityLink(to: identity, titled: "A]B", readsBrackets: false) == "[[\(identity)]]")
        #expect(NoteLinks.identityLink(to: identity, titled: "A|B", readsBrackets: false) == "[[\(identity)|A\\|B]]")
    }

    @Test func aNoteNoLinkCanNameAloneLeavesTheRequestOpenForAnotherChoice() async throws {
        let page = try await Harness()
        let first = Note(body: "Plan\n", path: "Home/Plan.md", created: .now)
        let second = Note(body: "plan\n", path: "Home/plan.md", created: .now)
        let other = Note(body: "Garden\n", path: "Garden.md", created: .now)
        page.library.notes += [first, second, other]
        try await page.load("Intro\n")
        _ = try await pending(page)
        #expect(!page.editor.finishLinkRequest(choosing: first.id), "no spelling names it alone")
        #expect(page.editor.linkRequest != nil, "the request stays open")
        #expect(page.editor.finishLinkRequest(choosing: other.id))
        #expect(try await answer(page) == "[[Garden]]")
    }

    @Test func aLinkRequestAfterTheWindowWentIsAnsweredWithNothing() async throws {
        let page = try await Harness()
        try await page.load("Intro\n")
        let editor = page.editor
        editor.windowWent()
        let current = try #require(editor.noteID)
        try await page.run("window.pick = window.webkit.messageHandlers.notes.postMessage({ type: 'pick', item: '\(current.rawValue)' })")
        #expect(try await answer(page) == nil)
        #expect(editor.linkRequest == nil)
    }

    @Test func loadingAnotherNoteAnswersAPendingLinkRequestOnce() async throws {
        let page = try await Harness()
        page.library.notes.append(Note(body: "Garden\n", path: "Garden.md", created: .now))
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
