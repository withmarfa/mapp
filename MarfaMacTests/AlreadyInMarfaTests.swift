import Foundation
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

/// Files about to be added that Marfa already holds: one question for a batch, and every add going ahead as before
/// where Marfa gives no answer.
@Suite(.hangLimit)
struct AlreadyInMarfaTests {
    let disk = TestFiles()

    /// Answers each file by its name: the items `matches` gives it, or no match for any other name.
    static func answering(_ matches: [String: [Item]], more: Set<String> = []) -> ([URL]) async -> FileMatches {
        { files in
            FileMatches(files.map { file in
                let name = file.lastPathComponent
                let found = (matches[name] ?? []).map { FileMatch(id: $0.id, title: $0.displayTitle) }
                return FileMatchAnswer.answered(found, more: more.contains(name))
            })
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
        #expect(question.title == "“shot.png” is already in Marfa.")
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
        #expect(question.title == "7 files are already in Marfa.")
        let lines = question.message.split(separator: "\n")
        #expect(lines.count == 6)
        #expect(lines.last == "And 2 more files.")
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

    @Test func skipDuplicatesAddsOnlyTheFilesWithNoMatch() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["a.png": [beach]])
        let browser = browser(for: library)
        let toasts = ToastPresenter()
        let adding = Task {
            await browser.importFiles([disk.url("a.png"), disk.url("b.png")], in: library, order: ItemOrder(), undoManager: nil, toasts: toasts)
        }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        browser.alreadyInMarfa.answer(.skipDuplicates)
        let ids = await adding.value
        #expect(ids.count == 1)
        #expect(library.addedFiles.map(\.name) == ["b.png"], "the matched file is skipped, the other added")
        #expect(toasts.current?.message == "Added 1 of 2 Files 1 is already in Marfa.")
        #expect(browser.selection == Set(ids), "Show has not opened the match")
        toasts.showMatches()
        #expect(browser.selection == [beach.id])
        #expect(library.addedFiles.map(\.name) == ["b.png"], "Show changes nothing that was added")
    }

    @Test func skipDuplicatesWithEveryFileMatchedAddsNothingAndShowOpensTheItem() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["a.png": [beach]])
        let browser = browser(for: library)
        let toasts = ToastPresenter()
        let adding = Task { await browser.importFiles([disk.url("a.png")], in: library, order: ItemOrder(), undoManager: nil, toasts: toasts) }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        browser.alreadyInMarfa.answer(.skipDuplicates)
        #expect(await adding.value.isEmpty)
        #expect(library.addedFiles.isEmpty)
        #expect(toasts.current?.message == "1 file is already in Marfa.")
        #expect(toasts.current?.undo == nil)
        #expect(browser.selection.isEmpty)
        toasts.showMatches()
        #expect(browser.selection == [beach.id])
        #expect(library.addedFiles.isEmpty)
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
            FileMatches(files.map { file in
                switch file.lastPathComponent {
                case "match.png": .answered([FileMatch(id: beach.id, title: "Beach Day")], more: false)
                case "none.png": .answered([], more: false)
                default: .noAnswer
                }
            })
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
        browser.alreadyInMarfa.answer(.skipDuplicates)
        #expect(await adding.value.count == 2)
        #expect(library.addedFiles.map(\.name) == ["none.png", "unanswered.png"], "a file with no answer is added, never skipped")
    }

    @Test func showOpensAMatchTheLibraryDoesNotHold() async throws {
        let id = ItemID.mint()
        let library = FakeItemLibrary()
        library.sameBytes = { _ in FileMatches([.answered([FileMatch(id: id, title: "Shared Photo")], more: false)]) }
        let browser = browser(for: library)
        let toasts = ToastPresenter()
        let adding = Task { await browser.importFiles([disk.url("a.png")], in: library, order: ItemOrder(), undoManager: nil, toasts: toasts) }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        #expect(browser.alreadyInMarfa.question?.message == "It has the same contents as “Shared Photo”.")
        browser.alreadyInMarfa.answer(.skipDuplicates)
        #expect(await adding.value.isEmpty)
        #expect(library.addedFiles.isEmpty)
        #expect(library.item(id) == nil)
        toasts.showMatches()
        #expect(browser.selection == [id], "Show opens the item by its id")
        #expect(library.addedFiles.isEmpty)
        #expect(library.item(id) == nil)
    }

    @Test func showSelectsEveryMatchIncludingOneThePlaceDoesNotList() async throws {
        let libraryNote = FakeItemLibrary.note("Library", modified: .now)
        let feedNote = FakeItemLibrary.note("Feed", modified: .now, tier: .feed)
        let library = FakeItemLibrary(items: [libraryNote, feedNote])
        library.sameBytes = Self.answering(["a.png": [libraryNote, feedNote]])
        let browser = browser(for: library)
        let toasts = ToastPresenter()
        let adding = Task { await browser.importFiles([disk.url("a.png")], in: library, order: ItemOrder(), undoManager: nil, toasts: toasts) }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        browser.alreadyInMarfa.answer(.skipDuplicates)
        #expect(await adding.value.isEmpty)
        #expect(browser.selection.isEmpty)
        toasts.showMatches()
        #expect(browser.selection == [libraryNote.id, feedNote.id])
        #expect(library.addedFiles.isEmpty)
    }

    @Test func showInANewWindowOpensEveryMatch() async throws {
        let libraryNote = FakeItemLibrary.note("Library", modified: .now)
        let feedNote = FakeItemLibrary.note("Feed", modified: .now, tier: .feed)
        let library = FakeItemLibrary(items: [libraryNote, feedNote])
        library.sameBytes = Self.answering(["a.png": [libraryNote, feedNote]])
        let browser = browser(for: library)
        browser.setOpening(.newWindow)
        var opened: Set<ItemID> = []
        browser.windowOpener = { opened = $0 }
        let toasts = ToastPresenter()
        let adding = Task { await browser.importFiles([disk.url("a.png")], in: library, order: ItemOrder(), undoManager: nil, toasts: toasts) }
        try #require(await eventually { browser.alreadyInMarfa.question != nil })
        browser.alreadyInMarfa.answer(.skipDuplicates)
        #expect(await adding.value.isEmpty)
        #expect(opened.isEmpty)
        toasts.showMatches()
        #expect(opened == [libraryNote.id, feedNote.id])
        #expect(library.addedFiles.isEmpty)
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

    @Test func aCheckPastItsLimitAddsEveryFileOnceTheLookupEnds() async {
        let library = FakeItemLibrary()
        let gate = Parked()
        let sawCancel = Mutex(false)
        let finishedCancelled = Mutex(false)
        library.sameBytes = { _ in
            await withTaskCancellationHandler {
                await gate.wait()
            } onCancel: {
                sawCancel.withLock { $0 = true }
            }
            finishedCancelled.withLock { $0 = Task.isCancelled }
            return .noAnswer
        }
        let asking = AlreadyInMarfa.Asking()
        asking.viewAppeared()
        let checking = await AlreadyInMarfa.$limitOverride.withValue(.milliseconds(50)) {
            Task { await AlreadyInMarfa.check([disk.url("a.png")], in: library, asking: asking) }
        }
        #expect(await eventually { gate.isParked })
        #expect(await eventually { sawCancel.withLock { $0 } })
        #expect(!finishedCancelled.withLock { $0 }, "the cancelled lookup is still inside the read")
        #expect(asking.question == nil)
        gate.open()
        #expect(await checking.value == .addingAll(count: 1))
        #expect(finishedCancelled.withLock { $0 })
        #expect(asking.question == nil)
    }

    @Test func theWholeCheckIsGivenTenSeconds() {
        #expect(AlreadyInMarfa.limit == .seconds(10))
    }

    @Test func aTimedOutDeviceImportHoldsTheStagedCopyUntilTheCancelledLookupEnds() async throws {
        let library = FakeItemLibrary()
        let browser = browser(for: library)
        let gate = Parked()
        let sawCancel = Mutex(false)
        let atEnd = Mutex<(cancelled: Bool, readable: Bool, stops: Int)?>(nil)
        let stops = Mutex(0)
        let watched = Mutex<String?>(nil)
        let watch = AlreadyInMarfa.grantWatch.add(.init(
            start: { _ in },
            stop: { url in
                guard watched.withLock({ $0 }) == url.resolvingSymlinksInPath().path else { return }
                stops.withLock { $0 += 1 }
            }
        ))
        defer { AlreadyInMarfa.grantWatch.remove(watch) }
        library.sameBytes = { files in
            await withTaskCancellationHandler {
                await gate.wait()
            } onCancel: {
                sawCancel.withLock { $0 = true }
            }
            let readable = files.allSatisfy { FileManager.default.isReadableFile(atPath: $0.path) }
            atEnd.withLock { $0 = (Task.isCancelled, readable, stops.withLock { $0 }) }
            return .noAnswer
        }
        let provider = try photoProvider(named: "IMG", bytes: "one")
        await AlreadyInMarfa.$limitOverride.withValue(.milliseconds(50)) {
            browser.importProviders([provider], in: library, order: ItemOrder(), undoManager: nil, toasts: nil)
        }
        #expect(await eventually { gate.isParked })
        #expect(await eventually { sawCancel.withLock { $0 } })
        let staged = try #require(library.askedSameBytes.last?.first)
        watched.withLock { $0 = staged.resolvingSymlinksInPath().path }
        #expect(FileManager.default.fileExists(atPath: staged.path), "the staged copy is held while the cancelled lookup runs")
        #expect(stops.withLock { $0 } == 0)
        #expect(library.addedFiles.isEmpty)
        gate.open()
        #expect(await eventually { library.addedFiles.map(\.name) == ["IMG.png"] })
        let end = try #require(atEnd.withLock { $0 })
        #expect(end.cancelled && end.readable && end.stops == 0)
        #expect(await eventually { stops.withLock { $0 } == 1 && !FileManager.default.fileExists(atPath: staged.path) })
    }

    @Test func aTimedOutDropOfASymlinkHoldsAccessUntilTheCancelledLookupEnds() async throws {
        let library = FakeItemLibrary()
        let browser = browser(for: library)
        let real = disk.url("photo.png", "pixels")
        let link = disk.directory.appending(path: "alias.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let gate = Parked()
        let sawCancel = Mutex(false)
        let atEnd = Mutex<(cancelled: Bool, name: String, readable: Bool, stops: Int)?>(nil)
        let stops = Mutex(0)
        let watch = AlreadyInMarfa.grantWatch.add(.init(
            start: { _ in },
            stop: { if $0.lastPathComponent == "alias.png" { stops.withLock { $0 += 1 } } }
        ))
        defer { AlreadyInMarfa.grantWatch.remove(watch) }
        library.sameBytes = { files in
            await withTaskCancellationHandler {
                await gate.wait()
            } onCancel: {
                sawCancel.withLock { $0 = true }
            }
            let name = files.map(\.lastPathComponent).joined(separator: ",")
            let readable = files.allSatisfy { FileManager.default.isReadableFile(atPath: $0.path) }
            atEnd.withLock { $0 = (Task.isCancelled, name, readable, stops.withLock { $0 }) }
            return .noAnswer
        }
        let adding = await AlreadyInMarfa.$limitOverride.withValue(.milliseconds(50)) {
            Task { await browser.importFiles([link], in: library, order: ItemOrder(), undoManager: nil) }
        }
        #expect(await eventually { gate.isParked })
        try FileManager.default.removeItem(at: link)
        #expect(await eventually { sawCancel.withLock { $0 } })
        #expect(FileManager.default.isReadableFile(atPath: real.path))
        #expect(stops.withLock { $0 } == 0)
        #expect(library.addedFiles.isEmpty)
        gate.open()
        #expect(await adding.value.count == 1)
        let end = try #require(atEnd.withLock { $0 })
        #expect(end.cancelled && end.name == "photo.png" && end.readable && end.stops == 0)
        #expect(stops.withLock { $0 } == 1)
        #expect(library.addedFiles.map(\.name) == ["photo.png"])
    }

    /// A photo handed over as a nearby device does, copied into the import's own folder.
    private func photoProvider(named name: String, bytes: String) throws -> NSItemProvider {
        let source = disk.url("\(name)-\(bytes).png", bytes)
        let provider = NSItemProvider()
        provider.suggestedName = name
        provider.registerFileRepresentation(for: .png, visibility: .all) { completion in
            completion(source, false, nil)
            return nil
        }
        return provider
    }

    @Test func twoCopiesOfOnePathAreNotBothTakenAsTheSameAnswer() async throws {
        let beach = FakeItemLibrary.note("Beach", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        let file = disk.url("twice.png")
        library.sameBytes = { _ in
            FileMatches([
                .answered([FileMatch(id: beach.id, title: "Beach")], more: false),
                .noAnswer,
            ])
        }
        let asking = AlreadyInMarfa.Asking()
        asking.viewAppeared()
        let checking = Task { await AlreadyInMarfa.check([file, file], in: library, asking: asking) }
        try #require(await eventually { asking.question != nil })
        #expect(asking.question?.rows.count == 1, "only the copy Marfa could read is a match")
        asking.answer(.skipDuplicates)
        let plan = await checking.value
        #expect(plan.adding == [1])
        #expect(plan.show == [beach.id])
        #expect(!plan.isCancelled)
    }

    @Test func aNewDraftBegunWhileFilesAreCheckedIsLeftAlone() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["map.png": [beach]])
        let browser = browser(for: library)
        browser.openNewItem(kind: "core.note", form: .text, in: library)
        browser.quickAdd.draft?.title = "Trip"
        browser.quickAdd.draft?.files = [try disk.file("map.png")]
        let saving = Task { await browser.saveQuickAdd(in: library, undoManager: nil) }
        try #require(await eventually { browser.quickAdd.alreadyInMarfa.question != nil })
        let replacement = try disk.file("map.png")
        // Clearing keeps a typed draft for the next New, which would be this same one. Dropping it is a new draft.
        if let held = browser.quickAdd.entry { browser.quickAdd.drafts.drop(held) }
        browser.quickAdd.clearDraft()
        browser.openNewItem(kind: "core.note", form: .text, in: library)
        browser.quickAdd.draft?.title = "Next"
        browser.quickAdd.draft?.files = [replacement]
        browser.quickAdd.alreadyInMarfa.answer(.skipDuplicates)
        #expect(await saving.value == nil)
        #expect(browser.quickAdd.draft?.title == "Next")
        #expect(browser.quickAdd.draft?.files.map(\.token) == [replacement.token])
        #expect(library.items.allSatisfy { $0.title != "Trip" && $0.title != "Next" })
        #expect(library.notices.waiting.contains { $0.message.contains("while its files were being checked") })
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
        #expect(await first.value == .addingAll(count: 1))
        try #require(await eventually { asking.question.map { $0 != firstQuestion } == true }, "the second is shown once the first is answered")
        #expect(asking.question?.rows.map(\.file.lastPathComponent) == ["b.png"])
        asking.viewDisappeared()
        #expect(await second.value == .addingAll(count: 1), "with no view left, it goes ahead unasked")
        #expect(asking.question == nil)
    }

    @Test func withNoViewToAskInEveryFileIsAddedUnasked() async {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["a.png": [beach]])
        let files = [disk.url("a.png")]
        let asking = AlreadyInMarfa.Asking()
        #expect(await AlreadyInMarfa.check(files, in: library, asking: asking) == .addingAll(count: files.count))
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
        #expect(await second.value == .addingAll(count: 1))
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

    @Test func quickAddSkipLeavesAnEditedFileSelectionIntactAndUnsent() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["photo.png": [beach]])
        let browser = browser(for: library)
        let toasts = ToastPresenter()
        browser.openNewItem(kind: TypeID.file.rawValue, form: .text, in: library)
        let original = try disk.file("photo.png")
        browser.quickAdd.draft?.files = [original]
        let saving = Task { await browser.saveQuickAdd(in: library, undoManager: nil, toasts: toasts) }
        try #require(await eventually { browser.quickAdd.alreadyInMarfa.question != nil })
        let replacement = try disk.file("photo.png")
        browser.quickAdd.draft?.files.append(replacement)
        browser.quickAdd.alreadyInMarfa.answer(.skipDuplicates)
        #expect(await saving.value == nil)
        #expect(browser.quickAdd.draft?.files.map(\.token) == [original.token, replacement.token])
        #expect(library.addedFiles.isEmpty)
        #expect(library.notices.waiting.last?.title == "Item Not Added")
    }

    @Test(arguments: [["photo.png"], ["photo.png", "invoice.pdf"]])
    func quickAddKeepsTheChangedSelectionAfterANoMatch(_ names: [String]) async throws {
        let library = FakeItemLibrary()
        let gate = Parked()
        defer { gate.open() }
        library.sameBytes = { _ in
            await gate.wait()
            return FileMatches([.answered([], more: false)])
        }
        let browser = browser(for: library)
        browser.openNewItem(kind: TypeID.file.rawValue, form: .text, in: library)
        browser.quickAdd.draft?.files = [try disk.file("photo.png")]
        let saving = Task { await browser.saveQuickAdd(in: library, undoManager: nil) }
        try #require(await eventually { gate.isParked })
        let replacements = try names.map { try disk.file($0) }
        browser.quickAdd.draft?.files = replacements
        gate.open()
        #expect(await saving.value == nil)
        #expect(library.addedFiles.isEmpty)
        #expect(browser.quickAdd.draft?.files.map(\.token) == replacements.map(\.token))
    }

    @Test func quickAddSkipOfItsOnlyFileAddsNothing() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["photo.png": [beach]])
        let browser = browser(for: library)
        let toasts = ToastPresenter()
        browser.openNewItem(kind: TypeID.file.rawValue, form: .text, in: library)
        browser.quickAdd.draft?.files = [try disk.file("photo.png")]
        let saving = Task { await browser.saveQuickAdd(in: library, undoManager: nil, toasts: toasts) }
        try #require(await eventually { browser.quickAdd.alreadyInMarfa.question != nil })
        browser.quickAdd.alreadyInMarfa.answer(.skipDuplicates)
        #expect(await saving.value == nil)
        #expect(library.addedFiles.isEmpty)
        #expect(browser.quickAdd.draft?.files.isEmpty == true)
        #expect(toasts.current?.message == "1 file is already in Marfa.")
        toasts.showMatches()
        #expect(browser.selection == [beach.id])
        #expect(library.addedFiles.isEmpty)
    }

    @Test func quickAddSkipSendsTheRestAndShowFromAPanelHandsTheMatchesOn() async throws {
        let beach = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [beach])
        library.sameBytes = Self.answering(["map.png": [beach]])
        let panel = Browser()
        panel.quickAdd.alreadyInMarfa.viewAppeared()
        var opened: [ItemID] = []
        panel.showsMatchesElsewhere = { opened = $0 }
        panel.openNewItem(kind: "core.note", form: .text, in: library)
        panel.quickAdd.draft?.title = "Trip"
        let kept = try disk.file("tickets.pdf")
        panel.quickAdd.draft?.files = [try disk.file("map.png"), kept]
        let toasts = ToastPresenter()
        let saving = Task { await panel.saveQuickAdd(in: library, undoManager: nil, toasts: toasts) }
        try #require(await eventually { panel.quickAdd.alreadyInMarfa.question != nil })
        panel.quickAdd.alreadyInMarfa.answer(.skipDuplicates)
        let id = try #require(await saving.value)
        try #require(await eventually { library.attachedFiles.map(\.name) == ["tickets.pdf"] })
        #expect(toasts.current?.message == "1 file is already in Marfa.")
        #expect(opened.isEmpty)
        toasts.showMatches()
        #expect(opened == [beach.id])
        #expect(panel.selection == [id])
        #expect(library.attachedFiles.map(\.name) == ["tickets.pdf"])
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
