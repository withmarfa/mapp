import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// A cached item or connection that a change should have remade is a stale relationship shown to the person, so
/// each change here is followed by the check that matters: what the library says now is what a library made
/// from the same notes, with nothing cached, says.
struct ItemCacheTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let work = Folder(id: .mint(), name: "Work")

    func note(_ path: String, _ text: String, folder: Folder? = nil) -> Note {
        Note(path: path, text: text, created: start, folderID: folder?.id)
    }

    /// The items an uncached library makes of the same notes, versions aside, which are numbers of this session.
    func uncached(_ library: NoteLibrary) -> [Item] {
        NoteLibrary(notes: library.notes, folders: library.folders).allItems.filter { !$0.isFile }.map(unversioned)
    }

    func unversioned(_ item: Item) -> Item {
        var item = item
        item.version = ItemVersion(0)
        return item
    }

    /// Every note's item, its relationships and its mentions, as the views read them.
    func expectCurrent(_ library: NoteLibrary, _ step: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let cached = library.allItems.filter { !$0.isFile }.map(unversioned)
        #expect(cached == uncached(library), "\(step): items", sourceLocation: sourceLocation)
        let fresh = NoteLibrary(notes: library.notes, folders: library.folders)
        for item in library.allItems where !item.isFile {
            #expect(library.item(item.id) == library.allItems.first { $0.id == item.id }, "\(step): item(_:)", sourceLocation: sourceLocation)
            let mine: [String] = library.relationships(for: item.id).map { "\($0.field)=\($0.targets.map { $0.itemID?.rawValue ?? $0.title })" }
            let theirs: [String] = fresh.relationships(for: item.id).map { "\($0.field)=\($0.targets.map { $0.itemID?.rawValue ?? $0.title })" }
            #expect(mine == theirs, "\(step): relationships", sourceLocation: sourceLocation)
            #expect(library.bodyMentions(for: item.id).map(\.itemID) == fresh.bodyMentions(for: item.id).map(\.itemID),
                    "\(step): mentions", sourceLocation: sourceLocation)
        }
        #expect(library.count(in: .allNotes) == fresh.count(in: .allNotes), "\(step): count", sourceLocation: sourceLocation)
        #expect(library.count(in: .recentlyDeleted) == fresh.count(in: .recentlyDeleted), "\(step): trash count", sourceLocation: sourceLocation)
        #expect(library.count(in: .folder(work.id)) == fresh.count(in: .folder(work.id)), "\(step): folder count", sourceLocation: sourceLocation)
    }

    func makeLibrary(extra: [Note] = []) -> (library: NoteLibrary, target: Note, other: Note, source: Note) {
        let target = note("Target.md", "Target\n\nText\n")
        let other = note("Other.md", "Other\n\nText\n")
        let source = note("Source.md", "Source\n\nText\n")
        let library = NoteLibrary(
            notes: [target, other, source] + extra, folders: [work], store: RecordingStore(), now: { start + 60 })
        _ = library.allItems
        _ = library.count(in: .allNotes)
        return (library, target, other, source)
    }

    func undoManager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    // MARK: A link added, changed or removed in the body

    @Test func everyEditToALinkLineIsSeenAndNoOtherEditRemakesTheConnections() throws {
        let (library, target, other, source) = makeLibrary()
        let bodies: [(String, [EdgeTarget])] = [
            ("Source\n\nSee [[Target]].\n", [.item(target.id)]),
            ("Source\n\nSee [[Target]].\n\nMore\n", [.item(target.id)]),
            ("Source\n\nSee [[Other]].\n\nMore\n", [.item(other.id)]),
            ("Source\n\nSee [[other]].\n\nMore\n", [.item(other.id)]),
            ("Source\n\nSee [[Other]] and [[Target]].\n", [.item(other.id), .item(target.id)]),
            ("Source\n\nSee [[Tar\nget]].\n", []),
            ("Source\n\nSee [Target]].\n", []),
            ("Source\n\nSee [[Target]].\n", [.item(target.id)]),
            ("Source\n\n```\n[[Other]]\n```\n", [.item(other.id)]),
            ("Source\n\n```\n[[Missing]]\n```\n", [.unresolved(spelling: "Missing", ambiguous: false)]),
            ("Source\r\n\r\nSee [[Target]].\r\n", [.item(target.id)]),
            ("Source\r\n\r\nSee [[Other]].\r\n", [.item(other.id)]),
            ("Source\r\n\r\nSee [[Other]].", [.item(other.id)]),
            ("Source\r\n\r\nSee [[Other]]", [.item(other.id)]),
            ("Source\n\nText\n", [])
        ]
        for (body, targets) in bodies {
            library.updateBody(of: source.id, to: body)
            #expect(library.item(source.id)?.edgesOut.map(\.target) == targets, "\(body.debugDescription)")
            expectCurrent(library, body.debugDescription)
        }
        // A word typed into the plain text is no reason to resolve every reference again.
        library.updateBody(of: source.id, to: "Source\n\nSee [[Target]].\n")
        _ = library.connectionIndex
        let generation = try #require(library.connections?.generation)
        for typed in ["Source\n\nSee [[Target]].\n\nA", "Source\n\nSee [[Target]].\n\nAB", "Source\n\nSee [[Target]].\n\nAB [x]"] {
            library.updateBody(of: source.id, to: typed)
            expectCurrent(library, typed.debugDescription)
        }
        #expect(library.connections?.generation == generation)
    }

    @Test func aLinkTypedOneCharacterAtATimeIsSeenWhenItIsWhole() {
        let (library, target, _, source) = makeLibrary()
        var typed = "Source\n\n"
        for character in "[[Target]]" {
            typed.append(character)
            library.updateBody(of: source.id, to: typed)
            let expected: [EdgeTarget] = typed.hasSuffix("]]") ? [.item(target.id)] : []
            #expect(library.item(source.id)?.edgesOut.map(\.target) == expected, "\(typed.debugDescription)")
        }
        expectCurrent(library, "typed whole")
        for _ in 0..<2 {
            typed.removeLast()
            library.updateBody(of: source.id, to: typed)
            #expect(library.item(source.id)?.edgesOut.isEmpty == true, "\(typed.debugDescription)")
        }
        expectCurrent(library, "deleted again")
    }

    // MARK: A name changing under a reference

    @Test func aRenameMoveOrTrashAnywhereRemakesWhatReferencesIt() throws {
        let linked = note("Linked.md", "Linked\n\nBy path [[Work/Plan]], by name [[Plan]], by file [[Plan.md]].\n")
        let plan = note("Work/Plan.md", "Plan\n\nText\n", folder: work)
        let (library, _, _, _) = makeLibrary(extra: [linked, plan])
        func edges() -> [EdgeTarget] { library.item(linked.id)?.edgesOut.map(\.target) ?? [] }
        #expect(edges() == [.item(plan.id), .item(plan.id), .item(plan.id)])
        expectCurrent(library, "loaded")

        let manager = undoManager()
        manager.beginUndoGrouping()
        library.move([plan.id], to: nil, undoManager: manager)
        manager.endUndoGrouping()
        expectCurrent(library, "moved to the Inbox")
        #expect(edges().first == .unresolved(spelling: "Work/Plan", ambiguous: false), "the path no longer names it")

        manager.undo()
        expectCurrent(library, "move undone")
        #expect(edges() == [.item(plan.id), .item(plan.id), .item(plan.id)])

        manager.redo()
        expectCurrent(library, "move redone")

        manager.beginUndoGrouping()
        library.delete([plan.id], undoManager: manager)
        manager.endUndoGrouping()
        expectCurrent(library, "deleted")
        #expect(edges().allSatisfy { if case .unresolved = $0 { true } else { false } }, "a deleted note names nothing")
        manager.undo()
        expectCurrent(library, "delete undone")

        manager.beginUndoGrouping()
        library.renameNote(plan.id, to: "Schedule", undoManager: manager)
        manager.endUndoGrouping()
        expectCurrent(library, "renamed")
        manager.undo()
        expectCurrent(library, "rename undone")
        #expect(edges() == [.unresolved(spelling: "Work/Plan", ambiguous: false), .item(plan.id), .item(plan.id)])
        manager.redo()
        expectCurrent(library, "rename redone")

        manager.beginUndoGrouping()
        library.rename(work.id, to: "Office", undoManager: manager)
        manager.endUndoGrouping()
        expectCurrent(library, "folder renamed")
        manager.undo()
        expectCurrent(library, "folder rename undone")
        library.deleteFolder(work.id, undoManager: manager)
        expectCurrent(library, "folder deleted")
    }

    @Test func aTitleChangedInTheFrontMatterResolvesReferencesToTheNewName() throws {
        let titled = note("Doc.md", "---\ntitle: Old name\n---\nText\n")
        let linking = note("Linking.md", "Linking\n\nSee [[New name]] and [[Old name]].\n")
        let (library, _, _, _) = makeLibrary(extra: [titled, linking])
        #expect(library.item(linking.id)?.edgesOut.map(\.target) == [.unresolved(spelling: "New name", ambiguous: false), .item(titled.id)])
        let manager = undoManager()
        manager.beginUndoGrouping()
        #expect(library.setItemProperty(titled.id, key: "title", value: .string("New name"), undoManager: manager))
        manager.endUndoGrouping()
        expectCurrent(library, "title set")
        #expect(library.item(titled.id)?.title == "New name")
        manager.undo()
        expectCurrent(library, "title undone")
        #expect(library.item(titled.id)?.title == "Old name")
    }

    @Test func aTitleAndATwinMakeAReferenceAmbiguousUntilOneGoes() {
        let twin = note("Work/Target.md", "Target\n\nA second note by that name.\n", folder: work)
        let (library, target, _, source) = makeLibrary(extra: [twin])
        library.updateBody(of: source.id, to: "Source\n\nSee [[Target]].\n")
        #expect(library.item(source.id)?.edgesOut.map(\.target) == [.unresolved(spelling: "Target", ambiguous: true)])
        library.delete([twin.id])
        #expect(library.item(source.id)?.edgesOut.map(\.target) == [.item(target.id)])
        library.recover([twin.id])
        #expect(library.item(source.id)?.edgesOut.map(\.target) == [.unresolved(spelling: "Target", ambiguous: true)])
        expectCurrent(library, "recovered")
    }

    // MARK: Notes the app reads again

    @Test func aNoteFollowingItsFirstLineChangesItsTitleWhereItIsListedAndWhereItIsLinked() {
        let (library, target, _, source) = makeLibrary()
        library.updateBody(of: source.id, to: "Source\n\nSee [[Target]] and [[Renamed target]].\n")
        library.updateBody(of: target.id, to: "Renamed target\n\nText\n")
        #expect(library.item(target.id)?.title == "Renamed target")
        #expect(library.item(source.id)?.edgesOut.map(\.target) == [.item(target.id), .item(target.id)])
        expectCurrent(library, "first line retitled")
        library.leave(target.id)
        expectCurrent(library, "left")
    }

    @Test func aTitleThatEqualsTheFirstLineStillFollowsTheLineInTheList() throws {
        let kept = note("Plan.md", "---\ntitle: Plan\n---\nPlan\n\nText\n")
        let (library, _, _, _) = makeLibrary(extra: [kept])
        #expect(library.note(kept.id)?.followsFirstLine == true)
        let generation = try #require(library.connections?.generation)
        library.updateBody(of: kept.id, to: "Plan B\n\nText\n")
        // The list follows the line as it is typed; references resolve against the property until the note is
        // left, so typing the line remakes no connections.
        #expect(library.item(kept.id)?.title == "Plan B")
        #expect(library.connections?.generation == generation)
        expectCurrent(library, "typed")
        library.leave(kept.id)
        expectCurrent(library, "left")
        #expect(library.item(kept.id)?.title == "Plan B")
    }
}

/// What another app does to the folder while the app has it open: the cache must not outlast it.
@MainActor
struct ItemCacheOutsideChangeTests {
    let root: TemporaryFolder
    let bin: TemporaryFolder
    let library: NoteLibrary

    init() async throws {
        root = try TemporaryFolder()
        bin = try TemporaryFolder()
        try root.write("# Target\n\nText\n", to: "Target.md")
        try root.write("# Source\n\nSee [[Target]] and [[Renamed]].\n", to: "Source.md")
        try root.write("# Elsewhere\n\nText\n", to: "Work/Elsewhere.md")
        try root.write(String(repeating: "x", count: 100), to: "Work/Photo.png")
        library = NoteLibrary(loadingFrom: FolderStore(root: root.url, bin: bin.url), defaults: nil)
        library.missingGrace = 0.05
        await library.load()
    }

    private func id(at path: String) throws -> ItemID {
        try #require(library.notes.first { $0.path == path }?.id ?? library.files.first { $0.path == path }?.id)
    }

    private func edges(of path: String) throws -> [EdgeTarget] {
        library.item(try id(at: path))?.edgesOut.map(\.target) ?? []
    }

    @Test func aTitleAddedByHandResolvesAReferenceAtOnce() async throws {
        let source = try id(at: "Source.md")
        let target = try id(at: "Target.md")
        _ = library.allItems
        #expect(try edges(of: "Source.md") == [.item(target), .unresolved(spelling: "Renamed", ambiguous: false)])
        try root.write("---\ntitle: Renamed\n---\n# Target\n\nText\n", to: "Target.md")
        await library.reread()
        #expect(library.item(target)?.title == "Renamed")
        #expect(library.item(source)?.edgesOut.map(\.target) == [.item(target), .item(target)])
    }

    @Test func aNoteRewrittenWithTheSameLengthOfTextIsReadAgain() async throws {
        let source = try id(at: "Source.md")
        _ = library.allItems
        let before = library.item(source)
        try root.write("# Source\n\nSee [[Elsewh]] and [[Renamed]].\n", to: "Source.md")
        await library.reread()
        #expect(library.item(source)?.version != before?.version)
        #expect(library.item(source)?.edgesOut.map(\.target) == [
            .unresolved(spelling: "Elsewh", ambiguous: false), .unresolved(spelling: "Renamed", ambiguous: false)])
        // The same reference, written again, is the same item.
        try root.write("# Source\n\nSee [[Elsewh]] and [[Renamed]].\n", to: "Source.md")
        await library.reread()
        #expect(library.item(source)?.edgesOut.count == 2)
    }

    @Test func aLinkRemovedByHandIsGoneAndOneAddedIsThere() async throws {
        let source = try id(at: "Source.md")
        _ = library.allItems
        try root.write("# Source\n\nNothing here.\n", to: "Source.md")
        await library.reread()
        #expect(try edges(of: "Source.md").isEmpty)
        try root.write("# Source\r\n\r\nSee [[Elsewhere]].\r\n", to: "Source.md")
        await library.reread()
        #expect(library.item(source)?.edgesOut.map(\.target) == [.item(try id(at: "Work/Elsewhere.md"))])
    }

    @Test func aFileGrowingOrChangingKindIsReadAgain() async throws {
        let photo = try id(at: "Work/Photo.png")
        #expect(library.item(photo)?.content == .file(.png, byteCount: 100))
        try root.write(String(repeating: "x", count: 5_000), to: "Work/Photo.png")
        await library.reread()
        #expect(library.item(photo)?.content == .file(.png, byteCount: 5_000))
        try FileManager.default.moveItem(at: root.url.appending(path: "Work/Photo.png"), to: root.url.appending(path: "Work/Photo.pdf"))
        await library.reread()
        let moved = try #require(library.files.first { $0.path == "Work/Photo.pdf" })
        let item = try #require(library.item(moved.id))
        #expect(item.type == WorkbenchSchema.pdfType)
        #expect(item.title == "Photo.pdf")
        #expect(library.allItems.filter(\.isFile).count == 1)
    }

    @Test func aFileThatArrivesIsCountedAndListedAndOneThatGoesIsNot() async throws {
        let count = library.count(in: .files)
        #expect(count == 1)
        try root.write("new", to: "Added.txt")
        await library.reread()
        #expect(library.count(in: .files) == 2)
        #expect(library.items(in: .files).count == 2)
        try FileManager.default.removeItem(at: root.url.appending(path: "Added.txt"))
        try FileManager.default.removeItem(at: root.url.appending(path: "Work/Photo.png"))
        await library.reread()
        await library.reread()
        #expect(library.count(in: .files) == 0)
        #expect(library.items(in: .files).isEmpty)
        #expect(library.items(matching: "Photo").isEmpty)
    }

    @Test func aFolderRenamedOutsideRemakesItsItemsContainerAndPaths() async throws {
        let elsewhere = try id(at: "Work/Elsewhere.md")
        let photo = try id(at: "Work/Photo.png")
        let container = library.item(elsewhere)?.container
        #expect(container != nil)
        try FileManager.default.moveItem(at: root.url.appending(path: "Work"), to: root.url.appending(path: "Office"))
        await library.reread()
        #expect(library.item(elsewhere)?.container == container)
        #expect(library.path(of: elsewhere) == "Office/Elsewhere.md")
        #expect(library.path(of: photo) == "Office/Photo.png")
        let photoItem = try #require(library.item(photo))
        let office = try #require(library.folder(of: photoItem))
        #expect(office.name == "Office")
        #expect(library.count(in: .folder(office.id)) == 2)
    }
}
