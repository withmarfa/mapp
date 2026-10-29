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

    @Test func webAddressPictureWaitsForTheOwnersChoiceThenLoadsThroughTheApp() async throws {
        let folder = try TemporaryFolder()
        let suite = "EditorPictureTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(RemotePictureSetting.ask.rawValue, forKey: RemotePictureSetting.key)
        let host = PictureStub.newHost()
        let address = "https://\(host)/rss-picture.png"
        PictureStub.answer(address, with: .body([SamplePicture.png()]))
        let page = try await Page(library: FakeItemLibrary(), pictures: WebPictures(
            cache: PictureCache(folder: folder.url.appending(path: "Cache")),
            fetcher: PictureFetcher(resolver: PictureStub.resolver, configuration: PictureStub.configuration),
            defaults: defaults))
        try await page.load("![RSS picture](\(address))\r\n")
        let label = try await settle(page.editor,
            "document.querySelector('.inkkit-file[data-inkkit-file-kind=file] .inkkit-file-label')?.textContent",
            as: String.self) { $0 == "Load Picture: RSS picture" }
        #expect(label == "Load Picture: RSS picture")
        #expect(try await page.editor.webView.evaluateJavaScript(
            "document.querySelector('.inkkit-file-open')?.getAttribute('aria-label')"
        ) as? String == "Open Load Picture: RSS picture")
        #expect(try await page.editor.webView.evaluateJavaScript(
            "document.querySelectorAll('.ProseMirror img, .ProseMirror iframe').length"
        ) as? Int == 0)
        #expect(try await page.editor.webView.evaluateJavaScript(
            "performance.getEntriesByType('resource').some(entry => /^https?:/.test(entry.name))"
        ) as? Bool == false)
        #expect(PictureStub.requests(to: address).isEmpty)
        try await page.run("document.querySelector('.inkkit-file-open').click()")
        let loaded = try await settle(page.editor,
            "(() => { const image = document.querySelector('.inkkit-image img'); return !!image && image.naturalWidth > 0 && image.src.startsWith('mapp-embed:'); })()",
            as: Bool.self) { $0 == true }
        #expect(loaded == true)
        #expect(PictureStub.requests(to: address).count == 1)
        #expect(try await page.editor.webView.evaluateJavaScript(
            "performance.getEntriesByType('resource').some(entry => /^https?:/.test(entry.name))"
        ) as? Bool == false)
        #expect(try await page.markdown() == nil)
        #expect(page.changes.isEmpty)
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

        ![[Budget.csv]] ![[Missing.zip]] ![far](../../outside.png) ![[A note]] ![[Offline.png]]

        """
        let page = try await Page()
        let note = page.library.add(body)
        for (text, name) in [("![[Photo.png|3]]", "Photo.png"), ("![[Clip.mov]]", "Clip.mov"), ("![[Plan.pdf]]", "Plan.pdf"), ("![[Budget.csv]]", "Budget.csv")] {
            page.library.bindEmbed(text, in: note.id, file: attachments.appending(path: name))
        }
        page.library.bindEmbed("![](../Attachments/Tone.wav)", in: note.id, file: attachments.appending(path: "Tone.wav"))
        page.library.bindEmbed("![[Missing.zip]]", in: note.id)
        page.library.bindEmbed("![far](../../outside.png)", in: note.id)
        page.library.bindEmbed("![[Offline.png]]", in: note.id, resolution: .refused("The Marfa server can’t be reached."))
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
        let expectedMissing = [
            ["name": "Missing.zip", "status": "File Not Found"],
            ["name": "far", "status": "File Not Found"],
            ["name": "A note", "status": "File Not Found"],
        ]
        let missing = try await settle(editor,
            "[...document.querySelectorAll('.inkkit-file[data-inkkit-file-kind=missing]')].map(card => ({ name: card.querySelector('.inkkit-file-label')?.textContent, status: card.querySelector('.inkkit-file-status')?.textContent }))",
            as: [[String: String]].self) { $0 == expectedMissing }
        #expect(missing == expectedMissing)
        let unavailable = try await settle(editor, "[...document.querySelectorAll('.inkkit-file[data-inkkit-file-kind=error] .inkkit-file-label')].map(e => e.textContent)", as: [String].self) { $0 == ["Offline.png"] }
        #expect(unavailable == ["Offline.png"], "a file that can't be had now says so, rather than that it is missing")

        #expect(labels?.contains("Plan.pdf: Open to view this PDF") == true)
        #expect(try await editor.webView.evaluateJavaScript("!!document.querySelector('.inkkit-file iframe')") as? Bool == false)

        #expect(try await page.markdown() == nil, "showing the files changes nothing in the note")
    }

    @Test func aPictureAppearsWhenItsFileArrivesAndGoesWhenItIsBinned() async throws {
        let root = try TemporaryFolder()
        let photo = root.url.appending(path: "Photo.png")
        try EmbedFixtures.png(width: 5, height: 2).write(to: photo)
        let text = "![[Photo.png|400]]"
        let page = try await Page()
        let note = page.library.add("\(text)\n")
        page.library.bindEmbed(text, in: note.id, resolution: .pending)
        page.editor.load(note)
        let shown = try await settle(page.editor, "[...document.querySelectorAll('.inkkit-file')].map(card => card.dataset.inkkitFileKind)", as: [String].self) { $0?.isEmpty == false }
        #expect(shown?.contains("image") == false, "a file not yet in the library shows no picture")

        let id = try #require(page.library.bindEmbed(text, in: note.id, file: photo))
        let arrived = try await settle(page.editor, "document.querySelectorAll('.inkkit-file[data-inkkit-file-kind=image]').length", as: Int.self) { $0 == 1 }
        #expect(arrived == 1, "the picture shows once its file arrives, with the note untouched")
        #expect(try await page.markdown() == nil)

        page.library.items[try #require(page.library.items.firstIndex { $0.id == id })].state = .trashed
        let gone = try await settle(page.editor, "document.querySelectorAll('.inkkit-file[data-inkkit-file-kind=image]').length", as: Int.self) { $0 == 0 }
        #expect(gone == 0, "a binned file shows as not found")
    }

    @Test func aVideoLargerThanOneAnswerPlaysToItsEnd() async throws {
        let root = try TemporaryFolder()
        try FileManager.default.createDirectory(at: root.url.appending(path: "Attachments"), withIntermediateDirectories: true)
        let movie = root.url.appending(path: "Attachments/Long.mov")
        try EmbedFixtures.longMovie(to: movie, padding: Int(2 * EmbeddedFiles.window))
        let size = try #require(try movie.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        try #require(UInt64(size) > 2 * EmbeddedFiles.window, "the movie is \(size) bytes")
        let page = try await Page()
        let note = page.library.add("![[Long.mov]]\n")
        page.library.bindEmbed("![[Long.mov]]", in: note.id, file: movie)
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
        let note = page.library.add("A sheet: ![[Budget.csv]]\n")
        page.library.bindEmbed("![[Budget.csv]]", in: note.id, file: root.url.appending(path: "Attachments/Budget.csv"))
        page.editor.load(note)
        _ = try await settle(page.editor, "!!document.querySelector('.inkkit-file')", as: Bool.self) { $0 == true }
        try await page.run("document.querySelector('.inkkit-file').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true }))")
        try await page.wait { page.editor.menuEmbed != nil }
        #expect(page.editor.menuEmbed?.item == note.id)
        #expect(page.editor.menuEmbed?.reference == EmbedReference(text: "![[Budget.csv]]"))
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
        library.attaching = { AttachReport(embeds: [Embed(link: "Attachments/Photo.png", name: "Photo")]) }
        let editor = try await attachingEditor(library)
        #expect(editor.insertImages(Self.pasted))
        #expect(try await eventuallyAsking { try await markdown(editor)?.contains("![Photo](Attachments/Photo.png)") == true })
        #expect(library.notices.waiting.last == nil)
    }

    @Test func imagesTheLibraryCannotKeepAreReportedInThePersonsWords() async throws {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Plan", modified: .now)])
        library.attaching = { AttachReport(failed: [(name: "Photo.png", reason: "The server is out of space.")]) }
        let editor = try await attachingEditor(library)
        #expect(editor.insertImages(Self.pasted))
        #expect(await eventually { library.notices.waiting.last != nil })
        #expect(try await markdown(editor) == nil, "nothing is inserted")
        #expect(library.notices.waiting.last?.title == "Can’t Attach Images")
        #expect(library.notices.waiting.last?.message == "“Photo.png” couldn’t be attached. The server is out of space.")
    }

    @Test func imagesThatWereAttachedAreInsertedAndThoseThatWerentAreNamed() async throws {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Plan", modified: .now)])
        library.attaching = {
            AttachReport(embeds: [Embed(link: "Attachments/Photo.png", name: "Photo")], failed: [(name: "Other.png", reason: "The server is out of space.")])
        }
        let folder = try TemporaryFolder()
        let large = folder.url.appending(path: "Large.png")
        try #require(FileManager.default.createFile(atPath: large.path, contents: nil))
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(PastedImages.largestImage + 1))
        try handle.close()
        let editor = try await attachingEditor(library)
        #expect(editor.insertImages(Self.pasted + [.file(large)]))
        #expect(try await eventuallyAsking { try await markdown(editor)?.contains("![Photo](Attachments/Photo.png)") == true })
        #expect(library.notices.waiting.last?.title == "Some Images Weren’t Attached")
        #expect(library.notices.waiting.last?.message == "“Large.png” is larger than 50 MB or can’t be read.\n“Other.png” couldn’t be attached. The server is out of space.")
    }

    @Test func imagesAttachedAfterTheNoteChangesAreNamedAndNotInsertedIntoTheNextOne() async throws {
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
            return AttachReport(embeds: [Embed(link: "Attachments/Photo.png", name: "Photo")])
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
        #expect(library.notices.waiting.last?.title == "Images Weren’t Added to the Note")
        #expect(library.notices.waiting.last?.message == "“Photo” was attached to “Plan” but isn’t in its text, because the note was no longer open for editing.")
    }

    @Test func filesQuickAddAttachedGoAtTheEndOfTheNewNoteOnceThePageShowsIt() async throws {
        let shown = FakeItemLibrary.note("Plan", modified: .now)
        let new = FakeItemLibrary.note("Trip", modified: .now)
        let library = FakeItemLibrary(items: [shown, new])
        library.bodies[new.id] = "Pack\n\nBook\n"
        let editor = try await attachingEditor(library)
        var saved: [String] = []
        editor.onChange = { id, text, _ in if id == new.id { saved.append(text) } }

        editor.append([Embed(link: "map%201.png", name: "map 1.png"), Embed(link: "tickets.pdf", name: "tickets.pdf")], to: new.id)
        _ = try await editor.webView.evaluateJavaScript("1")
        #expect(try await markdown(editor) == nil, "the note on the page is another one")

        editor.load(new)
        editor.focus(new.id, caret: .after("Pack"))
        #expect(try await eventuallyAsking { try await markdown(editor)?.contains("tickets.pdf") == true })
        let written = try #require(try await markdown(editor))
        #expect(written.hasPrefix("Pack\n\nBook\n"))
        #expect(written.contains("![map 1.png](map%201.png)"))
        #expect(written.range(of: "map%201.png")!.lowerBound < written.range(of: "tickets.pdf")!.lowerBound)
        #expect(await eventually { editor.pendingEmbeds.isEmpty })
        editor.flush()
        #expect(await eventually { saved.last?.contains("tickets.pdf") == true }, "the page saves them as it does typing")
    }

    @Test func filesQuickAddAttachedWaitWhileTheNoteIsEditedAsSource() async throws {
        let new = FakeItemLibrary.note("Trip", modified: .now)
        let library = FakeItemLibrary(items: [new])
        library.bodies[new.id] = "Pack\n"
        let editor = try await attachingEditor(library)
        editor.setSourceMode(true)
        #expect(await eventually { editor.caret.sourceMode })

        editor.append([Embed(link: "tickets.pdf", name: "tickets.pdf")], to: new.id)
        _ = try await editor.webView.evaluateJavaScript("1")
        // Gives the page's answer time to come back, so a dropped embed would show as none waiting.
        try await Task.sleep(for: .milliseconds(200))
        #expect(try await markdown(editor) == nil, "source editing takes none")
        #expect(editor.pendingEmbeds[new.id]?.map(\.name) == ["tickets.pdf"], "they wait rather than go")
        #expect(library.notices.waiting.isEmpty)

        editor.setSourceMode(false)
        #expect(try await eventuallyAsking { try await markdown(editor) == "Pack\n\n![tickets.pdf](tickets.pdf)\n" })
        #expect(await eventually { editor.pendingEmbeds.isEmpty })
    }

    @Test func filesQuickAddAttachedToANoteEndingInAnOpenCodeFenceAreTold() async throws {
        let new = FakeItemLibrary.note("Trip", modified: .now)
        let library = FakeItemLibrary(items: [new])
        library.bodies[new.id] = "```\ncode"
        let editor = try await attachingEditor(library)

        editor.append([Embed(link: "tickets.pdf", name: "tickets.pdf")], to: new.id)
        // The page also reports the refusal itself (Inkkit's `preservation`), so wait for the notice about the file.
        #expect(await eventually { library.notices.waiting.contains { $0.message.contains("“tickets.pdf”") } })
        let told = try #require(library.notices.waiting.first { $0.message.contains("“tickets.pdf”") })
        #expect(told.message.contains("“Trip”"))
        #expect(try await markdown(editor) == nil, "the note keeps its text exactly")
        #expect(editor.pendingEmbeds.isEmpty, "the refusal cannot change, so the files do not wait")
    }

    @Test func filesQuickAddPreserveLoneBlocksWhenAppending() async throws {
        for body in ["***", "```\n```\n", "![x](y.png)", "[ref]: http://x.com"] {
            let new = FakeItemLibrary.note("Trip", modified: .now)
            let library = FakeItemLibrary(items: [new])
            library.bodies[new.id] = body
            let editor = try await attachingEditor(library)

            editor.append([Embed(link: "tickets.pdf", name: "tickets.pdf")], to: new.id)
            #expect(try await eventuallyAsking { try await markdown(editor)?.contains("![tickets.pdf](tickets.pdf)") == true })
            let appended = try #require(try await markdown(editor))
            #expect(appended.hasPrefix(body), "\(body) keeps its authored text")
            #expect(library.notices.waiting.isEmpty)
            #expect(await eventually { editor.pendingEmbeds.isEmpty })
        }
    }

    @Test func filesQuickAddAttachedThatNeverReachTheTextAreTold() async throws {
        let new = FakeItemLibrary.note("Trip", modified: .now)
        let library = FakeItemLibrary(items: [new])
        let editor = try await attachingEditor(library)
        editor.setSourceMode(true)
        #expect(await eventually { editor.caret.sourceMode })
        editor.append([Embed(link: "tickets.pdf", name: "tickets.pdf")], to: new.id)
        // Gives the page time to answer, so a refusal told too early would show here.
        try await Task.sleep(for: .milliseconds(200))
        #expect(library.notices.waiting.isEmpty)

        editor.windowWent()
        #expect(editor.pendingEmbeds.isEmpty)
        let told = try #require(library.notices.waiting.last)
        #expect(told.message.contains("“tickets.pdf”") && told.message.contains("“Trip”"))
    }
}
