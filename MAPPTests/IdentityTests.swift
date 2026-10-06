import Foundation
import os
import Testing
@testable import MAPP

/// Items keep their identifiers across launches and renames, renames made while the app was closed among them.
@MainActor
struct IdentityTests {
    let root: TemporaryFolder
    let bin: TemporaryFolder
    let files = FileManager.default

    init() throws {
        root = try TemporaryFolder()
        bin = try TemporaryFolder()
        try root.write("# Plan\n\nFirst draft\n", to: "Work/Plan.md")
        try root.write("Deep\n", to: "Work/Project/Deep.md")
        try root.write("Shopping\n", to: "Shopping.md")
        try root.write("PDF", to: "Work/Report.pdf")
    }

    /// The library as the app opens it at launch.
    private func open(now: @escaping @Sendable () -> Date = { .now }) async -> NoteLibrary {
        let library = NoteLibrary(loadingFrom: FolderStore(root: root.url, bin: bin.url, now: now), defaults: nil)
        library.missingGrace = 0.05
        await library.load()
        return library
    }

    private func id(at path: String, in library: NoteLibrary) throws -> UUID {
        try #require(library.notes.first { $0.path == path && !$0.isDeleted }?.id ?? library.files.first { $0.path == path }?.id)
    }

    private func move(_ from: String, _ to: String) throws {
        let target = root.url.appending(path: to)
        try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.moveItem(at: root.url.appending(path: from), to: target)
    }

    private func ledger() throws -> IdentityLedger {
        try JSONDecoder().decode(IdentityLedger.self, from: Data(contentsOf: bin.url.appending(path: "Identities.json")))
    }

    @Test func identifiersAreTheSameAtTheNextLaunch() async throws {
        let first = await open()
        let notes = Dictionary(uniqueKeysWithValues: first.notes.map { ($0.path!, $0.id) })
        let folders = first.folders.map(\.id)
        let report = try id(at: "Work/Report.pdf", in: first)
        first.finish()
        let second = await open()
        #expect(Dictionary(uniqueKeysWithValues: second.notes.map { ($0.path!, $0.id) }) == notes)
        #expect(second.folders.map(\.id) == folders)
        #expect(try id(at: "Work/Report.pdf", in: second) == report)
        #expect(Set(notes.values).count == 3)
    }

    @Test func renamesAndMovesMadeWhileClosedKeepTheIdentifiers() async throws {
        let first = await open()
        let plan = try id(at: "Work/Plan.md", in: first)
        let shopping = try id(at: "Shopping.md", in: first)
        let report = try id(at: "Work/Report.pdf", in: first)
        first.finish()
        try move("Work/Plan.md", "Work/Plan B.md")
        try move("Shopping.md", "Home/Groceries.md")
        try move("Work/Report.pdf", "Report.pdf")
        let second = await open()
        #expect(try id(at: "Work/Plan B.md", in: second) == plan)
        #expect(try id(at: "Home/Groceries.md", in: second) == shopping)
        #expect(try id(at: "Report.pdf", in: second) == report)
        #expect(second.note(shopping)?.folderID == second.folders.first { $0.name == "Home" }?.id)
    }

    @Test func aFolderRenamedWhileClosedKeepsItsIdentifierAndEverythingInIt() async throws {
        let first = await open()
        let work = try #require(first.folders.first { $0.name == "Work" }?.id)
        let plan = try id(at: "Work/Plan.md", in: first)
        let deep = try id(at: "Work/Project/Deep.md", in: first)
        first.finish()
        try move("Work", "Office")
        let second = await open()
        #expect(second.folders.map(\.name) == ["Office"])
        #expect(second.folders.first?.id == work)
        #expect(try id(at: "Office/Plan.md", in: second) == plan)
        #expect(try id(at: "Office/Project/Deep.md", in: second) == deep)
        #expect(second.note(deep)?.folderID == work)
    }

    @Test func changesMadeInTheAppKeepTheIdentifiersAcrossLaunches() async throws {
        let first = await open()
        let plan = try id(at: "Work/Plan.md", in: first)
        let shopping = try id(at: "Shopping.md", in: first)
        let work = try #require(first.folders.first { $0.name == "Work" }?.id)
        first.renameNote(plan, to: "Plan B")
        first.move([shopping], to: work)
        first.rename(work, to: "Office")
        let made = try #require(first.createItem(typeID: "core.note", title: "Ideas", body: "Ideas\n", in: .allNotes))
        let folder = first.newFolder()
        first.updateBody(of: plan, to: "# Plan\n\nSecond draft\n")
        first.finish()
        let second = await open()
        #expect(try id(at: "Office/Plan B.md", in: second) == plan)
        #expect(try id(at: "Office/Shopping.md", in: second) == shopping)
        #expect(try id(at: "Notes/Ideas.md", in: second) == made.id)
        #expect(second.folder(work)?.name == "Office")
        #expect(second.folder(folder.id)?.name == folder.name)
        #expect(second.folder(try #require(made.folderID))?.name == "Notes")
    }

    @Test func aSafeSaveKeepsTheIdentifier() async throws {
        let first = await open()
        let shopping = try id(at: "Shopping.md", in: first)
        first.updateBody(of: shopping, to: "Shopping\n\nMilk\n")
        first.finish()
        // Another editor saving the way most do: a new file written beside and moved over the old one.
        try Data("Shopping\n\nEggs\n".utf8).write(to: root.url.appending(path: "Shopping.md"), options: .atomic)
        let second = await open()
        #expect(try id(at: "Shopping.md", in: second) == shopping)
        second.finish()
        try move("Shopping.md", "Groceries.md")
        let third = await open()
        #expect(try id(at: "Groceries.md", in: third) == shopping, "the file's new identity was kept, so the rename is followed")
    }

    @Test func aTrashedNoteKeepsItsIdentifierInTheBinAndBack() async throws {
        let first = await open()
        let plan = try id(at: "Work/Plan.md", in: first)
        first.delete([plan])
        first.finish()
        let second = await open()
        #expect(second.note(plan)?.isDeleted == true)
        second.recover([plan])
        second.finish()
        let third = await open()
        #expect(try id(at: "Work/Plan.md", in: third) == plan)
        #expect(third.notes.count == 3)
    }

    /// See `IdentityLedgerTests.aFileDeletedAndMadeAgainAtItsPathKeepsTheIdentifier`.
    @Test func aFileDeletedAndMadeAgainAtItsPathKeepsTheIdentifier() async throws {
        let first = await open()
        let shopping = try id(at: "Shopping.md", in: first)
        first.finish()
        try files.removeItem(at: root.url.appending(path: "Shopping.md"))
        try root.write("Something else\n", to: "Shopping.md")
        let second = await open()
        #expect(try id(at: "Shopping.md", in: second) == shopping)
    }

    @Test func aCopyIsANewItem() async throws {
        let first = await open()
        let plan = try id(at: "Work/Plan.md", in: first)
        let report = try id(at: "Work/Report.pdf", in: first)
        first.finish()
        try files.copyItem(at: root.url.appending(path: "Work/Plan.md"), to: root.url.appending(path: "Work/Plan copy.md"))
        try files.copyItem(at: root.url.appending(path: "Work/Report.pdf"), to: root.url.appending(path: "Report.pdf"))
        let second = await open()
        #expect(try id(at: "Work/Plan.md", in: second) == plan)
        #expect(try id(at: "Work/Report.pdf", in: second) == report)
        let copies = [try id(at: "Work/Plan copy.md", in: second), try id(at: "Report.pdf", in: second)]
        #expect(!copies.contains(plan) && !copies.contains(report))
        #expect(Set(copies).count == 2)
    }

    @Test func filesWithTheSameTextAreDifferentItems() async throws {
        try root.write("Same\n", to: "One.md")
        try root.write("Same\n", to: "Two.md")
        let first = await open()
        let one = try id(at: "One.md", in: first)
        let two = try id(at: "Two.md", in: first)
        #expect(one != two)
        first.finish()
        try move("One.md", "Three.md")
        let second = await open()
        #expect(try id(at: "Three.md", in: second) == one)
        #expect(try id(at: "Two.md", in: second) == two)
    }

    @Test func anImportedFileKeepsTheIdentifierItWasReportedWith() async throws {
        let source = try TemporaryFolder()
        try source.write("PNG", to: "Picture.png")
        let first = await open()
        let request = UUID()
        first.importFiles([source.url.appending(path: "Picture.png")], requestID: request)
        first.store?.drain()
        for _ in 0..<100 where first.completedImports[request] == nil { try await Task.sleep(for: .milliseconds(10)) }
        await first.reread()
        let imported = try #require(first.completedImports[request])
        #expect(try id(at: "Picture.png", in: first) == imported)
        first.finish()
        let second = await open()
        #expect(try id(at: "Picture.png", in: second) == imported)
    }

    @Test(arguments: [Data("not a ledger".utf8), nil])
    func aLedgerLostOrUnreadableIsMadeAgainWithoutComplaint(_ replacement: Data?) async throws {
        let first = await open()
        let plan = try id(at: "Work/Plan.md", in: first)
        first.finish()
        let file = bin.url.appending(path: "Identities.json")
        if let replacement { try replacement.write(to: file) } else { try files.removeItem(at: file) }
        let second = await open()
        #expect(second.failure == nil)
        #expect(second.notes.count == 3)
        #expect(Set(second.notes.map(\.id)).count == 3)
        #expect(try id(at: "Work/Plan.md", in: second) != plan, "the identifiers are made again, once")
        let rebuilt = try id(at: "Work/Plan.md", in: second)
        second.finish()
        #expect(try ledger().entries.count == 5)
        let third = await open()
        #expect(try id(at: "Work/Plan.md", in: third) == rebuilt)
    }

    @Test func whatIsGoneIsForgottenInTime() async throws {
        let clock = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_000_000))
        let now: @Sendable () -> Date = { clock.withLock { $0 } }
        let first = await open(now: now)
        first.finish()
        let before = try ledger().entries.count
        try files.removeItem(at: root.url.appending(path: "Shopping.md"))
        let second = await open(now: now)
        second.finish()
        #expect(try ledger().entries.count == before, "a file away for a moment is still remembered")
        clock.withLock { $0 += IdentityLedger.retention }
        let third = await open(now: now)
        third.finish()
        #expect(try ledger().entries.count == before - 1)
        #expect(try ledger().entries.allSatisfy { $0.path != "Shopping.md" })
    }

    @Test func purgedNotesLeaveTheLedger() async throws {
        let first = await open()
        let plan = try id(at: "Work/Plan.md", in: first)
        let before = try ledger().entries.count
        first.delete([plan])
        first.deletePermanently([plan])
        first.finish()
        #expect(try ledger().entries.count == before - 1)
    }

    @Test func aLargeFolderKeepsEveryIdentifier() async throws {
        for folder in 0..<20 {
            for note in 0..<150 { try root.write("Note \(note)\n", to: "Folder \(folder)/Note \(note).md") }
        }
        let first = await open()
        let ids = Dictionary(uniqueKeysWithValues: first.notes.map { ($0.path!, $0.id) })
        #expect(ids.count == 3003)
        #expect(Set(ids.values).count == ids.count)
        first.finish()
        try move("Folder 3", "Renamed")
        let second = await open()
        for note in second.notes {
            let path = note.path!.hasPrefix("Renamed/") ? "Folder 3/" + note.path!.dropFirst("Renamed/".count) : note.path!
            #expect(ids[path] == note.id)
        }
        #expect(try ledger().entries.count == 3003 + 1 + 21)
    }
}
