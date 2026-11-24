import Foundation
import Marfa
import MarfaTesting
import Synchronization
import Testing
@testable import MarfaMac

/// Where an archive's bytes come from in a test.
private struct FakeArchive: ArchiveSource {
    var pieces: [[UInt8]] = []
    var failure: (any Error)?

    func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws {
        for piece in pieces { try write(piece) }
        if let failure { throw failure }
    }
}

@Suite(.hangLimit) struct LibraryExportTests {
    private func folder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "export-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func anArchiveIsWrittenWholeUnderTheServersNameAndTheDay() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try await LibraryExport.export(
            from: FakeArchive(pieces: [[1, 2], [3]]), serverName: "Castell Studio", to: folder,
            now: Date(timeIntervalSince1970: 1_795_000_000))
        #expect(file.lastPathComponent == "Castell Studio 2026-11-18.tar")
        #expect(try Data(contentsOf: file) == Data([1, 2, 3]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Castell Studio 2026-11-18.tar"])
    }

    @Test func anExportNeverWritesOverAnEarlierOne() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let first = try await LibraryExport.export(from: FakeArchive(pieces: [[1]]), serverName: "Marfa", to: folder, now: now)
        let second = try await LibraryExport.export(from: FakeArchive(pieces: [[2]]), serverName: "Marfa", to: folder, now: now)
        #expect(first != second)
        #expect(second.lastPathComponent == "Marfa 2026-11-18 2.tar")
        #expect(try Data(contentsOf: first) == Data([1]))
    }

    @Test func aServerThatDoesNotAnswerFailsInOneLineAndLeavesNoFile() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let down = FakeArchive(pieces: [[1, 2]], failure: URLError(.cannotConnectToHost))
        let failure = await #expect(throws: LibraryExport.Failure.self) {
            try await LibraryExport.export(from: down, serverName: "Castell Studio", to: folder)
        }
        #expect(failure?.message == "Couldn’t export. Castell Studio isn’t answering.")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty, "no partial archive is left")
    }

    @Test func aSignInTheServerEndedAndAMissingPermissionAreToldApart() {
        #expect(LibraryExport.failure(MarfaServerCalls.Ending.keyRefused, serverName: "X").message.contains("Sign in again"))
        #expect(LibraryExport.failure(MarfaServerCalls.Ending.notPermitted, serverName: "X").message.contains("isn’t allowed"))
    }

    @Test func aFolderThatCannotBeWrittenToIsTold() async throws {
        let missing = URL.temporaryDirectory.appending(path: "nowhere-\(UUID())", directoryHint: .isDirectory)
        let failure = await #expect(throws: LibraryExport.Failure.self) {
            try await LibraryExport.export(from: FakeArchive(pieces: [[1]]), serverName: "X", to: missing)
        }
        #expect(failure?.message.contains("folder") == true)
    }
}

@Suite(.hangLimit) struct DownloadAlertTests {
    @Test func theAlertSaysWhatHappensToChangesNotYetSent() {
        #expect(!OnThisMacPage.downloadMessage(name: "Castell Studio", unsent: 0).contains("not yet sent"))
        let kept = OnThisMacPage.downloadMessage(name: "Castell Studio", unsent: 3)
        #expect(kept.contains("3 changes") && kept.contains("stay on this Mac"))
    }
}
