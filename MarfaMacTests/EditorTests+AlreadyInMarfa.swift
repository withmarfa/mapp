import Foundation
import Synchronization
import Testing
@testable import MarfaMac

/// Add Attachment, a drop or a paste of files on an item's page, asking first about files already in Marfa.
extension EditorTests {
    /// A library holding the item on the page first, then an item whose bytes match every file named `shot.png`.
    func attachingLibrary() -> (FakeItemLibrary, found: Item) {
        let found = FakeItemLibrary.note("Beach Day", modified: .now)
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Plan", modified: .now), found])
        library.sameBytes = AlreadyInMarfaTests.answering(["shot.png": [found]])
        library.attaching = { AttachReport(embeds: [Embed(link: "Attachments/other.png", name: "other")]) }
        return (library, found)
    }

    @Test func attachingAFileAlreadyInMarfaAsksAndCancelAttachesNothing() async throws {
        let disk = TestFiles()
        let (library, _) = attachingLibrary()
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        #expect(editor.insertImages([.file(disk.url("shot.png")), .file(disk.url("other.png"))]))
        try #require(await eventually { editor.alreadyInMarfa.question != nil })
        #expect(editor.alreadyInMarfa.question?.title == "1 of 2 Files Already in Marfa")
        editor.alreadyInMarfa.answer(.cancel)
        // Time for an attach made after Cancel to reach the library, which nothing signals when none is made.
        try await Task.sleep(for: .milliseconds(300))
        #expect(library.attachedBatches.isEmpty)
        #expect(try await markdown(editor) == nil)
    }

    @Test func skipDuplicatesAttachesOnlyTheUnmatchedImageAndShowOpensTheMatch() async throws {
        let disk = TestFiles()
        let (library, found) = attachingLibrary()
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        let details = DetailsPresentation()
        editor.titleDrafts = details
        var opened: [ItemID] = []
        editor.onShowMatches = { opened = $0 }
        #expect(editor.insertImages([.file(disk.url("shot.png")), .file(disk.url("other.png"))]))
        try #require(await eventually { editor.alreadyInMarfa.question != nil })
        editor.alreadyInMarfa.answer(.skipDuplicates)
        try #require(await eventually { library.attachedBatches.map(\.names) == [["other.png"]] })
        #expect(opened.isEmpty, "Show has not run")
        try #require(await eventually { details.toasts.current?.message == "1 file is already in Marfa." })
        details.toasts.showMatches()
        #expect(opened == [found.id])
        #expect(library.attachedBatches.map(\.names) == [["other.png"]], "Show changes nothing that was attached")
        #expect(try await eventuallyAsking { try await markdown(editor)?.contains("Attachments/other.png") == true })
    }

    @Test func attachingWithAddAnywayAttachesEveryFile() async throws {
        let disk = TestFiles()
        let (library, _) = attachingLibrary()
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        #expect(editor.insertImages([.file(disk.url("shot.png")), .file(disk.url("other.png"))] + Self.pasted))
        try #require(await eventually { editor.alreadyInMarfa.question != nil })
        editor.alreadyInMarfa.answer(.addAnyway)
        try #require(await eventually { !library.attachedBatches.isEmpty })
        #expect(library.attachedBatches.map(\.names) == [["shot.png", "other.png", "Photo.png"]])
    }

    @Test func pastedBytesAndUnmatchedFilesAreAttachedUnasked() async throws {
        let disk = TestFiles()
        let (library, _) = attachingLibrary()
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        #expect(editor.insertImages([.file(disk.url("other.png"))] + Self.pasted))
        try #require(await eventually { !library.attachedBatches.isEmpty })
        #expect(library.attachedBatches.map(\.names) == [["other.png", "Photo.png"]])
        #expect(library.askedSameBytes.map { $0.map(\.lastPathComponent) } == [["other.png", "Photo.png"]])
        let staged = library.askedSameBytes.flatMap { $0 }.filter { $0.lastPathComponent == "Photo.png" }
        #expect(await eventually { staged.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } })
        #expect(editor.alreadyInMarfa.question == nil)
    }

    @Test func pastingTheSameImageTwiceAsksAndCancelRemovesTheStagedFile() async throws {
        let (library, found) = attachingLibrary()
        library.sameBytes = AlreadyInMarfaTests.answering(["Photo.png": [found]])
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        #expect(editor.insertImages(Self.pasted))
        try #require(await eventually { editor.alreadyInMarfa.question != nil })
        let staged = try #require(library.askedSameBytes.last)
        #expect(staged.map(\.lastPathComponent) == ["Photo.png"])
        editor.alreadyInMarfa.answer(.cancel)
        try #require(await eventually { staged.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } })
        try await Task.sleep(for: .milliseconds(300))
        #expect(library.attachedBatches.isEmpty)

        #expect(editor.insertImages(Self.pasted))
        try #require(await eventually { editor.alreadyInMarfa.question != nil })
        let stagedAgain = try #require(library.askedSameBytes.last)
        editor.alreadyInMarfa.answer(.cancel)
        try #require(await eventually { stagedAgain.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } })
        #expect(library.attachedBatches.isEmpty)
    }

    @Test func pastingAnImageAlreadyInMarfaSkipsItRemovesTheStagedFileAndShowOpensIt() async throws {
        let (library, found) = attachingLibrary()
        library.sameBytes = AlreadyInMarfaTests.answering(["Photo.png": [found]])
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        let details = DetailsPresentation()
        editor.titleDrafts = details
        var opened: [ItemID] = []
        editor.onShowMatches = { opened = $0 }
        #expect(editor.insertImages(Self.pasted))
        try #require(await eventually { editor.alreadyInMarfa.question != nil })
        let staged = try #require(library.askedSameBytes.last)
        editor.alreadyInMarfa.answer(.skipDuplicates)
        try #require(await eventually { staged.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } })
        try await Task.sleep(for: .milliseconds(300))
        #expect(library.attachedBatches.isEmpty)
        #expect(details.toasts.current?.message == "1 file is already in Marfa.")
        details.toasts.showMatches()
        #expect(opened == [found.id])
        #expect(library.attachedBatches.isEmpty)
    }

    @Test func skipDuplicatesAddsNoneOfTheMatchedImagesAndShowNamesEveryMatch() async throws {
        let plan = FakeItemLibrary.note("Plan", modified: .now)
        let beach = FakeItemLibrary.note("Beach", modified: .now)
        let trip = FakeItemLibrary.note("Trip", modified: .now)
        let missing = ItemID.mint()
        let library = FakeItemLibrary(items: [plan, beach, trip])
        library.sameBytes = { _ in
            FileMatches([
                .answered([FileMatch(id: beach.id, title: "Beach"), FileMatch(id: trip.id, title: "Trip")], more: false),
                .answered([FileMatch(id: missing, title: "Gone")], more: false),
            ])
        }
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        let details = DetailsPresentation()
        editor.titleDrafts = details
        var opened: [ItemID] = []
        editor.onShowMatches = { opened = $0 }
        let disk = TestFiles()
        #expect(editor.insertImages([.file(disk.url("shot.png")), .file(disk.url("gone.png"))]))
        try #require(await eventually { editor.alreadyInMarfa.question != nil })
        editor.alreadyInMarfa.answer(.skipDuplicates)
        try await Task.sleep(for: .milliseconds(300))
        #expect(library.attachedBatches.isEmpty, "a matched file is skipped even when its item is not held")
        #expect(details.toasts.current?.message == "2 files are already in Marfa.")
        details.toasts.showMatches()
        #expect(opened == [beach.id, trip.id, missing])
        #expect(library.attachedBatches.isEmpty)
    }

    @Test func showFromThePageNamesEveryMatchAndAttachesNothing() async throws {
        let plan = FakeItemLibrary.note("Plan", modified: .now)
        let beach = FakeItemLibrary.note("Beach", modified: .now)
        let trip = FakeItemLibrary.note("Trip", modified: .now)
        let library = FakeItemLibrary(items: [plan, beach, trip])
        library.sameBytes = AlreadyInMarfaTests.answering(["shot.png": [beach, trip]])
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        let details = DetailsPresentation()
        editor.titleDrafts = details
        var opened: [ItemID] = []
        editor.onShowMatches = { opened = $0 }
        let disk = TestFiles()
        #expect(editor.insertImages([.file(disk.url("shot.png"))]))
        try #require(await eventually { editor.alreadyInMarfa.question != nil })
        editor.alreadyInMarfa.answer(.skipDuplicates)
        try #require(await eventually { details.toasts.current != nil })
        details.toasts.showMatches()
        #expect(opened == [beach.id, trip.id])
        #expect(library.attachedBatches.isEmpty)
    }

    @Test func aPasteWhosePageChangesDuringTheLookupIsStillAttached() async throws {
        let first = FakeItemLibrary.note("Plan", modified: .now)
        let second = FakeItemLibrary.note("Other", modified: .now)
        let library = FakeItemLibrary(items: [first, second])
        let gate = Parked()
        defer { gate.open() }
        library.sameBytes = { _ in
            await gate.wait()
            return .noAnswer
        }
        var existedAtAttach = false
        library.attaching = {
            let staged = library.askedSameBytes.flatMap { $0 }
            existedAtAttach = !staged.isEmpty && staged.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
            return AttachReport(embeds: [Embed(link: "Attachments/Photo.png", name: "Photo")])
        }
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        #expect(editor.insertImages(Self.pasted))
        try #require(await eventually { gate.isParked })
        editor.load(second)
        try #require(await eventually { editor.pageItemID == second.id })
        gate.open()
        try #require(await eventually { library.attachedBatches.contains { $0.item == first.id } })
        #expect(existedAtAttach, "the staged copy is still there when the image is attached")
        let staged = library.askedSameBytes.flatMap { $0 }
        #expect(await eventually { staged.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } })
        #expect(library.attachedBatches.map(\.names) == [["Photo.png"]])
        #expect(library.notices.waiting.contains { $0.message.contains("was attached to “Plan”") })
        #expect(!library.notices.waiting.contains { $0.message.contains("nothing was attached") })
        #expect(try await markdown(editor) == nil)
    }

    @Test func aTimedOutPasteKeepsTheStagedFileUntilTheCancelledLookupEnds() async throws {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Plan", modified: .now)])
        let gate = Parked()
        let sawCancel = Mutex(false)
        let atEnd = Mutex<(cancelled: Bool, existed: Bool)?>(nil)
        library.sameBytes = { files in
            await withTaskCancellationHandler {
                await gate.wait()
            } onCancel: {
                sawCancel.withLock { $0 = true }
            }
            atEnd.withLock { $0 = (Task.isCancelled, files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }) }
            return .noAnswer
        }
        library.attaching = { AttachReport(embeds: [Embed(link: "Attachments/Photo.png", name: "Photo")]) }
        let editor = try await attachingEditor(library)
        await AlreadyInMarfa.$limitOverride.withValue(.milliseconds(50)) {
            #expect(editor.insertImages(Self.pasted))
        }
        #expect(await eventually { gate.isParked })
        #expect(await eventually { sawCancel.withLock { $0 } })
        let staged = try #require(library.askedSameBytes.last)
        #expect(staged.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(library.attachedBatches.isEmpty, "nothing is attached until the cancelled lookup has ended")
        gate.open()
        try #require(await eventually { !library.attachedBatches.isEmpty })
        let end = try #require(atEnd.withLock { $0 })
        #expect(end.cancelled && end.existed)
        #expect(await eventually { staged.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } })
    }

    @Test func aFailedPasteKeepsItsCopyWhenAnEarlierFileDisappearsDuringAttachment() async throws {
        let disk = TestFiles()
        let chosen = disk.url("chosen.png", "chosen")
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Plan", modified: .now)])
        library.attaching = {
            try? FileManager.default.removeItem(at: chosen)
            return AttachReport(failed: [AttachmentFailure(index: 1, name: "Photo.png", reason: "Disk full")])
        }
        let editor = try await attachingEditor(library)
        #expect(editor.insertImages([.file(chosen)] + Self.pasted))
        try #require(await eventually { library.notices.waiting.last != nil })
        #expect(library.attachedBatches.map(\.names) == [["chosen.png", "Photo.png"]])
        let copy = try #require(library.askedSameBytes.last?.last?.resolvingSymlinksInPath())
        #expect(FileManager.default.isReadableFile(atPath: copy.path))
        #expect(library.notices.waiting.last?.action == .showInFinder([copy]))
    }

    @Test func aSymbolicLinkIsHashedAndAttachedAsTheFileItNames() async throws {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Plan", modified: .now)])
        library.sameBytes = { _ in .noAnswer }
        library.attaching = { AttachReport(embeds: [Embed(link: "Attachments/photo.png", name: "photo.png")]) }
        let disk = TestFiles()
        let real = disk.url("photo.png", "pixels")
        let link = disk.directory.appending(path: "alias.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let editor = try await attachingEditor(library)
        #expect(editor.insertImages([.file(link)]))
        try #require(await eventually { !library.attachedBatches.isEmpty || library.notices.waiting.last != nil })
        #expect(library.askedSameBytes.map { $0.map(\.lastPathComponent) } == [["photo.png"]])
        #expect(library.attachedBatches.map(\.names) == [["photo.png"]])
        #expect(library.notices.waiting.allSatisfy { !$0.message.contains("can’t be read") })
    }

    @Test func aRecoveredImageSavedToDownloadsIsNotSaidToBeAttached() async throws {
        let plan = FakeItemLibrary.note("Plan", modified: .now)
        let library = FakeItemLibrary(items: [plan])
        let missing = ItemID.mint()
        let disk = TestFiles()
        let image = disk.url("gone.png", "pixels")
        let saved = disk.url("gone.png")
        library.sameBytes = { _ in
            FileMatches([.answered([FileMatch(id: missing, title: "Gone")], more: false)])
        }
        library.attaching = { AttachReport(kept: [KeptFile(name: "gone.png", file: saved)]) }
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        #expect(editor.insertImages([.file(image)]))
        try #require(await eventually { editor.alreadyInMarfa.question != nil })
        editor.alreadyInMarfa.answer(.addAnyway)
        try #require(await eventually { library.notices.waiting.contains { $0.message.contains("saved to Downloads") } })
        #expect(library.notices.waiting.allSatisfy { !$0.message.contains("was attached") })
        #expect(library.attachedBatches.map(\.names) == [["gone.png"]])
    }
}
