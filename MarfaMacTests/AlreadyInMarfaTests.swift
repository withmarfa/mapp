import Foundation
import Testing
@testable import MarfaMac

/// Files about to be added that Marfa already holds: one question for a batch, and every add going ahead as before
/// where Marfa gives no answer.
@Suite(.hangLimit)
struct AlreadyInMarfaTests {
    let disk = TestFiles()

    /// Answers each file by its name: the items `matches` gives it, or no match for any other name.
    static func answering(_ matches: [String: [Item]], more: Set<String> = []) -> ([URL]) async -> FileMatches {
        { files in
            FileMatches(Dictionary(uniqueKeysWithValues: files.map { file in
                let name = file.lastPathComponent
                let found = (matches[name] ?? []).map { FileMatch(id: $0.id, title: $0.displayTitle) }
                return (file, FileMatchAnswer.answered(found, more: more.contains(name)))
            }))
        }
    }

    func browser(for library: FakeItemLibrary) -> Browser {
        let browser = Browser()
        browser.adopt(library)
        browser.alreadyInMarfa.viewAppeared()
        browser.quickAdd.alreadyInMarfa.viewAppeared()
        return browser
    }

    // MARK: Drops and imports

    @Test func filesWithNoMatchAreAddedWithNoQuestion() async {
        let library = FakeItemLibrary()
        library.sameBytes = Self.answering([:])
        let browser = browser(for: library)
        let ids = await browser.importFiles([disk.url("a.txt"), disk.url("b.txt")], in: library, order: ItemOrder(), undoManager: nil)
        #expect(ids.count == 2)
        #expect(library.askedSameBytes.map { $0.map(\.lastPathComponent) } == [["a.txt", "b.txt"]], "the batch is checked once")
        #expect(browser.alreadyInMarfa.question == nil)
        #expect(library.addedFiles.map(\.name) == ["a.txt", "b.txt"])
    }

    @Test func oneFileAlreadyInMarfaAsksAndAddsNothingWhileItWaits() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["shot.png": [beach]])
        let browser = browser(for: library)
        let adding = Task { await browser.importFiles([disk.url("shot.png")], in: library, order: ItemOrder(), undoManager: nil) }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        let question = try #require(browser.alreadyInMarfa.question)
        #expect(question.title == "“shot.png” Is Already in Marfa")
        #expect(question.message == "It has the same contents as “Beach Day”.")
        #expect(library.addedFiles.isEmpty, "nothing is added before the person answers")
        browser.alreadyInMarfa.answer(.addAnyway, to: question.id)
        #expect(await adding.value.count == 1)
        #expect(library.addedFiles.map(\.name) == ["shot.png"])
    }

    @Test func severalFilesAlreadyInMarfaAreOneQuestion() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let trip = FakeItemLibrary.note("Trip", modified: .now)
        let receipt = FakeItemLibrary.note("Receipt", modified: .now)
        let library = FakeItemLibrary(items: [beach, trip, receipt])
        library.sameBytes = Self.answering(["a.png": [beach], "b.png": [trip, receipt], "c.png": [receipt]], more: ["c.png"])
        let browser = browser(for: library)
        let adding = Task {
            await browser.importFiles(
                [disk.url("a.png"), disk.url("b.png"), disk.url("c.png"), disk.url("d.png")], in: library, order: ItemOrder(), undoManager: nil)
        }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        let question = try #require(browser.alreadyInMarfa.question)
        #expect(question.title == "3 of 4 Files Already in Marfa")
        #expect(question.message == """
            “a.png” has the same contents as “Beach Day”.
            “b.png” has the same contents as “Trip” and 1 other item.
            “c.png” has the same contents as “Receipt” and other items.
            Open shows all of them.
            """)
        browser.alreadyInMarfa.answer(.cancel, to: question.id)
        #expect(await adding.value.isEmpty)
        #expect(browser.alreadyInMarfa.question == nil, "one question was asked, and it is gone")
    }

    @Test func aLongBatchNamesFiveFilesThenCountsTheRest() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        let names = (1...7).map { "\($0).png" }
        library.sameBytes = Self.answering(Dictionary(uniqueKeysWithValues: names.map { ($0, [beach]) }))
        let browser = browser(for: library)
        let adding = Task { await browser.importFiles(names.map { disk.url($0) }, in: library, order: ItemOrder(), undoManager: nil) }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        let question = try #require(browser.alreadyInMarfa.question)
        #expect(question.title == "7 Files Are Already in Marfa")
        let lines = question.message.split(separator: "\n")
        #expect(lines.count == 7)
        #expect(lines.dropLast().last == "And 2 more files.")
        #expect(lines.last == "Open shows all of them.")
        browser.alreadyInMarfa.answer(.cancel, to: question.id)
        _ = await adding.value
    }

    @Test func addAnywayAddsEveryFileAsOneUndoStepAndOneToast() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["a.png": [beach]])
        let browser = browser(for: library)
        let toasts = ToastPresenter()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let adding = Task {
            await browser.importFiles([disk.url("a.png"), disk.url("b.png")], in: library, order: ItemOrder(), undoManager: undo, toasts: toasts)
        }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        browser.alreadyInMarfa.answer(.addAnyway)
        let ids = await adding.value
        #expect(ids.count == 2)
        #expect(library.addedFiles.map(\.name) == ["a.png", "b.png"])
        #expect(toasts.current?.message == "Added 2 Files")
        #expect(browser.selection == Set(ids))
        undo.undo()
        #expect(ids.allSatisfy { library.item($0)?.state == .trashed }, "one Undo takes back the whole drop")
        #expect(!undo.canUndo)
    }

    @Test func openAddsTheFilesWithNoMatchAndOpensTheMatchedItems() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["a.png": [beach]])
        let browser = browser(for: library)
        let toasts = ToastPresenter()
        let adding = Task {
            await browser.importFiles([disk.url("a.png"), disk.url("b.png")], in: library, order: ItemOrder(), undoManager: nil, toasts: toasts)
        }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        browser.alreadyInMarfa.answer(.open)
        let ids = await adding.value
        #expect(ids.count == 1)
        #expect(library.addedFiles.map(\.name) == ["b.png"], "the matched file is skipped, the other added")
        #expect(toasts.current?.message == "Added 1 File")
        #expect(browser.selection == [beach.id], "the item already in Marfa is opened")
    }

    @Test func openWithEveryFileMatchedAddsNothingAndOpensTheItem() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["a.png": [beach]])
        let browser = browser(for: library)
        let toasts = ToastPresenter()
        let adding = Task { await browser.importFiles([disk.url("a.png")], in: library, order: ItemOrder(), undoManager: nil, toasts: toasts) }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        browser.alreadyInMarfa.answer(.open)
        #expect(await adding.value.isEmpty)
        #expect(library.addedFiles.isEmpty)
        #expect(toasts.current == nil)
        #expect(browser.selection == [beach.id])
    }

    @Test func cancelWritesNothing() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let collection = FakeItemLibrary.collection("Reading")
        let library = FakeItemLibrary(items: [beach, collection])
        library.sameBytes = Self.answering(["a.png": [beach]])
        let browser = browser(for: library)
        browser.show(.collection(collection.id), in: library, order: ItemOrder())
        let toasts = ToastPresenter()
        let undo = UndoManager()
        let adding = Task {
            await browser.importFiles([disk.url("a.png"), disk.url("b.png")], in: library, order: ItemOrder(), undoManager: undo, toasts: toasts)
        }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        browser.alreadyInMarfa.answer(.cancel)
        #expect(await adding.value.isEmpty)
        #expect(library.addedFiles.isEmpty)
        #expect(toasts.current == nil)
        #expect(!undo.canUndo)
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func noAnswerAddsEveryFileAsToday() async {
        let library = FakeItemLibrary()
        library.sameBytes = { _ in .noAnswer }
        let browser = browser(for: library)
        let ids = await browser.importFiles([disk.url("a.png"), disk.url("b.png")], in: library, order: ItemOrder(), undoManager: nil)
        #expect(ids.count == 2)
        #expect(browser.alreadyInMarfa.question == nil)
    }

    @Test func aMixOfAnswersAsksOnlyAboutTheMatches() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = { files in
            FileMatches(Dictionary(uniqueKeysWithValues: files.compactMap { file -> (URL, FileMatchAnswer)? in
                switch file.lastPathComponent {
                case "match.png": (file, .answered([FileMatch(id: beach.id, title: "Beach Day")], more: false))
                case "none.png": (file, .answered([], more: false))
                default: nil
                }
            }))
        }
        let browser = browser(for: library)
        let adding = Task {
            await browser.importFiles(
                [disk.url("match.png"), disk.url("none.png"), disk.url("unanswered.png")], in: library, order: ItemOrder(), undoManager: nil)
        }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        let question = try #require(browser.alreadyInMarfa.question)
        #expect(question.rows.map(\.file.lastPathComponent) == ["match.png"])
        #expect(question.title == "1 of 3 Files Already in Marfa")
        browser.alreadyInMarfa.answer(.open)
        #expect(await adding.value.count == 2)
        #expect(library.addedFiles.map(\.name) == ["none.png", "unanswered.png"], "a file with no answer is added, never skipped")
    }

    @Test func aMatchTheLibraryDoesNotHoldIsNamedAsMarfaNamedIt() async throws {
        let library = FakeItemLibrary()
        library.sameBytes = { files in FileMatches([files[0]: .answered([FileMatch(id: .mint(), title: "Shared Photo")], more: false)]) }
        let browser = browser(for: library)
        let toasts = ToastPresenter()
        let adding = Task { await browser.importFiles([disk.url("a.png")], in: library, order: ItemOrder(), undoManager: nil, toasts: toasts) }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        #expect(browser.alreadyInMarfa.question?.message == "It has the same contents as “Shared Photo”.")
        browser.alreadyInMarfa.answer(.open)
        let added = await adding.value
        #expect(added.count == 1)
        #expect(library.addedFiles.map(\.name) == ["a.png"])
        #expect(toasts.current?.message == "1 file was added because the item already in Marfa couldn’t be opened.")
        #expect(browser.selection == Set(added), "the added file is selected, as any other drop is")
    }

    @Test func openFetchesAMatchTheLibraryDoesNotHoldYet() async throws {
        let id = ItemID.mint()
        let arriving = FakeItemLibrary.note("Shared Photo", modified: .now, id: id)
        let library = FakeItemLibrary()
        library.arrivals[id] = arriving
        library.sameBytes = { files in FileMatches([files[0]: .answered([FileMatch(id: id, title: "Shared Photo")], more: false)]) }
        let browser = browser(for: library)
        let adding = Task { await browser.importFiles([disk.url("a.png")], in: library, order: ItemOrder(), undoManager: nil) }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        browser.alreadyInMarfa.answer(.open)
        #expect(await adding.value.isEmpty)
        #expect(library.addedFiles.isEmpty)
        #expect(library.heldForOpening == [id])
        #expect(browser.selection == [id])
    }

    @Test func openSelectsEveryMatchIncludingOneThePlaceDoesNotList() async throws {
        let libraryNote = FakeItemLibrary.note("Library", modified: .now)
        let feedNote = FakeItemLibrary.note("Feed", modified: .now, tier: .feed)
        let library = FakeItemLibrary(items: [libraryNote, feedNote])
        library.sameBytes = Self.answering(["a.png": [libraryNote, feedNote]])
        let browser = browser(for: library)
        let adding = Task { await browser.importFiles([disk.url("a.png")], in: library, order: ItemOrder(), undoManager: nil) }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        browser.alreadyInMarfa.answer(.open)
        #expect(await adding.value.isEmpty)
        #expect(browser.selection == [libraryNote.id, feedNote.id])
    }

    @Test func openInANewWindowOpensEveryMatch() async throws {
        let libraryNote = FakeItemLibrary.note("Library", modified: .now)
        let feedNote = FakeItemLibrary.note("Feed", modified: .now, tier: .feed)
        let library = FakeItemLibrary(items: [libraryNote, feedNote])
        library.sameBytes = Self.answering(["a.png": [libraryNote, feedNote]])
        let browser = browser(for: library)
        browser.setOpening(.newWindow)
        var opened: Set<ItemID> = []
        browser.windowOpener = { opened = $0 }
        let adding = Task { await browser.importFiles([disk.url("a.png")], in: library, order: ItemOrder(), undoManager: nil) }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        browser.alreadyInMarfa.answer(.open)
        #expect(await adding.value.isEmpty)
        #expect(opened == [libraryNote.id, feedNote.id])
    }

    @Test func aFileGoneWhileTheQuestionWaitsIsToldAsAnyUnreadableFile() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["a.png": [beach]])
        let browser = browser(for: library)
        let gone = disk.url("a.png")
        let adding = Task { await browser.importFiles([gone], in: library, order: ItemOrder(), undoManager: nil) }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        try FileManager.default.removeItem(at: gone)
        browser.alreadyInMarfa.answer(.addAnyway)
        #expect(await adding.value.isEmpty)
        #expect(library.notices.waiting.first?.title == "Can’t Add File")
    }

    // MARK: The check itself

    @Test func aCheckPastItsLimitAddsEveryFileUnasked() async {
        let library = FakeItemLibrary()
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let late = Self.answering(["a.png": [beach]])
        let (release, released) = AsyncStream<Void>.makeStream()
        library.sameBytes = { files in
            for await _ in release { break }
            return await late(files)
        }
        let asking = AlreadyInMarfa.Asking()
        asking.viewAppeared()
        let files = [disk.url("a.png")]
        let plan = await AlreadyInMarfa.check(files, in: library, asking: asking, within: .milliseconds(200))
        #expect(plan == .addingAll(files), "the add goes ahead without the answer")
        released.yield()
        released.finish()
        // Time for the late answer to arrive, which must ask nothing.
        try? await Task.sleep(for: .milliseconds(300))
        #expect(asking.question == nil)
    }

    @Test func theWholeCheckIsGivenTenSeconds() {
        #expect(AlreadyInMarfa.limit == .seconds(10))
    }

    @Test func questionsWaitTheirTurnAndAGoneViewLetsThemGoAhead() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["a.png": [beach], "b.png": [beach]])
        let asking = AlreadyInMarfa.Asking()
        asking.viewAppeared()
        let first = Task { await AlreadyInMarfa.check([disk.url("a.png")], in: library, asking: asking) }
        try #require(await eventually { asking.question != nil })
        let firstQuestion = try #require(asking.question)
        let second = Task { await AlreadyInMarfa.check([disk.url("b.png")], in: library, asking: asking) }
        try #require(await eventually { library.askedSameBytes.count == 2 })
        asking.answer(.cancel, to: UUID())
        #expect(asking.question == firstQuestion, "an answer to another question is ignored")
        asking.answer(.addAnyway, to: firstQuestion.id)
        #expect(asking.question == nil, "the next question waits until this alert is gone")
        #expect(await first.value == .addingAll([disk.directory.appending(path: "a.png")]))
        try #require(await eventually { asking.question.map { $0 != firstQuestion } == true }, "the second is shown once the first is answered")
        #expect(asking.question?.rows.map(\.file.lastPathComponent) == ["b.png"])
        asking.viewDisappeared()
        #expect(await second.value == .addingAll([disk.directory.appending(path: "b.png")]), "with no view left, it goes ahead unasked")
        #expect(asking.question == nil)
    }

    @Test func withNoViewToAskInEveryFileIsAddedUnasked() async {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["a.png": [beach]])
        let files = [disk.url("a.png")]
        let asking = AlreadyInMarfa.Asking()
        #expect(await AlreadyInMarfa.check(files, in: library, asking: asking) == .addingAll(files))
        #expect(asking.question == nil)
    }

    @Test func twoBatchesAreEachAnsweredOnceTheAlertIsGone() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["a.png": [beach], "b.png": [beach]])
        let asking = AlreadyInMarfa.Asking()
        asking.viewAppeared()
        let first = Task { await AlreadyInMarfa.check([disk.url("a.png")], in: library, asking: asking) }
        try #require(await eventually { asking.question != nil })
        let firstQuestion = try #require(asking.question)
        let second = Task { await AlreadyInMarfa.check([disk.url("b.png")], in: library, asking: asking) }
        try #require(await eventually { library.askedSameBytes.count == 2 })
        asking.answer(.cancel, to: firstQuestion.id)
        #expect(asking.question == nil)
        #expect((await first.value).isCancelled)
        try #require(await eventually { asking.question?.rows.map(\.file.lastPathComponent) == ["b.png"] })
        asking.answer(.addAnyway, to: asking.question?.id)
        #expect(await second.value == .addingAll([disk.directory.appending(path: "b.png")]))
        #expect(await eventually { asking.question == nil })
    }

    // MARK: Quick Add

    @Test func quickAddsFileAsksAndCancelKeepsTheDraft() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["photo.png": [beach]])
        let browser = browser(for: library)
        browser.openNewItem(kind: TypeID.file.rawValue, form: .text, in: library)
        browser.quickAdd.draft?.files = [try disk.file("photo.png")]
        let typed = browser.quickAdd.draft
        let saving = Task { await browser.saveQuickAdd(in: library, undoManager: nil) }
        try #require(await eventually { browser.quickAdd.alreadyInMarfa.question != nil })
        #expect(browser.quickAdd.isSaving, "the panel is busy while it asks")
        browser.quickAdd.alreadyInMarfa.answer(.cancel)
        #expect(await saving.value == nil)
        #expect(library.addedFiles.isEmpty && library.created.isEmpty)
        #expect(browser.quickAdd.draft == typed, "Cancel leaves the panel as it was")
    }

    @Test func quickAddsFileAddedAnywayIsAdded() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["photo.png": [beach]])
        let browser = browser(for: library)
        browser.openNewItem(kind: TypeID.file.rawValue, form: .text, in: library)
        browser.quickAdd.draft?.files = [try disk.file("photo.png")]
        let saving = Task { await browser.saveQuickAdd(in: library, undoManager: nil) }
        try #require(await eventually { browser.quickAdd.alreadyInMarfa.question != nil })
        browser.quickAdd.alreadyInMarfa.answer(.addAnyway)
        #expect(await saving.value != nil)
        #expect(library.addedFiles.map(\.name) == ["photo.png"])
    }

    @Test func quickAddsOpenTakesTheMatchedFilesOutAndOpensTheItem() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["map.png": [beach]])
        let browser = browser(for: library)
        browser.openNewItem(kind: "core.note", form: .text, in: library)
        browser.quickAdd.draft?.title = "Trip"
        let kept = try disk.file("tickets.pdf")
        browser.quickAdd.draft?.files = [try disk.file("map.png"), kept]
        let saving = Task { await browser.saveQuickAdd(in: library, undoManager: nil) }
        try #require(await eventually { browser.quickAdd.alreadyInMarfa.question != nil })
        browser.quickAdd.alreadyInMarfa.answer(.open)
        #expect(await saving.value == nil)
        #expect(library.created.isEmpty && library.attachedFiles.isEmpty, "nothing is added until the person adds again")
        #expect(browser.quickAdd.draft?.title == "Trip")
        #expect(browser.quickAdd.draft?.files == [kept])
        #expect(browser.selection == [beach.id])
    }

    @Test func quickAddsOpenFromAPanelHandsTheMatchesToTheAppWindow() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["map.png": [beach]])
        let panel = Browser()
        panel.quickAdd.alreadyInMarfa.viewAppeared()
        var opened: [ItemID] = []
        panel.opensFoundElsewhere = { ids in
            opened = ids
            return []
        }
        panel.openNewItem(kind: "core.note", form: .text, in: library)
        panel.quickAdd.draft?.title = "Trip"
        let kept = try disk.file("tickets.pdf")
        panel.quickAdd.draft?.files = [try disk.file("map.png"), kept]
        let saving = Task { await panel.saveQuickAdd(in: library, undoManager: nil) }
        try #require(await eventually { panel.quickAdd.alreadyInMarfa.question != nil })
        panel.quickAdd.alreadyInMarfa.answer(.open)
        #expect(await saving.value == nil)
        #expect(opened == [beach.id])
        #expect(panel.quickAdd.draft?.files == [kept])
        #expect(panel.selection.isEmpty)
        #expect(library.created.isEmpty)
    }

    @Test func quickAddsAttachmentsWithNoMatchAreAttachedUnasked() async throws {
        let library = FakeItemLibrary()
        library.sameBytes = Self.answering([:])
        let browser = browser(for: library)
        browser.openNewItem(kind: "core.note", form: .text, in: library)
        browser.quickAdd.draft?.title = "Trip"
        browser.quickAdd.draft?.files = [try disk.file("map.png")]
        let id = try #require(await browser.saveQuickAdd(in: library, undoManager: nil))
        try #require(await eventually { library.attachedFiles.count == 1 })
        #expect(library.attachedFiles.map(\.item) == [id])
        #expect(browser.quickAdd.alreadyInMarfa.question == nil)
    }
}
