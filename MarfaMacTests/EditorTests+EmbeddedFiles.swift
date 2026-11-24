import AppKit
import Foundation
import Testing
import WebKit
@testable import MarfaMac

/// Files an item embeds, and images attached to it.
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
            "document.querySelector('.inkkit-file[data-inkkit-file-appearance=placeholder] .inkkit-file-label')?.textContent",
            as: String.self) { $0 == "RSS picture" }
        #expect(label == "RSS picture")
        #expect(try await page.editor.webView.evaluateJavaScript(
            "document.querySelector('.inkkit-file[data-inkkit-file-appearance=placeholder] button.inkkit-file-action')?.getAttribute('aria-label')"
        ) as? String == "Load RSS picture")
        #expect(try await page.editor.webView.evaluateJavaScript(
            "document.querySelectorAll('.ProseMirror img, .ProseMirror iframe').length"
        ) as? Int == 0)
        #expect(try await page.editor.webView.evaluateJavaScript(
            "performance.getEntriesByType('resource').some(entry => /^https?:/.test(entry.name))"
        ) as? Bool == false)
        #expect(PictureStub.requests(to: address).isEmpty)
        try await page.run("document.querySelector('.inkkit-file-action').click()")
        let loaded = try await settle(page.editor,
            "(() => { const image = document.querySelector('.inkkit-image img'); return !!image && image.naturalWidth > 0 && image.src.startsWith('marfa-embed:'); })()",
            as: Bool.self) { $0 == true }
        #expect(loaded == true)
        #expect(PictureStub.requests(to: address).count == 1)
        #expect(try await page.editor.webView.evaluateJavaScript(
            "performance.getEntriesByType('resource').some(entry => /^https?:/.test(entry.name))"
        ) as? Bool == false)
        #expect(try await page.markdown() == nil)
        #expect(page.changes.isEmpty)
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
        #expect(arrived == 1, "the picture shows once its file arrives, with the item untouched")
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

    // MARK: Quick Look on a file card

    /// Asks the editor for Quick Look as the card's action does, rather than finding the card's button, which waits on
    /// the page to draw the card and its actions and timed out on a busy runner.
    @Test func quickLookOnAFileCardShowsTheFileTheEmbedIsBoundTo() async throws {
        let root = try TemporaryFolder()
        let sheet = root.url.appending(path: "Budget.csv")
        try Data("a,b\n".utf8).write(to: sheet)
        let page = try await Page()
        let note = page.library.add("A sheet: ![[Budget.csv]]\n")
        page.library.bindEmbed("![[Budget.csv]]", in: note.id, file: sheet)
        page.editor.load(note)
        try await page.wait { page.editor.isReady }
        #expect(page.editor.quickLook == nil)
        let told = page.library.notices.told
        page.editor.quickLookEmbed(EmbedReference(text: "![[Budget.csv]]"), in: note.id)
        try await page.wait { page.editor.quickLook != nil }
        #expect(page.editor.quickLook?.current?.lastPathComponent == "Budget.csv")
        #expect(page.library.notices.told == told, "showing the file tells the person nothing")
        #expect(try await page.markdown() == nil, "the item's text is not changed")
        page.editor.dismissQuickLook()
        #expect(page.editor.quickLook == nil)
    }

    @Test func quickLookForAnEmbedTheLibraryNoLongerHoldsShowsNothingAndSaysWhy() async throws {
        let page = try await Page()
        let note = page.library.add("![[Gone.csv]]\n")
        page.library.bindEmbed("![[Gone.csv]]", in: note.id)
        page.editor.load(note)
        try await page.wait { page.editor.isReady }
        page.editor.quickLookEmbed(EmbedReference(text: "![[Gone.csv]]"), in: note.id)
        try await page.wait { !page.library.notices.waiting.isEmpty }
        #expect(page.library.notices.waiting.last?.title == String(localized: "Can’t Quick Look"))
        #expect(page.library.notices.waiting.last?.message == String(localized: "This file isn’t in Marfa."))
        #expect(page.editor.quickLook == nil)
    }

    @Test func quickLookForAnotherItemThanTheOneOnThePageDoesNothing() async throws {
        let root = try TemporaryFolder()
        let sheet = root.url.appending(path: "Budget.csv")
        try Data("a,b\n".utf8).write(to: sheet)
        let page = try await Page()
        let note = page.library.add("![[Budget.csv]]\n")
        let other = page.library.add("![[Budget.csv]]\n")
        page.library.bindEmbed("![[Budget.csv]]", in: other.id, file: sheet)
        page.editor.load(note)
        try await page.wait { page.editor.isReady }
        page.editor.quickLookEmbed(EmbedReference(text: "![[Budget.csv]]"), in: other.id)
        _ = try await page.editor.webView.evaluateJavaScript("1")
        #expect(page.editor.quickLook == nil, "a stale page cannot make the app show a file of an item it is not showing")
        #expect(page.library.notices.told == 0)
    }

    @Test func theQuickLookMessageNamesTheItemAndTheEmbedAndNothingElseIsTaken() throws {
        let body: [String: Any] = ["type": "quickLookEmbed", "embed": ["item": "abc", "text": "![[Budget.csv]]"]]
        guard case .quickLookEmbed(let item, let reference) = try #require(EditorMessage(body: body)) else {
            Issue.record("Not a Quick Look message")
            return
        }
        #expect(item == ItemID("abc"))
        #expect(reference == EmbedReference(text: "![[Budget.csv]]"))
        #expect(EditorMessage(body: ["type": "quickLookEmbed"]) == nil)
        #expect(EditorMessage(body: ["type": "quickLookEmbed", "embed": ["item": "abc", "text": ""]]) == nil)
        #expect(EditorMessage(body: ["type": "quickLookEmbed", "embed": ["item": "", "text": "![[a.png]]"]]) == nil)
        #expect(EditorMessage(body: ["type": "quickLookEmbed", "embed": "![[a.png]]"]) == nil)
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

    @Test func attachedImagesAreInsertedIntoTheItem() async throws {
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

    @Test func imagesAttachedAfterTheItemChangesAreNamedAndNotInsertedIntoTheNextOne() async throws {
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
        #expect(try await markdown(editor) == nil, "the item now on the page takes nothing")
        #expect(editor.pageItemID == second.id)
        #expect(library.notices.waiting.last?.title == "Images Weren’t Added to the Item")
        #expect(library.notices.waiting.last?.message == "“Photo” was attached to “Plan” but isn’t in its text, because the item was no longer open for editing.")
    }

    @Test func filesQuickAddAttachedGoAtTheEndOfTheNewItemOnceThePageShowsIt() async throws {
        let shown = FakeItemLibrary.note("Plan", modified: .now)
        let new = FakeItemLibrary.note("Trip", modified: .now)
        let library = FakeItemLibrary(items: [shown, new])
        library.bodies[new.id] = "Pack\n\nBook\n"
        let editor = try await attachingEditor(library)
        var saved: [String] = []
        editor.onChange = { id, text, _ in if id == new.id { saved.append(text) } }

        editor.append([Embed(link: "map%201.png", name: "map 1.png"), Embed(link: "tickets.pdf", name: "tickets.pdf")], to: new.id)
        _ = try await editor.webView.evaluateJavaScript("1")
        #expect(try await markdown(editor) == nil, "the item on the page is another one")

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

    @Test func filesQuickAddAttachedWaitWhileTheItemIsEditedAsSource() async throws {
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

    @Test func filesQuickAddAttachedToAnItemEndingInAnOpenCodeFenceAreTold() async throws {
        let new = FakeItemLibrary.note("Trip", modified: .now)
        let library = FakeItemLibrary(items: [new])
        library.bodies[new.id] = "```\ncode"
        let editor = try await attachingEditor(library)

        editor.append([Embed(link: "tickets.pdf", name: "tickets.pdf")], to: new.id)
        // The page also reports the refusal itself (Inkkit's `preservation`), so wait for the notice about the file.
        #expect(await eventually { library.notices.waiting.contains { $0.message.contains("“tickets.pdf”") } })
        let told = try #require(library.notices.waiting.first { $0.message.contains("“tickets.pdf”") })
        #expect(told.message.contains("“Trip”"))
        #expect(try await markdown(editor) == nil, "the item keeps its text exactly")
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

    @Test func filesAttachedThatTheFirstAttemptTouchedHiddenTextAreKeptAndGoOnTheNext() async throws {
        let new = FakeItemLibrary.note("Trip", modified: .now)
        let library = FakeItemLibrary(items: [new])
        library.bodies[new.id] = "# Pack\n\nbag\n"
        let editor = try await attachingEditor(library)
        // The page refuses the first attempt as Inkkit does for an edit that reaches folded text, and does its work the second time.
        _ = try await editor.webView.evaluateJavaScript(
            """
            (() => {
              const real = window.editor.appendImages
              let refused = 0
              window.editor.appendImages = (...arguments_) => refused++ < 1
                ? { commandError: 'hidden-text', message: 'The section was folded.' }
                : real(...arguments_)
              window.__refusals = () => refused
            })()
            """)

        editor.append([Embed(link: "tickets.pdf", name: "tickets.pdf")], to: new.id)
        #expect(try await eventuallyAsking { try await markdown(editor)?.contains("![tickets.pdf](tickets.pdf)") == true })
        #expect(try await editor.webView.evaluateJavaScript("window.__refusals()") as? Int == 2, "it was refused once and sent again")
        #expect(await eventually { editor.pendingEmbeds.isEmpty })
        #expect(library.notices.waiting.isEmpty, "nothing is told as lost")
    }

    @Test func aRefusalForHiddenTextIsAskedAgain() {
        #expect(EditorController.retriesAfterPaint("hidden-text"))
        #expect(!EditorController.retriesAfterPaint("preservation"))
    }

    /// Makes the page refuse `function` as Inkkit does for folded text: `times` refusals, or every one when nil.
    func refuse(_ function: String, times: Int?, in editor: EditorController) async throws {
        _ = try await editor.webView.evaluateJavaScript(
            """
            (() => {
              const real = window.editor.\(function)
              let refused = 0
              window.editor.\(function) = (...arguments_) => refused++ < \(times ?? 1_000_000)
                ? { commandError: 'hidden-text', message: 'The section was folded.' }
                : real(...arguments_)
              window.__refusals = () => refused
            })()
            """)
    }

    @Test func filesAttachedThatStayInFoldedTextAreGivenUpOnAfterALimitAndNamed() async throws {
        let new = FakeItemLibrary.note("Trip", modified: .now)
        let library = FakeItemLibrary(items: [new])
        library.bodies[new.id] = "# Pack\n\nbag\n"
        let editor = try await attachingEditor(library)
        try await refuse("appendImages", times: nil, in: editor)

        editor.append([Embed(link: "tickets.pdf", name: "tickets.pdf")], to: new.id)
        #expect(await eventually { editor.pendingEmbeds.isEmpty })
        #expect(try await markdown(editor) == nil, "nothing reached the text")
        let asked = try #require(try await editor.webView.evaluateJavaScript("window.__refusals()") as? Int)
        #expect(asked == EditorController.hiddenTextRetryLimit + 1, "it asked a limited number of times")
        // Nothing to wait for: gives a further retry time to be made, if one is going to.
        try await Task.sleep(for: EditorController.hiddenTextRetryDelay * 3)
        #expect(try await editor.webView.evaluateJavaScript("window.__refusals()") as? Int == asked, "and then stopped")
        let told = try #require(library.notices.waiting.last)
        #expect(told.title == "File Not in the Text")
        #expect(told.message.contains("“tickets.pdf”") && told.message.contains("“Trip”"))
    }

    @Test func imagesDroppedIntoFoldedTextArePlacedOnTheNextAttempt() async throws {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Plan", modified: .now)])
        library.attaching = { AttachReport(embeds: [Embed(link: "Attachments/Photo.png", name: "Photo")]) }
        let editor = try await attachingEditor(library)
        try await refuse("insertImages", times: 1, in: editor)
        #expect(editor.insertImages(Self.pasted))
        #expect(try await eventuallyAsking { try await markdown(editor)?.contains("![Photo](Attachments/Photo.png)") == true })
        #expect(try await editor.webView.evaluateJavaScript("window.__refusals()") as? Int == 2, "refused once and sent again")
        #expect(library.notices.waiting.isEmpty, "nothing is told as lost")
    }

    @Test func imagesThatCannotBePlacedInFoldedTextAreNamed() async throws {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Plan", modified: .now)])
        library.attaching = { AttachReport(embeds: [Embed(link: "Attachments/Photo.png", name: "Photo")]) }
        let editor = try await attachingEditor(library)
        try await refuse("insertImages", times: nil, in: editor)
        #expect(editor.insertImages(Self.pasted))
        #expect(await eventually { library.notices.waiting.last != nil })
        #expect(try await markdown(editor) == nil, "nothing reached the text")
        #expect(try await editor.webView.evaluateJavaScript("window.__refusals()") as? Int == EditorController.hiddenTextRetryLimit + 1)
        #expect(library.notices.waiting.last?.title == "Images Weren’t Added to the Item")
        #expect(library.notices.waiting.last?.message == "“Photo” was attached to “Plan” but isn’t in its text. It was meant for a folded section or text not yet shown.")
    }

    @Test func imagesThePageDeclinesAreNamedToo() async throws {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Plan", modified: .now)])
        library.attaching = { AttachReport(embeds: [Embed(link: "Attachments/Photo.png", name: "Photo")]) }
        let editor = try await attachingEditor(library)
        _ = try await editor.webView.evaluateJavaScript("window.editor.insertImages = () => false; 1")
        #expect(editor.insertImages(Self.pasted))
        #expect(await eventually { library.notices.waiting.last != nil })
        #expect(library.notices.waiting.last?.message.contains("“Photo” was attached to “Plan” but isn’t in its text.") == true)
    }

    @Test func textTypedIntoFoldedTextThatInkkitDroppedIsTold() async throws {
        guard case .hiddenText = try #require(EditorMessage(body: ["type": "hiddenText"])) else {
            Issue.record("Not the refusal message")
            return
        }
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Plan", modified: .now)])
        let editor = try await attachingEditor(library)
        // What Inkkit's `events.error` reaches the app as, since a real fold refusal needs a person's keystrokes.
        _ = try await editor.webView.evaluateJavaScript("window.webkit.messageHandlers.host.postMessage({ type: 'hiddenText' }); 1")
        #expect(await eventually { library.notices.waiting.last != nil })
        let told = try #require(library.notices.waiting.last)
        #expect(told.title == "Text Wasn’t Added")
        #expect(told.message == "What you typed reached a folded section, which is now open. It wasn’t added, so type it again.")
        // Typing on into the open section tells once, not for every key.
        _ = try await editor.webView.evaluateJavaScript("window.webkit.messageHandlers.host.postMessage({ type: 'hiddenText' }); 1")
        _ = try await editor.webView.evaluateJavaScript("1")
        #expect(await eventually { library.notices.told == 2 })
        #expect(library.notices.waiting.count == 1)
    }
}
