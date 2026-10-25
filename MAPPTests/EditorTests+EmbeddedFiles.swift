import AppKit
import Foundation
import Testing
import WebKit
@testable import MAPP

/// Files a note embeds, and images attached to it.
extension EditorTests {
    // MARK: Embedded files of any kind

    /// Evaluates a script until it answers what `done` accepts, as a page loading files takes its own time.
    func settle<T>(_ editor: EditorController, _ script: String, as: T.Type = T.self, until done: (T?) -> Bool) async throws -> T? {
        var value: T?
        _ = try await eventuallyAsking {
            value = try await editor.webView.evaluateJavaScript(script) as? T
            return done(value)
        }
        return value
    }

    /// Serves the page's embeds from `root` as a library will once it resolves them through the working copy's
    /// links: a name from `Attachments/`, a path from `directory`, each opened only inside `root`.
    func serveEmbeds(_ editor: EditorController, from root: URL, directory: String = "") {
        editor.embeds.open = { reference, _ in
            guard let real = OpenFile.realPath(of: root) else { return nil }
            let file = switch reference {
            case .name(let name): real.appending(path: "Attachments/\(name)")
            case .path(let path): real.appending(path: directory).appending(path: path.removingPercentEncoding ?? path).standardized
            }
            return await OpenFile.open(file, inside: root)
        }
    }

    @Test func eachKindOfEmbeddedFileShowsAsWhatItIs() async throws {
        let root = try TemporaryFolder()
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
        let page = try await Page()
        serveEmbeds(page.editor, from: root.url, directory: "Projects")
        let note = page.library.add(body)
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 1400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        defer {
            window.contentView = nil
            window.close()
        }
        page.editor.load(note)
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
        #expect(try await editor.webView.evaluateJavaScript("!!document.querySelector('.inkkit-file iframe')") as? Bool == false)

        #expect(try await page.markdown() == nil, "showing the files changes nothing in the note")
    }

    @Test func aVideoLargerThanOneAnswerPlaysToItsEnd() async throws {
        let root = try TemporaryFolder()
        try FileManager.default.createDirectory(at: root.url.appending(path: "Attachments"), withIntermediateDirectories: true)
        let movie = root.url.appending(path: "Attachments/Long.mov")
        try EmbedFixtures.longMovie(to: movie, padding: Int(2 * EmbeddedFiles.window))
        let size = try #require(try movie.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        try #require(UInt64(size) > 2 * EmbeddedFiles.window, "the movie is \(size) bytes")
        let page = try await Page()
        serveEmbeds(page.editor, from: root.url)
        let note = page.library.add("![[Long.mov]]\n")
        // WebKit loads no media for a page outside a window.
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page.editor.container
        defer {
            window.contentView = nil
            window.close()
        }
        page.editor.load(note)
        let duration = try await settle(page.editor, "(() => { const v = document.querySelector('video'); return v && v.readyState >= 1 ? v.duration : -1 })()", as: Double.self) { ($0 ?? -1) > 0 }
        try #require((duration ?? 0) > 3)
        try await page.run("const v = document.querySelector('video'); v.currentTime = v.duration - 0.1")
        let shown = try await settle(page.editor, "(() => { const v = document.querySelector('video'); return !v.seeking && v.readyState >= 2 && v.currentTime > v.duration - 0.5 })()", as: Bool.self) { $0 == true }
        #expect(shown == true, "the frames past the first answer load")
    }

    @Test func theContextMenuOverAnEmbeddedFileKnowsWhichFile() async throws {
        let root = try TemporaryFolder()
        try FileManager.default.createDirectory(at: root.url.appending(path: "Attachments"), withIntermediateDirectories: true)
        try Data("a,b\n".utf8).write(to: root.url.appending(path: "Attachments/Budget.csv"))
        let page = try await Page()
        serveEmbeds(page.editor, from: root.url)
        let note = page.library.add("A sheet: ![[Budget.csv]]\n")
        page.editor.load(note)
        _ = try await settle(page.editor, "!!document.querySelector('.inkkit-file')", as: Bool.self) { $0 == true }
        try await page.run("document.querySelector('.inkkit-file').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true }))")
        try await page.wait { page.editor.menuEmbed != nil }
        #expect(page.editor.menuEmbed?.item == note.id)
        #expect(page.editor.menuEmbed?.reference == .name("Budget.csv"))
        _ = page.editor.takeMenuEmbed()
        try await page.run("document.querySelector('p').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true }))")
        _ = try await page.editor.webView.evaluateJavaScript("1")
        #expect(page.editor.menuEmbed == nil, "a menu elsewhere offers no file")
    }

    // MARK: Attaching images through any library

    /// An editor over a library held in memory, showing `notes[0]` once its page has loaded.
    func attachingEditor(_ library: FakeItemLibrary) async throws -> EditorController {
        let editor = EditorController(library: library)
        try #require(await eventually { editor.isReady })
        editor.load(library.items[0])
        _ = try await editor.webView.evaluateJavaScript("1")
        return editor
    }

    static let pasted = [PastedImages.Source.data(name: "Photo.png", Data("png".utf8))]

    /// What the page would save, or nil while it is as loaded.
    func markdown(_ editor: EditorController) async throws -> String? {
        try await editor.webView.evaluateJavaScript("window.editor.markdown()") as? String
    }

    @Test func attachedImagesAreInsertedIntoTheNote() async throws {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Plan", modified: .now)])
        library.attaching = { [Embed(link: "Attachments/Photo.png", name: "Photo")] }
        let editor = try await attachingEditor(library)
        #expect(editor.insertImages(Self.pasted))
        #expect(try await eventuallyAsking { try await markdown(editor)?.contains("![Photo](Attachments/Photo.png)") == true })
        #expect(library.failure == nil)
    }

    @Test func imagesTheLibraryCannotKeepAreReportedInThePersonsWords() async throws {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Plan", modified: .now)])
        library.attaching = { throw SourceFailure(kind: .failed, message: "The server is out of space.") }
        let editor = try await attachingEditor(library)
        #expect(editor.insertImages(Self.pasted))
        #expect(await eventually { library.failure != nil })
        #expect(try await markdown(editor) == nil, "nothing is inserted")
        #expect(library.failure?.title == "Can’t Attach Images")
        #expect(library.failure?.message == "The images weren’t added to the note. The server is out of space.")
    }

    @Test func imagesAttachedAfterTheNoteChangesAreNotInsertedIntoTheNextOne() async throws {
        let first = FakeItemLibrary.note("Plan", modified: .now)
        let second = FakeItemLibrary.note("Other", modified: .now)
        let library = FakeItemLibrary(items: [first, second])
        let (gate, open) = AsyncStream<Void>.makeStream()
        var started = false
        var answered = false
        library.attaching = {
            started = true
            for await _ in gate { break }
            defer { answered = true }
            return [Embed(link: "Attachments/Photo.png", name: "Photo")]
        }
        let editor = try await attachingEditor(library)
        #expect(editor.insertImages(Self.pasted))
        try #require(await eventually { started })
        editor.load(second)
        _ = try await editor.webView.evaluateJavaScript("1")
        open.yield()
        open.finish()
        try #require(await eventually { answered })
        // Time for an insertion made from the late answer to reach the page, which nothing signals when none is made.
        try await Task.sleep(for: .milliseconds(300))
        #expect(try await markdown(editor) == nil, "the note now on the page takes nothing")
        #expect(editor.noteID == second.id)
        #expect(library.failure == nil)
    }
}
