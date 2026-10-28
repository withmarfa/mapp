import Foundation
import Testing
@testable import MAPP

@Suite(.hangLimit) struct MarfaKeptFileTests {
    let folder: TemporaryFolder
    var kept: URL { folder.url.appending(path: "MAPP Files", directoryHint: .isDirectory) }

    init() throws {
        folder = try TemporaryFolder()
    }

    private func leasedFile(holding text: String) throws -> URL {
        let file = folder.url.appending(path: "leased-\(UUID().uuidString)")
        try Data(text.utf8).write(to: file)
        return file
    }

    @Test func aKeptCopyOutlastsTheLeasedFileUnderItsTitle() async throws {
        let leased = try leasedFile(holding: "bytes")
        let copy = try await MarfaSource.keptCopy(of: leased, hash: "sha256:a", name: "Photo.png", in: kept)

        try FileManager.default.removeItem(at: leased)

        #expect(try String(contentsOf: copy, encoding: .utf8) == "bytes")
        #expect(copy.lastPathComponent == "Photo.png")
        #expect(copy.deletingLastPathComponent().lastPathComponent == "sha256:a")
    }

    @Test func aKeptCopyIsReadOnlySoAnotherAppCanNotSaveOverMarfasFile() async throws {
        let copy = try await MarfaSource.keptCopy(of: try leasedFile(holding: "bytes"), hash: "sha256:a", name: "a.txt", in: kept)

        let permissions = try FileManager.default.attributesOfItem(atPath: copy.path)[.posixPermissions] as? Int
        #expect(permissions == 0o444)
        #expect(throws: (any Error).self) { try Data("edited".utf8).write(to: copy) }
        await MarfaSource.removeKeptCopies(in: kept)
        #expect(!FileManager.default.fileExists(atPath: copy.path), "a read-only copy is still removed with the rest")
    }

    @Test func aHashAlreadyKeptIsAnsweredWithoutCopyingAgain() async throws {
        let copy = try await MarfaSource.keptCopy(of: try leasedFile(holding: "first"), hash: "sha256:a", name: "a.txt", in: kept)

        let again = try await MarfaSource.keptCopy(of: try leasedFile(holding: "second"), hash: "sha256:a", name: "a.txt", in: kept)

        #expect(again == copy)
        #expect(try String(contentsOf: again, encoding: .utf8) == "first")
    }

    @Test func aMissingLeasedFileThrowsAndLeavesNothingKept() async throws {
        let missing = folder.url.appending(path: "missing")

        await #expect(throws: (any Error).self) {
            try await MarfaSource.keptCopy(of: missing, hash: "sha256:a", name: "a.txt", in: kept)
        }

        let names = (try? FileManager.default.contentsOfDirectory(atPath: kept.appending(path: "sha256:a").path)) ?? []
        #expect(names.isEmpty)
    }

    @Test func aTitleWithoutAnExtensionTakesItsTypes() {
        #expect(MarfaSource.keptName(title: "Scan", mimeType: "image/png") == "Scan.png")
        #expect(MarfaSource.keptName(title: "Scan.jpg", mimeType: "image/png") == "Scan.jpg")
        #expect(MarfaSource.keptName(title: ".hidden/name:x", mimeType: nil) == "hidden-name-x")
    }

    @Test func keptCopiesAreRemovedTogether() async throws {
        let copy = try await MarfaSource.keptCopy(of: try leasedFile(holding: "bytes"), hash: "sha256:a", name: "a.txt", in: kept)

        await MarfaSource.removeKeptCopies(in: kept)

        #expect(!FileManager.default.fileExists(atPath: copy.path))
    }
}
