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
            editor.onChange = { [unowned self] _, markdown in changes.append(markdown) }
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
        page.editor.onChange = { id, markdown in library.updateBody(of: id, to: markdown) }
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

    @Test func anEditOverlappingAnOutsideChangeWinsOnThePageAsInTheFile() async throws {
        let note = Note(body: "Milk\n", created: .now)
        let library = NoteLibrary(notes: [note], store: RecordingStore())
        let page = try await Harness(library: library)
        page.editor.onChange = { id, markdown in library.updateBody(of: id, to: markdown) }
        page.editor.load(try #require(library.item(note.id)))
        _ = try await page.editor.webView.evaluateJavaScript("1")
        // The person's edit is still waiting to be reported when another app's change is taken in.
        page.editor.format(.checklist)
        library.updateBody(of: note.id, to: "Outside\n")
        page.editor.noteChanged(try #require(library.item(note.id)))
        try await page.wait { library.note(note.id)?.body == "- [ ] Milk\n" }
        var shown = ""
        for _ in 0..<40 {
            shown = try await page.editor.webView.evaluateJavaScript("document.querySelector('.ProseMirror').textContent") as? String ?? ""
            if shown == "Milk" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(shown == "Milk")
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
        try await EmbedFixtures.movie(to: attachments.appending(path: "Clip.mov"))
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

        let audio = try await settle(editor, "(() => { const a = document.querySelector('.embed-audio audio'); return a && a.readyState >= 1 ? a.duration : -1 })()", as: Double.self) { ($0 ?? -1) > 0 }
        #expect(abs((audio ?? 0) - 0.5) < 0.05, "the sound's length is read through ranges of the file")

        let video = try await settle(editor, "(() => { const v = document.querySelector('.embed-video video'); return v && v.readyState >= 1 ? [v.videoWidth, v.videoHeight] : [] })()", as: [Int].self) { $0 == [64, 64] }
        #expect(video == [64, 64])

        let frame = try await settle(editor, "document.querySelector('.embed-pdf iframe')?.src ?? ''", as: String.self) { $0?.isEmpty == false }
        #expect(frame?.hasPrefix("mapp-embed://file/") == true)

        let card = try await settle(editor, "(() => { const c = document.querySelector('.embed-card'); const i = c?.querySelector('img'); return c && i?.complete && i.naturalWidth > 0 ? [c.querySelector('.embed-name').textContent, c.querySelector('.embed-detail').textContent] : [] })()", as: [String].self) { $0?.count == 2 }
        #expect(card?.first == "Budget.csv")
        #expect(card?.last?.isEmpty == false, "the card says how large the file is")

        let absent = try await editor.webView.evaluateJavaScript("[...document.querySelectorAll('.image-absent')].map((span) => span.textContent)") as? [String]
        #expect(absent == ["Missing.zip", "far"])
        let text = try await editor.webView.evaluateJavaScript("document.querySelector('.ProseMirror').textContent") as? String
        #expect(text?.contains("![[A note]]") == true, "an embedded note is text")

        // WebKit draws a PDF in a frame from the app's scheme: the red page shows where the frame is.
        let rect = try #require(try await editor.webView.evaluateJavaScript(
            "(() => { const r = document.querySelector('.embed-pdf iframe').getBoundingClientRect(); return [r.x, r.y, r.width, r.height] })()"
        ) as? [Double])
        var red = false
        for _ in 0..<60 where !red {
            try await Task.sleep(for: .milliseconds(100))
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3])
            configuration.afterScreenUpdates = true
            guard let snapshot = try? await editor.webView.takeSnapshot(configuration: configuration),
                  let bitmap = snapshot.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)) else { continue }
            let center = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB)
            red = (center?.redComponent ?? 0) > 0.8 && (center?.greenComponent ?? 1) < 0.3
        }
        #expect(red, "the PDF is drawn inside its frame")

        #expect(try await page.markdown() == nil, "showing the files changes nothing in the note")
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
        _ = try await settle(page.editor, "!!document.querySelector('.embed-card')", as: Bool.self) { $0 == true }
        try await page.run("document.querySelector('.embed-card').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true }))")
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
