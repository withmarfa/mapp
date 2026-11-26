import Foundation
import Testing
@testable import MarfaMac

@Suite(.hangLimit) struct MarfaKeptFileTests {
    let folder: TemporaryFolder
    var kept: URL { folder.url.appending(path: "Marfa Files", directoryHint: .isDirectory) }

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
        let copy = try await MarfaSource.keptCopy(of: leased, hash: "sha256:a", name: "Photo.png", in: kept, generation: MarfaSource.keptGeneration(of: kept))

        try FileManager.default.removeItem(at: leased)

        #expect(try String(contentsOf: copy, encoding: .utf8) == "bytes")
        #expect(copy.lastPathComponent == "Photo.png")
        #expect(copy.deletingLastPathComponent().lastPathComponent == "sha256:a")
    }

    @Test func aKeptCopyIsReadOnlySoAnotherAppCanNotSaveOverMarfasFile() async throws {
        let copy = try await MarfaSource.keptCopy(of: try leasedFile(holding: "bytes"), hash: "sha256:a", name: "a.txt", in: kept, generation: MarfaSource.keptGeneration(of: kept))

        let permissions = try FileManager.default.attributesOfItem(atPath: copy.path)[.posixPermissions] as? Int
        #expect(permissions == 0o444)
        #expect(throws: (any Error).self) { try Data("edited".utf8).write(to: copy) }
        await MarfaSource.removeKeptCopies(in: kept)
        #expect(!FileManager.default.fileExists(atPath: copy.path), "a read-only copy is still removed with the rest")
    }

    @Test func aHashAlreadyKeptIsAnsweredWithoutCopyingAgain() async throws {
        let copy = try await MarfaSource.keptCopy(of: try leasedFile(holding: "first"), hash: "sha256:a", name: "a.txt", in: kept, generation: MarfaSource.keptGeneration(of: kept))

        let again = try await MarfaSource.keptCopy(of: try leasedFile(holding: "second"), hash: "sha256:a", name: "a.txt", in: kept, generation: MarfaSource.keptGeneration(of: kept))

        #expect(again == copy)
        #expect(try String(contentsOf: again, encoding: .utf8) == "first")
    }

    @Test func aMissingLeasedFileThrowsAndLeavesNothingKept() async throws {
        let missing = folder.url.appending(path: "missing")

        await #expect(throws: (any Error).self) {
            try await MarfaSource.keptCopy(of: missing, hash: "sha256:a", name: "a.txt", in: kept, generation: MarfaSource.keptGeneration(of: kept))
        }

        let names = (try? FileManager.default.contentsOfDirectory(atPath: kept.appending(path: "sha256:a").path)) ?? []
        #expect(names.isEmpty)
    }

    @Test func aTitleWithoutAnExtensionTakesItsTypes() {
        #expect(MarfaSource.keptName(title: "Scan", mimeType: "image/png") == "Scan.png")
        #expect(MarfaSource.keptName(title: "Scan.jpg", mimeType: "image/png") == "Scan.jpg")
        #expect(MarfaSource.keptName(title: ".hidden/name:x", mimeType: nil) == "hidden-name-x")
    }

    /// A file whose fetch began before its library's files were removed, as on a disconnect, is not kept after them.
    @Test func aFileFetchedBeforeItsLibraryWasLeftIsNotKept() async throws {
        let generation = MarfaSource.keptGeneration(of: kept)
        await MarfaSource.removeKeptCopies(in: kept)

        await #expect(throws: CancellationError.self) {
            try await MarfaSource.keptCopy(of: try leasedFile(holding: "late"), hash: "sha256:a", name: "a.txt", in: kept, generation: generation)
        }
        #expect(!FileManager.default.fileExists(atPath: kept.path))
    }

    /// Removing one library's files leaves another's, and a fetch for the other still keeps its file.
    @Test func removingOneLibrarysFilesLeavesAnothers() async throws {
        let other = folder.url.appending(path: "Other Files", directoryHint: .isDirectory)
        let theirs = try await MarfaSource.keptCopy(
            of: try leasedFile(holding: "theirs"), hash: "sha256:b", name: "b.txt", in: other, generation: MarfaSource.keptGeneration(of: other))
        let generation = MarfaSource.keptGeneration(of: other)

        await MarfaSource.removeKeptCopies(in: kept)

        #expect(FileManager.default.fileExists(atPath: theirs.path))
        let late = try await MarfaSource.keptCopy(of: try leasedFile(holding: "late"), hash: "sha256:c", name: "c.txt", in: other, generation: generation)
        #expect(late.path.hasPrefix(other.path))
    }

    @Test func keptCopiesAreRemovedTogether() async throws {
        let copy = try await MarfaSource.keptCopy(of: try leasedFile(holding: "bytes"), hash: "sha256:a", name: "a.txt", in: kept, generation: MarfaSource.keptGeneration(of: kept))

        await MarfaSource.removeKeptCopies(in: kept)

        #expect(!FileManager.default.fileExists(atPath: copy.path))
    }
}
