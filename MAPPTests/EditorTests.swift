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
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
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
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
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
            _ = try await page.editor.webView.evaluateJavaScript("1")
            for width in [CGFloat(360), 900, 500] {
                let before = rects()
                window.setContentSize(NSSize(width: width, height: 600))
                #expect(page.editor.webView.frame.width == width)
                try await page.wait { rects() != before }
                #expect(rects().contains { $0.width > 0 && $0.height > 0 })
                #expect(try await page.editor.webView.evaluateJavaScript("window.innerWidth") as? Double == Double(width))
            }
            // A header that wraps differently moves the text below it.
            let header = Self.header(source ? "A short title" : String(repeating: "A title long enough to wrap ", count: 2))
            for command in ["setTextSize(\(source ? 20 : 18))", "setHeader(\(Self.json(header)))"] {
                let before = rects()
                try await page.run("window.editor.\(command)")
                try await page.wait { rects() != before }
            }
            if !source {
                window.setContentSize(NSSize(width: 1400, height: 600))
                _ = try await page.editor.webView.evaluateJavaScript("1")
                try await Task.sleep(for: .milliseconds(100))
                for command in ["setFullWidth(true)", "setFullWidth(false)", "setReadingWidth(24)"] {
                    let before = rects()
                    try await page.run("window.editor.\(command)")
                    try await page.wait { rects() != before }
                }
            }
        }
        try await page.run("window.editor.setFinding(false)")
        let stopped = rects()
        try await page.run("window.editor.setHeader(\(Self.json(Self.header(String(repeating: "Another title ", count: 12)))))")
        try await Task.sleep(for: .milliseconds(100))
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
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
        let window = NSWindow(
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
        #expect(markdown.split(separator: "\n").contains { $0.hasPrefix("|") && $0.contains("---") })
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
                "[...document.querySelectorAll('.image img')].map((image) => image.naturalWidth)"
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 1400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        defer {
            window.contentView = nil
            window.close()
        }
        page.editor.load(try #require(library.item(note.id)))
        let editor = page.editor

        let image = try await settle(editor, "(() => { const i = document.querySelector('.image img'); return i ? [i.naturalWidth, Math.round(i.getBoundingClientRect().width)] : [] })()", as: [Int].self) { $0 == [5, 3] }
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
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
        PageHeader(item: id.rawValue, hidden: hidden, title: title, draft: nil, titleRejected: false, editable: true,
                   type: "Task", status: .init(label: "In Progress", enabled: true),
                   parent: .init(label: "Field Research", enabled: true), propertyRejected: false, interfaceTextSize: 13)
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
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await page.load(Array(repeating: "A paragraph for the scrolling check.", count: 60).joined(separator: "\n\n") + "\n")
        page.editor.setHeader(Self.header("Review the findings"))
        _ = try await page.editor.webView.evaluateJavaScript("1")
        let shown = try await page.editor.webView.evaluateJavaScript(
            "[...document.querySelectorAll('#ItemPageTitle, #ItemTypeChip, #ItemStatusChip, #ItemParentChip')].map(e => e.textContent)"
        ) as? [String]
        #expect(shown == ["Review the findings", "Task", "In Progress", "Field Research"])

        // The title and the text start at the same margin whatever the width, the reading width or Full Width.
        for (width, full) in [(CGFloat(360), false), (900, false), (1400, false), (1400, true)] {
            window.setContentSize(NSSize(width: width, height: 500))
            page.editor.setStyle(PageStyle(fullWidth: full))
            _ = try await page.editor.webView.evaluateJavaScript("1")
            try await Task.sleep(for: .milliseconds(50))
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
    }

    @Test func aChipAsksForItsMenuUnderItsFrameInTheEditor() async throws {
        let page = try await Harness()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
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
        let chip = try await Self.rect("#ItemStatusChip", in: page)
        let viewport = try #require(try await page.editor.webView.evaluateJavaScript("window.innerHeight") as? Double)
        try await page.run("document.getElementById('ItemStatusChip').dispatchEvent(new PointerEvent('pointerdown', { button: 0, bubbles: true, cancelable: true }))")
        try await page.run("document.getElementById('ItemParentChip').click()")
        try await page.wait { menus.count == 2 }
        #expect(menus.map(\.0) == [.status, .parent])
        #expect(menus.allSatisfy { $0.1 == id })
        // The page's window starts below what covers the web view's top; the frame is in the container's terms.
        let covered = page.editor.webView.bounds.height - viewport
        let expected = page.editor.container.convert(CGRect(x: chip[0], y: chip[1] + covered, width: chip[2], height: chip[3]), from: page.editor.webView)
        #expect(abs(menus[0].2.minX - expected.minX) < 0.5 && abs(menus[0].2.minY - expected.minY) < 0.5)
        #expect(abs(menus[0].2.width - chip[2]) < 0.5 && abs(menus[0].2.height - chip[3]) < 0.5)
        #expect(menus[0].2.minY > 52 - 30, "the chip lies below the covered top, less what has scrolled")
    }

    /// An item's page as the app shows it: the native view, reading the item from the library, over the page.
    @Observable final class Shown {
        var id: ItemID
        init(_ id: ItemID) { self.id = id }
    }

    struct PageHost: View {
        let library: NoteLibrary
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
        let library = ItemPreviewFixtures.library
        let ticket = ItemPreviewFixtures.ticketID
        let page: Harness
        let drafts = DetailsPresentation()
        let shown: Shown
        let window: NSWindow

        init() async throws {
            page = try await Harness(library: library)
            shown = Shown(ticket)
            window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PageHost(library: library, editor: page.editor, drafts: drafts, shown: shown)
                .environment(\.library, library))
            window.makeKeyAndOrderFront(nil)
            try await waitForTitle("Review the findings")
        }

        func close() {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }

        func value(_ script: String) async throws -> Any? {
            try await page.editor.webView.evaluateJavaScript(script)
        }

        func shownTitle() async throws -> String? {
            try await value("document.getElementById('ItemPageTitle').textContent") as? String
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

        func waitFor(_ condition: () async throws -> Bool) async throws {
            for _ in 0..<60 where try await !condition() { try await Task.sleep(for: .milliseconds(50)) }
            try #require(try await condition())
        }

        func waitForTitle(_ title: String) async throws {
            try await waitFor { try await self.shownTitle() == title }
        }
    }

    @Test func theTitleIsSavedFromThePageAndARefusalIsShownThere() async throws {
        let host = try await HostedPage()
        defer { host.close() }
        let library = host.library, ticket = host.ticket, page = host.page
        let status = try await host.value("document.querySelector('#ItemStatusChip .item-chip-label').textContent") as? String
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
        try await Task.sleep(for: .milliseconds(200))
        #expect(commits == 1, "leaving the title after Return does not save it again")

        // The change is undone as the app's own, from the window's undo manager, and the page shows it.
        #expect(host.window.undoManager?.canUndo == true)
        host.window.undoManager?.undo()
        try await page.wait { library.item(ticket)?.title == "Review the findings" }
        try await host.waitForTitle("Review the findings")

        // A title the library refuses stays as typed, with the reason, and survives moving to another note and back.
        try await host.type("Review/photographs")
        try await host.pressReturn()
        try await host.waitFor { try await host.titleError() == true }
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
        try await host.waitFor { try await host.value("document.getElementById('item-header').hidden") as? Bool == true }
        host.library.recover([host.ticket])
        try await host.page.wait { host.page.editor.isEditable }
        try await host.waitFor { try await host.value("document.getElementById('item-header').hidden") as? Bool == false }
    }
}
