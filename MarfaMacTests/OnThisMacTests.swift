import Foundation
import Marfa
import MarfaTesting
import Synchronization
import Testing
@testable import MarfaMac

/// One tar entry, as the server writes it: a ustar header with its sum, the bytes, and padding to the block.
nonisolated func tarEntry(_ name: String, _ body: [UInt8]) -> [UInt8] {
    func octal(_ value: Int, width: Int) -> [UInt8] {
        let digits = String(value, radix: 8)
        return Array((String(repeating: "0", count: width - 1 - digits.count) + digits).utf8) + [0]
    }
    var header = [UInt8](repeating: 0, count: 512)
    header.replaceSubrange(0..<name.utf8.count, with: Array(name.utf8))
    header.replaceSubrange(100..<108, with: octal(0o644, width: 8))
    header.replaceSubrange(124..<136, with: octal(body.count, width: 12))
    header[156] = UInt8(ascii: "0")
    header.replaceSubrange(257..<265, with: Array("ustar\u{0}00".utf8))
    let sum = header.indices.reduce(0) { $0 + ((148..<156).contains($1) ? 32 : Int(header[$1])) }
    header.replaceSubrange(148..<156, with: octal(sum, width: 7) + [32])
    return header + body + [UInt8](repeating: 0, count: (512 - body.count % 512) % 512)
}

/// A whole archive of the Marfa `instance`: its manifest naming `files` files of which it carries `carried`, the line
/// files a restore requires (`payload` as the items), a blob for each carried file, and the end of the tar.
nonisolated func archiveBytes(instance: String = "instance-one", files: Int = 0, carried: Int = 0, payload: [UInt8] = []) -> [UInt8] {
    let manifest = #"{"version":4,"format":"marfa-archive","instance_id":"\#(instance)","file_count":\#(files),"blob_count":\#(carried)}"#
    var bytes = tarEntry("manifest.json", Array(manifest.utf8))
    for name in ["files.ndjson.gz", "instance.ndjson.gz", "items.ndjson.gz", "versions.ndjson.gz", "edges.ndjson.gz", "rows.ndjson.gz"] {
        bytes += tarEntry(name, name == "items.ndjson.gz" ? payload : [])
    }
    for blob in 0..<carried { bytes += tarEntry("blobs/" + String(repeating: "0", count: 63) + String(blob), [UInt8(blob)]) }
    return bytes + [UInt8](repeating: 0, count: 1024)
}

/// Where an archive's bytes come from in a test: `bytes` in pieces of `piece` bytes, then `failure` if there is one.
private struct FakeArchive: ArchiveSource {
    var bytes = archiveBytes()
    var piece = 333
    var failure: (any Error)?

    func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws {
        for start in stride(from: 0, to: bytes.count, by: piece) { try write(Array(bytes[start..<min(start + piece, bytes.count)])) }
        if let failure { throw failure }
    }
}

@Suite(.hangLimit) struct LibraryExportTests {
    private func folder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "export-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func contents(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    @Test func anArchiveIsWrittenWholeUnderTheServersNameAndTheDay() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bytes = archiveBytes(payload: [1, 2, 3])
        let gate = ExportGate()
        let exported = try await LibraryExport.export(
            from: FakeArchive(bytes: bytes), serverName: "Castell Studio", to: folder,
            now: Date(timeIntervalSince1970: 1_795_000_000), instance: "instance-one", gate: gate)
        #expect(exported.file.lastPathComponent == "Castell Studio 2026-11-18.tar")
        #expect(exported.instance == "instance-one")
        #expect(try Data(contentsOf: exported.file) == Data(bytes))
        #expect(try contents(folder) == ["Castell Studio 2026-11-18.tar"])
        #expect(gate.workspace == nil, "the private directory is gone")
    }

    @Test func anExportNeverWritesOverAnEarlierOne() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let one = archiveBytes(payload: [1])
        let first = try await LibraryExport.export(from: FakeArchive(bytes: one), serverName: "Marfa", to: folder, now: now).file
        let second = try await LibraryExport.export(
            from: FakeArchive(bytes: archiveBytes(payload: [2])), serverName: "Marfa", to: folder, now: now
        ).file
        #expect(second.lastPathComponent == "Marfa 2026-11-18 2.tar")
        #expect(try Data(contentsOf: first) == Data(one))
    }

    @Test func twoExportsAtOnceIntoOneFolderBothEndWholeAndKeepAnEarlierFile() async throws {
        /// Holds each archive after its first half until both have started.
        actor Meeting {
            private var waiting: [CheckedContinuation<Void, Never>] = []
            func arrive() async {
                await withCheckedContinuation { continuation in
                    waiting.append(continuation)
                    guard waiting.count == 2 else { return }
                    for one in waiting { one.resume() }
                    waiting = []
                }
            }
        }
        struct Met: ArchiveSource {
            let meeting: Meeting
            let bytes: [UInt8]
            func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws {
                try write(Array(bytes[..<1000]))
                await meeting.arrive()
                try write(Array(bytes[1000...]))
            }
        }
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let earlier = folder.appending(path: "Marfa 2026-11-18.tar")
        try Data([9]).write(to: earlier)
        let meeting = Meeting()
        let (one, two) = (archiveBytes(payload: [1]), archiveBytes(payload: [2]))
        async let first = LibraryExport.export(from: Met(meeting: meeting, bytes: one), serverName: "Marfa", to: folder, now: now)
        async let second = LibraryExport.export(from: Met(meeting: meeting, bytes: two), serverName: "Marfa", to: folder, now: now)
        let files = try await [first, second].map(\.file)
        #expect(Set(files.map(\.lastPathComponent)) == ["Marfa 2026-11-18 2.tar", "Marfa 2026-11-18 3.tar"])
        #expect(Set(try files.map { try Data(contentsOf: $0) }) == [Data(one), Data(two)])
        #expect(try Data(contentsOf: earlier) == Data([9]))
        #expect(try contents(folder).count == 3, "nothing else is left in the folder")
    }

    @Test func aFileThatTakesTheNameDuringAnExportIsNotReplaced() async throws {
        struct Taken: ArchiveSource {
            let name: URL
            func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws {
                try write(archiveBytes())
                try Data([9]).write(to: name)
            }
        }
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let taken = folder.appending(path: "Marfa 2026-11-18.tar")
        let file = try await LibraryExport.export(
            from: Taken(name: taken), serverName: "Marfa", to: folder, now: Date(timeIntervalSince1970: 1_795_000_000)
        ).file
        #expect(file.lastPathComponent == "Marfa 2026-11-18 2.tar")
        #expect(try Data(contentsOf: taken) == Data([9]))
    }

    @Test func anArchiveSaysHowManyFilesItDoesNotCarry() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let exported = try await LibraryExport.export(
            from: FakeArchive(bytes: archiveBytes(files: 5, carried: 2), piece: 7), serverName: "Marfa", to: folder)
        #expect(exported.notCarried == 3)
        #expect(LibraryExport.lacking(exported, serverName: "Marfa") == "It lacks 3 files Marfa couldn’t send.")
        let whole = try await LibraryExport.export(from: FakeArchive(bytes: archiveBytes(files: 2, carried: 2)), serverName: "Marfa", to: folder)
        #expect(whole.notCarried == 0 && LibraryExport.lacking(whole, serverName: "Marfa") == nil)
    }

    /// Each way a stream falls short of a whole archive.
    nonisolated enum Short: CaseIterable, Sendable {
        case noManifest, endsAfterTheManifest, endsInsideAnEntry, noEnd, lacksAnEntry, lacksABlob, damagedHeader, notAMarfaArchive

        var bytes: [UInt8] {
            let whole = archiveBytes(files: 2, carried: 2)
            let manifestEnd = 1024
            switch self {
            case .noManifest: return Array(whole[manifestEnd...])
            case .endsAfterTheManifest: return Array(whole[..<manifestEnd])
            case .endsInsideAnEntry: return Array(whole[..<(whole.count - 1024 - 300)])
            case .noEnd: return Array(whole[..<(whole.count - 1024)])
            case .lacksAnEntry:
                return tarEntry("manifest.json", Array(#"{"format":"marfa-archive","instance_id":"instance-one","file_count":0,"blob_count":0}"#.utf8))
                    + tarEntry("items.ndjson.gz", []) + [UInt8](repeating: 0, count: 1024)
            case .lacksABlob: return Array(whole[..<(whole.count - 1024 - 1024)]) + [UInt8](repeating: 0, count: 1024)
            case .damagedHeader:
                var damaged = whole
                damaged[manifestEnd + 3] ^= 1
                return damaged
            case .notAMarfaArchive:
                return archiveBytes().replacing(Array("marfa-archive".utf8), with: Array("other-archive".utf8))
            }
        }
    }

    @Test(arguments: Short.allCases) func aStreamThatIsNotAWholeArchiveIsNotSaved(_ short: Short) async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let gate = ExportGate()
        let failure = await #expect(throws: LibraryExport.Failure.self) {
            try await LibraryExport.export(from: FakeArchive(bytes: short.bytes), serverName: "Marfa", to: folder, gate: gate)
        }
        #expect(failure?.message == "Couldn’t export. Marfa sent an archive that isn’t whole, so it wasn’t saved.")
        #expect(try contents(folder).isEmpty)
        #expect(gate.workspace == nil)
    }

    @Test func anArchiveOfAnotherMarfaIsNotSaved() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let failure = await #expect(throws: LibraryExport.Failure.self) {
            try await LibraryExport.export(
                from: FakeArchive(bytes: archiveBytes(instance: "instance-two")), serverName: "Marfa", to: folder, instance: "instance-one")
        }
        #expect(failure?.message.contains("another Marfa") == true)
        #expect(try contents(folder).isEmpty)
    }

    @Test func aGateClosedBeforeTheMovePublishesNothing() async throws {
        struct Closing: ArchiveSource {
            let gate: ExportGate
            func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws {
                try write(archiveBytes())
                gate.close()
            }
        }
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let gate = ExportGate()
        await #expect(throws: LibraryExport.Failure.self) {
            try await LibraryExport.export(from: Closing(gate: gate), serverName: "Marfa", to: folder, gate: gate)
        }
        #expect(try contents(folder).isEmpty, "a whole archive is not published once its gate is closed")
        #expect(gate.workspace == nil)
    }

    @Test func aCancelledExportRemovesOnlyItsOwnDirectoryAndLeavesTheFolderAlone() async throws {
        struct Endless: ArchiveSource {
            func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws {
                try write(Array(archiveBytes()[..<2000]))
                // Hold the stream open until the test cancels it.
                try await Task.sleep(for: .seconds(3600))
            }
        }
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let other = folder.appending(path: ".Marfa export.partial")
        try Data([9]).write(to: other)
        let gate = ExportGate()
        let export = Task { try await LibraryExport.export(from: Endless(), serverName: "Marfa", to: folder, gate: gate) }
        #expect(await eventually { gate.workspace != nil })
        let workspace = try #require(gate.workspace)
        #expect(!workspace.path.hasPrefix(folder.path), "the export writes outside the folder")
        export.cancel()
        _ = await export.result
        #expect(!FileManager.default.fileExists(atPath: workspace.path))
        #expect(try contents(folder) == [other.lastPathComponent])
        #expect(try Data(contentsOf: other) == Data([9]))
    }

    @Test func aServerThatDoesNotAnswerFailsInOneLineAndLeavesNoFile() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let down = FakeArchive(bytes: Array(archiveBytes()[..<700]), failure: URLError(.cannotConnectToHost))
        let failure = await #expect(throws: LibraryExport.Failure.self) {
            try await LibraryExport.export(from: down, serverName: "Castell Studio", to: folder)
        }
        #expect(failure?.message == "Couldn’t export. Castell Studio isn’t answering.")
        #expect(try contents(folder).isEmpty)
    }

    @Test func aSignInTheServerEndedAndAMissingPermissionAreToldApart() {
        #expect(LibraryExport.failure(MarfaServerCalls.Ending.keyRefused, serverName: "X").message.contains("Sign in again"))
        #expect(LibraryExport.failure(MarfaServerCalls.Ending.notPermitted, serverName: "X").message.contains("isn’t allowed"))
    }

    @Test func aFolderThatCannotBeWrittenToIsTold() async throws {
        let missing = URL.temporaryDirectory.appending(path: "nowhere-\(UUID())", directoryHint: .isDirectory)
        let failure = await #expect(throws: LibraryExport.Failure.self) {
            try await LibraryExport.export(from: FakeArchive(), serverName: "X", to: missing)
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
