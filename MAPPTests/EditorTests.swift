import AppKit
import Foundation
import PDFKit
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

    @Test func aNoteOpenedAndLeftAloneIsNotRewritten() async throws {
        let page = try await Harness()
        try await page.load(kitchen)
        #expect(try await page.markdown() == nil)
        // Longer than the pause after which the page reports an edit.
        try await Task.sleep(for: .milliseconds(400))
        #expect(page.changes.isEmpty)
    }

    @Test func headingMarksAppearOnlyWhileEditing() async throws {
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
        let markers = "getComputedStyle(document.querySelector('h2'), '::before').content"
        let hidden = ["none", "normal", "\"\""]
        let beforeFocus = try await page.editor.webView.evaluateJavaScript(markers) as? String
        #expect(hidden.contains(beforeFocus ?? ""))
        page.editor.focus()
        try await page.run("0")
        let hasFocus = try await page.editor.webView.evaluateJavaScript(
            "document.activeElement === document.querySelector('.ProseMirror')"
        ) as? Bool
        #expect(hasFocus == true)
        let focused = try await page.editor.webView.evaluateJavaScript(markers) as? String
        #expect(focused == "\"##\"")
        try await page.run("document.querySelector('.ProseMirror').blur()")
        let afterBlur = try await page.editor.webView.evaluateJavaScript(markers) as? String
        #expect(hidden.contains(afterBlur ?? ""))
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
        #expect(markdown.contains("| --- | --- | --- |"))
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
        page.editor.onChange = { id, markdown, read in library.updateBody(of: id, to: markdown, readAt: read) }
        page.editor.load(try #require(library.item(note.id)))
        _ = try await page.editor.webView.evaluateJavaScript("1")
        page.editor.format(.checklist)
        // Another window's text, typed on the text it held.
        library.updateBody(of: note.id, to: "Outside\n")
        page.editor.noteChanged(try #require(library.item(note.id)))
        try await page.wait { library.notes.count == 2 }
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
        let absent = try await page.editor.webView.evaluateJavaScript(
            "[...document.querySelectorAll('.image-absent')].map((span) => span.textContent)"
        ) as? [String]
        #expect(absent == ["b"])
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
    }
}
