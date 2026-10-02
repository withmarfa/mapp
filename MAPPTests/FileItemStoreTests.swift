import Foundation
import Testing
@testable import MAPP

@MainActor
struct FileItemStoreTests {
    @Test func markdownImportCompletionResolvesLoadedNoteAndIsConsumed() async throws {
        let root = try TemporaryFolder()
        let bin = try TemporaryFolder()
        let source = try TemporaryFolder()
        let text = "---\ntitle: Imported\n---\n# Body\n"
        try source.write(text, to: "Imported.MD")
        let store = FolderStore(root: root.url, bin: bin.url)
        let library = NoteLibrary(loadingFrom: store, defaults: nil)
        await library.load()
        let requestID = UUID()
        library.importFiles([source.url.appending(path: "Imported.MD")], requestID: requestID)
        store.drain()
        for _ in 0..<100 where library.completedImports[requestID] == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        await library.reread()
        let expected = UUID(stableFrom: "note:Imported.MD")
        #expect(library.completedImports[requestID] == expected)
        #expect(library.note(expected)?.file.text == text)
        #expect(library.item(expected) != nil)
        #expect(library.files.isEmpty)
        library.consumeImportCompletion(requestID)
        #expect(library.completedImports[requestID] == nil)
    }

    @Test func importsPreserveBytesAndCollisionDoesNotOverwrite() throws {
        let root = try TemporaryFolder()
        let bin = try TemporaryFolder()
        let source = try TemporaryFolder()
        let bytes = Data([0, 255, 4, 10, 13])
        let input = source.url.appending(path: "Picture.png")
        try bytes.write(to: input)
        try root.write("Existing", to: "Picture.png")
        let store = FolderStore(root: root.url, bin: bin.url)
        store.perform(.importFile(path: "Picture.png", source: input))
        store.drain()
        #expect(root.read("Picture.png") == "Existing")
        #expect(try Data(contentsOf: root.url.appending(path: "Picture 2.png")) == bytes)
        let reopened = FolderStore(root: root.url, bin: bin.url)
        #expect(Set(try reopened.load().files.map(\.path)) == ["Picture.png", "Picture 2.png"])
    }

    @Test func fileAccessAndImportRejectEscapesAndSymlinks() throws {
        let root = try TemporaryFolder()
        let bin = try TemporaryFolder()
        let source = try TemporaryFolder()
        try source.write("Private", to: "Outside.pdf")
        let input = source.url.appending(path: "Outside.pdf")
        try FileManager.default.createSymbolicLink(at: root.url.appending(path: "Escape.pdf"), withDestinationURL: input)
        let store = FolderStore(root: root.url, bin: bin.url)
        #expect(store.fileURL(for: "../Outside.pdf") == nil)
        #expect(store.fileURL(for: "Escape.pdf") == nil)
        #expect(try store.load().files.isEmpty)
        store.perform(.importFile(path: "../Escape.pdf", source: input))
        store.drain()
        #expect(!FileManager.default.fileExists(atPath: root.url.deletingLastPathComponent().appending(path: "Escape.pdf").path))
        #expect(try Data(contentsOf: input) == Data("Private".utf8))
    }

    @Test func successfulImportReportsActualPathAndDirectoryImportFails() async throws {
        let root = try TemporaryFolder()
        let bin = try TemporaryFolder()
        let source = try TemporaryFolder()
        try source.write("PDF", to: "Report.pdf")
        try root.write("Existing", to: "Report.pdf")
        let store = FolderStore(root: root.url, bin: bin.url)
        var imported: String?
        var failure: String?
        store.imported = { _, path in imported = path }
        store.failed = { _, message in failure = message }
        store.perform(.importFile(path: "Report.pdf", source: source.url.appending(path: "Report.pdf")))
        store.drain()
        for _ in 0..<100 where imported == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(imported == "Report 2.pdf")
        store.perform(.importFile(path: "Directory", source: source.url))
        store.drain()
        for _ in 0..<100 where failure == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(failure != nil)
        #expect(!root.exists("Directory"))
    }

    @Test func rejectedImportLeavesNoPartialItemOrTemporaryFile() async throws {
        let root = try TemporaryFolder()
        let bin = try TemporaryFolder()
        let source = try TemporaryFolder()
        let input = source.url.appending(path: "Missing.pdf")
        let store = FolderStore(root: root.url, bin: bin.url)
        var failure: String?
        store.failed = { _, message in failure = message }
        store.perform(.importFile(path: "Missing.pdf", source: input))
        store.drain()
        for _ in 0..<100 where failure == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(failure != nil)
        #expect(try store.load().files.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.url.path).isEmpty)
    }

    @Test func attachmentAndHiddenFilesRemainExcluded() throws {
        let root = try TemporaryFolder()
        let bin = try TemporaryFolder()
        try root.write("Visible", to: "Work/Report.pdf")
        try root.write("Attachment", to: "Attachments/Picture.png")
        try root.write("Hidden", to: ".marfa/State.bin")
        let store = FolderStore(root: root.url, bin: bin.url)
        #expect(try store.load().files.map(\.path) == ["Work/Report.pdf"])
    }
}
