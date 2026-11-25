import CoreTransferable
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

@Suite(.hangLimit)
struct FileDropTests {
    let disk = TestFiles()

    @Test func droppedFilesBecomeItemsAndAreSelected() async throws {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.adopt(library)
        let ids = await browser.importFiles(
            [disk.url("one.txt"), disk.url("two.txt")], in: library, order: ItemOrder(), undoManager: nil)
        #expect(ids.count == 2)
        #expect(library.addedFiles.map(\.name) == ["one.txt", "two.txt"])
        #expect(browser.selection == Set(ids))
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func filesDroppedWhileACollectionIsShownJoinIt() async throws {
        let collection = FakeItemLibrary.collection("Reading")
        let library = FakeItemLibrary(items: [collection])
        let browser = Browser()
        browser.adopt(library)
        browser.show(.collection(collection.id), in: library, order: ItemOrder())
        let ids = await browser.importFiles([disk.url("a.txt")], in: library, order: ItemOrder(), undoManager: nil)
        let added = try #require(ids.first)
        #expect(library.item(added)?.edgesOut.contains { $0.to == .item(collection.id) } == true)
    }

    @Test func filesDroppedOnACollectionJoinItWhereverTheWindowIs() async throws {
        let collection = FakeItemLibrary.collection("Reading")
        let library = FakeItemLibrary(items: [collection])
        let browser = Browser()
        browser.adopt(library)
        let target = browser.fileDropTarget(onCollection: collection.id, in: library)
        let ids = await browser.importFiles([disk.url("a.txt")], to: target, in: library, order: ItemOrder(), undoManager: nil)
        let added = try #require(ids.first)
        #expect(library.item(added)?.edgesOut.contains { $0.to == .item(collection.id) } == true)
        #expect(browser.selection == [added])
    }

    @Test func filesDroppedInACollectionsPlaceAreOneToastAndOneUndoStep() async throws {
        let collection = FakeItemLibrary.collection("Reading")
        let library = FakeItemLibrary(items: [collection])
        let browser = Browser()
        browser.adopt(library)
        browser.show(.collection(collection.id), in: library, order: ItemOrder())
        let toasts = ToastPresenter()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let ids = await browser.importFiles(
            [disk.url("a.txt"), disk.url("b.txt"), disk.url("c.txt")], in: library, order: ItemOrder(), undoManager: undo, toasts: toasts)
        #expect(ids.count == 3)
        #expect(toasts.current?.message == "Added 3 Files")
        #expect(toasts.current?.undo != nil)
        undo.undo()
        #expect(!undo.canUndo)
        for id in ids { #expect(library.item(id)?.state == .trashed) }
    }

    @Test func thePillNamesThePlaceAndSaysWhereFilesGoWhenThePlaceCannotTakeThem() async throws {
        let collection = FakeItemLibrary.collection("Glaze tests")
        let library = FakeItemLibrary(items: [collection])
        let browser = Browser()
        browser.adopt(library)
        browser.show(.collection(collection.id), in: library, order: ItemOrder())
        #expect(browser.fileDropTarget(in: library).pill(count: 3) == "Add 3 Files to Glaze tests")
        #expect(browser.fileDropTarget(in: library).pill(count: 1) == "Add 1 File to Glaze tests")
        browser.show(.feed, in: library, order: ItemOrder())
        #expect(browser.fileDropTarget(in: library).pill(count: 2) == "Add 2 Files to the Feed")
        browser.show(.type(TypeID("core.note")), in: library, order: ItemOrder())
        let notes = browser.fileDropTarget(in: library)
        #expect(notes.pill(count: 3) == "Add 3 Files to the Library")
        #expect(notes.place == .library && notes.collection == nil)
        browser.show(.type(.file), in: library, order: ItemOrder())
        #expect(browser.fileDropTarget(in: library).pill(count: 3) == "Add 3 Files to \(library.name(of: .type(.file)))")
        browser.show(.archive, in: library, order: ItemOrder())
        #expect(browser.fileDropTarget(in: library).pill(count: 0) == "Add Files to the Library")
    }

    @Test func aFolderIsToldAndTheFilesDroppedWithItAreAdded() async throws {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.adopt(library)
        let folder = disk.directory.appending(path: "Folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let toasts = ToastPresenter()
        let ids = await browser.importFiles([folder, disk.url("a.txt")], in: library, order: ItemOrder(), undoManager: nil, toasts: toasts)
        #expect(ids.count == 1)
        #expect(library.notices.waiting.count == 1)
        #expect(toasts.current?.message == "Added 1 of 2 Files")
    }

    @Test func aFileDroppedTwiceIsAddedOnce() async throws {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.adopt(library)
        let file = disk.url("a.txt")
        let ids = await browser.importFiles([file, file], in: library, order: ItemOrder(), undoManager: nil)
        #expect(ids.count == 1)
    }

    @Test func aFileTheLibraryRefusesIsToldAndTheOthersAreStillAdded() async throws {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.adopt(library)
        library.refusesFiles = true
        let toasts = ToastPresenter()
        let ids = await browser.importFiles([disk.url("big.bin"), disk.url("a.txt")], in: library, order: ItemOrder(), undoManager: nil, toasts: toasts)
        #expect(ids.isEmpty)
        #expect(library.notices.waiting.count == 1)
        #expect(toasts.current == nil)
    }

    @Test func filesTheLibraryHasNotShownAreToldNotJoinedAndGiveNoUndo() async throws {
        let collection = FakeItemLibrary.collection("Glaze tests")
        let library = FakeItemLibrary(items: [collection])
        let browser = Browser()
        browser.adopt(library)
        browser.show(.collection(collection.id), in: library, order: ItemOrder())
        library.withheldFiles = ["b.txt"]
        let toasts = ToastPresenter()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let ids = await browser.importFiles(
            [disk.url("a.txt"), disk.url("b.txt")], in: library, order: ItemOrder(), undoManager: undo, toasts: toasts,
            waiting: .milliseconds(50))
        #expect(ids.count == 2)
        #expect(toasts.current?.message == "Added 2 Files, 1 not in Glaze tests")
        #expect(toasts.current?.undo == nil)
        #expect(!undo.canUndo)
        #expect(library.notices.waiting.count == 1)
        #expect(library.item(ids[0])?.collectionIDs.contains(collection.id) == true)
        #expect(browser.selection == [ids[0]])
    }

    @Test func aDropWhoseFilesAreAllUnshownJoinsNothingAndSelectsNothing() async throws {
        let collection = FakeItemLibrary.collection("Glaze tests")
        let library = FakeItemLibrary(items: [collection])
        let browser = Browser()
        browser.adopt(library)
        browser.show(.collection(collection.id), in: library, order: ItemOrder())
        library.withheldFiles = ["a.txt"]
        let toasts = ToastPresenter()
        let ids = await browser.importFiles(
            [disk.url("a.txt")], in: library, order: ItemOrder(), undoManager: nil, toasts: toasts, waiting: .milliseconds(50))
        #expect(ids.count == 1)
        #expect(toasts.current?.message == "Added 1 File, 1 not in Glaze tests")
        #expect(toasts.current?.undo == nil)
        #expect(library.notices.waiting.count == 1)
        #expect(browser.selection.isEmpty)
    }

    @MainActor @Test func theToastAndUndoWaitForTheLibraryToHoldWhatWasAdded() async throws {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.adopt(library)
        library.withheldFiles = ["a.txt"]
        let toasts = ToastPresenter()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let url = disk.url("a.txt")
        let drop = Task { @MainActor in
            await browser.importFiles([url], in: library, order: ItemOrder(), undoManager: undo, toasts: toasts)
        }
        try #require(await eventually { !library.withheld.isEmpty })
        #expect(toasts.current == nil)
        #expect(!undo.canUndo)
        library.showWithheld()
        let ids = await drop.value
        #expect(toasts.current?.message == "Added 1 File")
        #expect(toasts.current?.undo != nil)
        #expect(undo.canUndo)
        undo.undo()
        #expect(library.item(ids[0])?.state == .trashed)
    }

    @Test func aFileThatCannotBeReadIsToldAndTheRestAreStillAdded() async throws {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.adopt(library)
        let missing = disk.directory.appending(path: "gone.txt")
        let ids = await browser.importFiles([missing, disk.url("kept.txt")], in: library, order: ItemOrder(), undoManager: nil)
        #expect(ids.count == 1)
        #expect(library.notices.waiting.count == 1)
    }

    @Test func filesGoWhereTheyWereDroppedWhenThePersonMovesOnMidImport() async throws {
        let collection = FakeItemLibrary.collection("Reading")
        let library = FakeItemLibrary(items: [collection])
        let browser = Browser()
        browser.adopt(library)
        browser.show(.collection(collection.id), in: library, order: ItemOrder())
        library.sendingFile = { browser.show(.library, in: library, order: ItemOrder()) }
        let ids = await browser.importFiles([disk.url("a.txt"), disk.url("b.txt")], in: library, order: ItemOrder(), undoManager: nil)
        #expect(ids.count == 2)
        for id in ids { #expect(library.item(id)?.edgesOut.contains { $0.to == .item(collection.id) } == true) }
        #expect(browser.shown == .library)
    }

    @Test func filesDroppedInTheFeedAllKeepTheFeedTierWhenThePersonMovesOnMidImport() async throws {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.adopt(library)
        browser.show(.feed, in: library, order: ItemOrder())
        library.sendingFile = { browser.show(.library, in: library, order: ItemOrder()) }
        _ = await browser.importFiles([disk.url("a.txt"), disk.url("b.txt")], in: library, order: ItemOrder(), undoManager: nil)
        #expect(library.addedTiers == [.feed, .feed])
    }

    @Test func aDropCutOffByALibraryChangeStillAddsEveryFileToTheLibraryItWasDroppedOn() async throws {
        let library = FakeItemLibrary()
        let other = FakeItemLibrary()
        let browser = Browser()
        browser.adopt(library)
        library.sendingFile = { browser.adopt(other) }
        let ids = await browser.importFiles([disk.url("a.txt"), disk.url("b.txt")], in: library, order: ItemOrder(), undoManager: nil)
        #expect(library.addedFiles.map(\.name) == ["a.txt", "b.txt"])
        #expect(other.addedFiles.isEmpty)
        #expect(ids.count == 2)
        #expect(browser.selection.isEmpty)
    }

    @Test func aFileThatFailsAfterALibraryChangeIsStillToldAndTheRestAreAdded() async throws {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.adopt(library)
        library.sendingFile = { browser.adopt(FakeItemLibrary()) }
        let missing = disk.directory.appending(path: "gone.txt")
        let ids = await browser.importFiles([disk.url("a.txt"), missing, disk.url("b.txt")], in: library, order: ItemOrder(), undoManager: nil)
        #expect(ids.count == 2)
        #expect(library.notices.waiting.count == 1)
    }

    @Test func filesDroppedBeforeALibraryChangeAreStillAddedToTheirLibraryAndNothingIsSelected() async throws {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.adopt(library)
        browser.adopt(FakeItemLibrary())
        let ids = await browser.importFiles([disk.url("a.txt")], in: library, order: ItemOrder(), undoManager: nil)
        #expect(ids.count == 1)
        #expect(library.addedFiles.count == 1)
        #expect(browser.selection.isEmpty)
    }

    @Test func aSymbolicLinkToAFileIsTakenAsThatFile() throws {
        let target = disk.url("real.txt", "contents")
        let link = disk.directory.appending(path: "link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let file = try #require(QuickAdd.File(link))
        #expect(file.byteCount == 8)
        let folderLink = disk.directory.appending(path: "folder-link")
        try FileManager.default.createSymbolicLink(at: folderLink, withDestinationURL: disk.directory)
        #expect(QuickAdd.File(folderLink) == nil)
    }

    @Test func aDraggedItemLeavesAsAMarkdownFileNamedAfterIt() async throws {
        let library = FakeItemLibrary()
        let note = library.add("# Plans\n\nSome text")
        let reference = library.dragReference(of: note.id)
        #expect(reference.text == "# Plans\n\nSome text")
        let text = try #require(reference.text)
        let file = try #require(QuickLookFile.write(text, titled: reference.title, as: reference.type, in: "Drag-test", key: note.id.rawValue))
        defer { file.remove() }
        #expect(file.url.lastPathComponent == QuickLookFile.name(for: "Plans", type: .markdown))
        #expect(try String(contentsOf: file.url, encoding: .utf8) == "# Plans\n\nSome text")
    }

    @Test func aDraggedFileItemFetchesItsFileOnlyWhenAskedFor() async throws {
        let library = FakeItemLibrary()
        let browser = Browser()
        browser.adopt(library)
        let id = try #require(await library.addFile(disk.url("scan.txt", "contents"), title: nil, parentID: nil, tier: .library, tags: []))
        library.files[id] = disk.url("kept")
        let reference = library.dragReference(of: id)
        #expect(library.fetches == 0)
        guard case .file(let fetch) = reference.content else { Issue.record("A file item carries its file."); return }
        #expect(try await fetch() == library.files[id])
        #expect(library.fetches == 1)
    }

    @Test func anItemDraggedToAnotherWindowArrivesAsItsIdentifierOnly() async throws {
        let library = FakeItemLibrary()
        let note = library.add("# Plans")
        let data = try JSONEncoder().encode(library.dragReference(of: note.id))
        let decoded = try JSONDecoder().decode(ItemReference.self, from: data)
        #expect(decoded.id == note.id)
        #expect(decoded.text == nil)
    }

    @Test func copiesAreMadeInAFolderOfTheRunningProcess() throws {
        let file = try #require(QuickLookFile.write("text", titled: "Plans", as: .plainText, in: "Process-test"))
        defer { file.remove() }
        #expect(file.folder.deletingLastPathComponent().lastPathComponent == String(ProcessInfo.processInfo.processIdentifier))
    }

    @Test func leftoversOfProcessesNoLongerRunningGoAndThoseOfRunningOnesStay() throws {
        let root = disk.directory
        let manager = FileManager.default
        for name in QuickLookFile.folderNames {
            for process in ["111", "222", "old-layout"] {
                let folder = root.appending(path: name).appending(path: process)
                try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                try Data("x".utf8).write(to: folder.appending(path: "file.txt"))
            }
        }
        QuickLookFile.removeLeftovers(in: root, isRunning: { $0 == 111 })
        for name in QuickLookFile.folderNames {
            let base = root.appending(path: name)
            #expect(manager.fileExists(atPath: base.appending(path: "111/file.txt").path))
            #expect(!manager.fileExists(atPath: base.appending(path: "222").path))
            #expect(!manager.fileExists(atPath: base.appending(path: "old-layout").path))
        }
    }

    @Test func thisProcessIsARunningCopyOfTheAppAndAnUnusedOneIsNot() {
        #expect(QuickLookFile.isRunningCopy(ProcessInfo.processInfo.processIdentifier))
        #expect(!QuickLookFile.isRunningCopy(Int32.max))
    }

    @Test func twoDevicePhotosWithTheSameNameAreBothKept() async throws {
        let first = try photoProvider(named: "IMG", bytes: "one")
        let second = try photoProvider(named: "IMG", bytes: "two")
        let gathered = await FileIntake.files(from: [first, second])
        defer { gathered.remove() }
        #expect(gathered.unreadable == 0)
        #expect(gathered.urls.count == 2)
        #expect(Set(gathered.urls).count == 2)
        #expect(gathered.urls.allSatisfy { $0.lastPathComponent == "IMG.png" })
        let texts = try gathered.urls.map { try String(contentsOf: $0, encoding: .utf8) }
        #expect(Set(texts) == ["one", "two"])
    }

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

    @Test func aQuickLookReplacedWhileFetchingStopsAndLeavesNoCopies() async throws {
        let library = FakeItemLibrary()
        let note = library.add("# Plans")
        let fileID = try #require(await library.addFile(disk.url("scan.txt"), title: nil, parentID: nil, tier: .library, tags: []))
        library.files[fileID] = disk.url("kept", "file contents")
        library.fetchDelay[fileID] = .milliseconds(500)
        let browser = Browser()
        browser.adopt(library)
        browser.selection = [note.id, fileID]
        let first = Task { await browser.quickLookSelection(in: library) }
        #expect(await eventually { browser.quickLook?.urls.count == 1 })
        let firstCopy = try #require(browser.quickLook?.urls.first)
        browser.selection = [note.id]
        await browser.quickLookSelection(in: library)
        await first.value
        let request = try #require(browser.quickLook)
        #expect(request.urls.count == 1)
        #expect(!FileManager.default.fileExists(atPath: firstCopy.path))
        #expect(FileManager.default.fileExists(atPath: request.urls[0].path))
        browser.dismissQuickLook()
    }

    @Test func aQuickLookClosedWhileFetchingShowsNothingAndLeavesNoCopies() async throws {
        let library = FakeItemLibrary()
        let fileID = try #require(await library.addFile(disk.url("scan.txt"), title: nil, parentID: nil, tier: .library, tags: []))
        library.files[fileID] = disk.url("kept", "file contents")
        library.fetchDelay[fileID] = .milliseconds(300)
        let browser = Browser()
        browser.adopt(library)
        browser.selection = [fileID]
        let pending = Task { await browser.quickLookSelection(in: library) }
        #expect(await eventually { library.fetches == 1 })
        browser.dismissQuickLook()
        await pending.value
        #expect(browser.quickLook == nil)
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func aQuickLookClosesWhenTheWindowChangesLibraryMidFetch() async throws {
        let library = FakeItemLibrary()
        let note = library.add("# Plans")
        let fileID = try #require(await library.addFile(disk.url("scan.txt"), title: nil, parentID: nil, tier: .library, tags: []))
        library.files[fileID] = disk.url("kept", "file contents")
        library.fetchDelay[fileID] = .milliseconds(300)
        let browser = Browser()
        browser.adopt(library)
        browser.selection = [note.id, fileID]
        let pending = Task { await browser.quickLookSelection(in: library) }
        #expect(await eventually { browser.quickLook?.urls.count == 1 })
        let shown = try #require(browser.quickLook?.urls.first)
        browser.adopt(FakeItemLibrary())
        await pending.value
        #expect(browser.quickLook == nil)
        #expect(!FileManager.default.fileExists(atPath: shown.path))
    }

    @Test func quickLookTellsThePersonWhenTheFileCannotBeFetched() async throws {
        let library = FakeItemLibrary()
        let fileID = try #require(await library.addFile(disk.url("scan.txt"), title: nil, parentID: nil, tier: .library, tags: []))
        library.fetchFails = true
        let browser = Browser()
        browser.adopt(library)
        browser.selection = [fileID]
        await browser.quickLookSelection(in: library)
        #expect(browser.quickLook == nil)
        #expect(library.notices.waiting.count == 1)
    }
}
