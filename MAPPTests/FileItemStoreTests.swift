import Foundation
import Testing
@testable import MAPP

@MainActor
struct FileItemStoreTests {
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
