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

    @Test func attachingWithOpenAttachesTheRestThenOpensTheMatchedItem() async throws {
        let disk = TestFiles()
        let (library, found) = attachingLibrary()
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        var opened: [ItemID] = []
        editor.onOpenFound = { opened = $0 }
        #expect(editor.insertImages([.file(disk.url("shot.png")), .file(disk.url("other.png"))]))
        try #require(await eventually { editor.alreadyInMarfa.question != nil })
        editor.alreadyInMarfa.answer(.open)
        try #require(await eventually { !opened.isEmpty })
        #expect(library.attachedBatches.map(\.names) == [["other.png"]])
        #expect(opened == [found.id])
        #expect(try await markdown(editor)?.contains("Attachments/other.png") == true, "the rest were placed before the item opened")
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

    @Test func pastingAnImageAlreadyInMarfaOpensItAndRemovesTheStagedFile() async throws {
        let (library, found) = attachingLibrary()
        library.sameBytes = AlreadyInMarfaTests.answering(["Photo.png": [found]])
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        var opened: [ItemID] = []
        editor.onOpenFound = { opened = $0 }
        #expect(editor.insertImages(Self.pasted))
        try #require(await eventually { editor.alreadyInMarfa.question != nil })
        let staged = try #require(library.askedSameBytes.last)
        editor.alreadyInMarfa.answer(.open)
        try #require(await eventually { opened == [found.id] })
        try #require(await eventually { staged.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } })
        try await Task.sleep(for: .milliseconds(300))
        #expect(library.attachedBatches.isEmpty)
    }

    @Test func openFromThePageOpensEveryMatchAndAttachesOneThatCannotBeReached() async throws {
        let plan = FakeItemLibrary.note("Plan", modified: .now)
        let beach = FakeItemLibrary.note("Beach", modified: .now)
        let trip = FakeItemLibrary.note("Trip", modified: .now)
        let missing = ItemID.mint()
        let library = FakeItemLibrary(items: [plan, beach, trip])
        library.sameBytes = { files in
            FileMatches([
                .answered([FileMatch(id: beach.id, title: "Beach"), FileMatch(id: trip.id, title: "Trip")], more: false),
                .answered([FileMatch(id: missing, title: "Gone")], more: false),
            ])
        }
        library.attaching = { AttachReport(embeds: [Embed(link: "Attachments/gone.png", name: "gone.png")]) }
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        var opened: [ItemID] = []
        editor.onOpenFound = { opened = $0 }
        let disk = TestFiles()
        #expect(editor.insertImages([.file(disk.url("shot.png")), .file(disk.url("gone.png"))]))
        try #require(await eventually { editor.alreadyInMarfa.question != nil })
        editor.alreadyInMarfa.answer(.open)
        try #require(await eventually { opened == [beach.id, trip.id] })
        try #require(await eventually { library.attachedBatches.map(\.names) == [["gone.png"]] })
        #expect(library.notices.waiting.contains { $0.title == "Couldn’t Open Item" && $0.message.contains("gone.png") })
    }

    @Test func anItemWindowFollowsEveryMatchWhenNothingElseOpensThem() async throws {
        let plan = FakeItemLibrary.note("Plan", modified: .now)
        let beach = FakeItemLibrary.note("Beach", modified: .now)
        let trip = FakeItemLibrary.note("Trip", modified: .now)
        let library = FakeItemLibrary(items: [plan, beach, trip])
        library.sameBytes = AlreadyInMarfaTests.answering(["shot.png": [beach, trip]])
        let editor = try await attachingEditor(library)
        editor.alreadyInMarfa.viewAppeared()
        var followed: [ItemID] = []
        editor.onOpenItem = { followed.append($0) }
        let disk = TestFiles()
        #expect(editor.insertImages([.file(disk.url("shot.png"))]))
        try #require(await eventually { editor.alreadyInMarfa.question != nil })
        editor.alreadyInMarfa.answer(.open)
        try #require(await eventually { followed == [beach.id, trip.id] })
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

    @Test func aTimedOutPasteKeepsTheStagedFileUntilTheLookupFinishes() async throws {
        defer { AlreadyInMarfa.limitOverride.set(nil) }
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("Plan", modified: .now)])
        let gate = Parked()
        defer { gate.open() }
        let cancelled = Mutex(false)
        let existedAtEnd = Mutex(false)
        library.sameBytes = { files in
            await gate.wait()
            cancelled.withLock { $0 = Task.isCancelled }
            existedAtEnd.withLock { $0 = files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) } }
            return .noAnswer
        }
        library.attaching = { AttachReport(embeds: [Embed(link: "Attachments/Photo.png", name: "Photo")]) }
        AlreadyInMarfa.limitOverride.set(.milliseconds(50))
        let editor = try await attachingEditor(library)
        #expect(editor.insertImages(Self.pasted))
        try #require(await eventually { !library.attachedBatches.isEmpty })
        #expect(gate.isParked, "the image is attached without waiting out the cancelled lookup")
        let staged = library.askedSameBytes.flatMap { $0 }
        #expect(staged.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        gate.open()
        #expect(await eventually { cancelled.withLock { $0 } })
        #expect(existedAtEnd.withLock { $0 }, "the staged copy is still there when the lookup finishes")
        #expect(await eventually { staged.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } })
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
        editor.alreadyInMarfa.answer(.open)
        try #require(await eventually { library.notices.waiting.contains { $0.message.contains("saved to Downloads") } })
        #expect(library.notices.waiting.allSatisfy { !$0.message.contains("was attached") })
        #expect(library.attachedBatches.map(\.names) == [["gone.png"]])
    }
}
