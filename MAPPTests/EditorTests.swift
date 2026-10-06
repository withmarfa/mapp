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
        let editor = EditorController()
        var changes: [String] = []

        init() async throws {
            editor.onChange = { [unowned self] _, markdown in changes.append(markdown) }
            try await wait { self.editor.isReady }
        }

        func load(_ body: String, deleted: Bool = false) async throws {
            editor.load(Note(body: body, created: .now, deleted: deleted ? .now : nil))
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

    @Test func aFirstLineTypedWithASpaceAtItsEndNamesTheFileWithoutIt() async throws {
        let store = RecordingStore()
        let note = Note(body: "Plan\n", created: .now)
        let library = NoteLibrary(notes: [note], store: store)
        let page = try await Harness()
        page.editor.library = library
        page.editor.onChange = { id, markdown in library.updateBody(of: id, to: markdown) }
        page.editor.onLeave = { library.leave($0) }
        page.editor.load(try #require(library.note(note.id)))
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
        let page = try await Harness()
        page.editor.library = library
        page.editor.onChange = { id, markdown in library.updateBody(of: id, to: markdown) }
        page.editor.load(note)
        _ = try await page.editor.webView.evaluateJavaScript("1")
        // The person's edit is still waiting to be reported when another app's change is taken in.
        page.editor.format(.checklist)
        library.updateBody(of: note.id, to: "Outside\n")
        page.editor.noteChanged(try #require(library.note(note.id)))
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
        let page = try await Harness()
        page.editor.library = library
        page.editor.load(note)
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
