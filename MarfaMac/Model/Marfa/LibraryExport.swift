import Foundation
import Marfa
import MarfaAPI
import OpenAPIRuntime
import Synchronization

/// Where an export's bytes come from: the server's archive, in pieces.
nonisolated protocol ArchiveSource: Sendable {
    /// Gives each piece of the archive to `write`, in order, and returns once it has all been given.
    func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws
}

/// The server's `GET /export` through the package's client: the items, their metadata, their edges and their files, as an
/// archive the server's own restore reads.
nonisolated struct MarfaArchiveSource: ArchiveSource {
    let calls: MarfaServerCalls

    func stream(into write: @Sendable ([UInt8]) throws -> Void) async throws {
        let client = try calls.client()
        let body = try await client.exportArchive(query: .init(format: .archive, files: true)).ok.body.applicationXTar
        for try await chunk in body { try write(Array(chunk)) }
    }
}

/// What lets one export publish its archive. Whoever stops the export closes it, and the move into the folder runs under
/// the same lock, so once `close()` has returned the export can no longer publish.
nonisolated final class ExportGate: Sendable {
    private struct State {
        var open = true
        var workspace: URL?
    }

    private let state = Mutex(State())

    var isClosed: Bool { state.withLock { !$0.open } }

    /// The export's private directory, while it has one.
    var workspace: URL? { state.withLock { $0.workspace } }

    func close() {
        state.withLock { $0.open = false }
    }

    /// Takes `workspace` as the export's private directory, or answers false where the gate is already closed.
    func hold(_ workspace: URL) -> Bool {
        state.withLock {
            guard $0.open else { return false }
            $0.workspace = workspace
            return true
        }
    }

    /// Runs `body` only while the gate is open and the task is not cancelled.
    func publish<T>(_ body: () throws -> T) throws -> T {
        try state.withLock {
            guard $0.open, !Task.isCancelled else { throw CancellationError() }
            return try body()
        }
    }

    /// Removes the export's private directory, once, whoever asks first.
    func removeWorkspace() {
        state.withLock {
            guard let workspace = $0.workspace else { return }
            try? FileManager.default.removeItem(at: workspace)
            $0.workspace = nil
        }
    }
}

/// Export Everything: the whole library from the server into a folder the person chose. It needs the server, since the
/// copy on this Mac holds what is cached and not what an archive must hold. Each export writes into a private directory
/// the system makes for it on the folder's volume, checks that what arrived is a whole archive, and moves it into the
/// folder without replacing a file. It never removes anything in the folder.
nonisolated enum LibraryExport {
    /// Why an export did not finish, as one line.
    struct Failure: Error, Equatable {
        let message: String
    }

    /// A finished export: its file, the Marfa it holds, and how many files the archive names without carrying their bytes.
    struct Exported: Equatable, Sendable {
        let file: URL
        let instance: String
        let notCarried: Int
    }

    /// The archive's name: the server's name and the day, with `number` added from the second on.
    static func fileName(for server: String, on date: Date, number: Int = 1) -> String {
        let day = date.formatted(.iso8601.year().month().day())
        let base = "\(server.replacingOccurrences(of: "/", with: "-")) \(day)"
        return number > 1 ? "\(base) \(number).tar" : "\(base).tar"
    }

    /// Writes the archive into `folder` and returns it. Throws `Failure` with the line to show, also for a stream that is
    /// not a whole archive and, where `instance` is given, for an archive of another Marfa. Cancelling the task or closing
    /// `gate` stops the export and publishes nothing.
    @concurrent static func export(
        from source: any ArchiveSource, serverName: String, to folder: URL, now: Date = .now, instance: String? = nil,
        gate: ExportGate = ExportGate()
    ) async throws(Failure) -> Exported {
        let manager = FileManager.default
        guard
            let workspace = try? manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: folder, create: true)
        else {
            throw Failure(message: String(localized: "Couldn’t export. The app can’t write to that folder."))
        }
        guard gate.hold(workspace) else {
            try? manager.removeItem(at: workspace)
            throw failure(CancellationError(), serverName: serverName)
        }
        defer { gate.removeWorkspace() }
        let partial = workspace.appending(path: "export.tar")
        let descriptor = open(partial.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            throw Failure(message: String(localized: "Couldn’t export. The app can’t write to that folder."))
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        let check = Mutex(ArchiveCheck())
        do {
            try await source.stream { piece in
                try Task.checkCancellation()
                check.withLock { $0.see(piece) }
                try handle.write(contentsOf: piece)
            }
            try handle.synchronize()
            try handle.close()
            guard let archive = check.withLock({ $0.whole }) else { throw Incomplete() }
            if let instance, archive.instance != instance { throw OtherMarfa() }
            let file = try gate.publish { try publish(partial, in: folder, server: serverName, on: now) }
            return Exported(file: file, instance: archive.instance, notCarried: archive.notCarried)
        } catch {
            try? handle.close()
            throw failure(error, serverName: serverName)
        }
    }

    private struct Incomplete: Error {}
    private struct OtherMarfa: Error {}

    /// Moves a whole archive to the first free name. The move refuses a name that is taken, so a file another export or
    /// another app put there in the meantime is never replaced.
    private static func publish(_ partial: URL, in folder: URL, server: String, on date: Date) throws -> URL {
        for number in 1...10_000 {
            let final = folder.appending(path: fileName(for: server, on: date, number: number))
            if renamex_np(partial.path, final.path, UInt32(RENAME_EXCL)) == 0 { return final }
            guard errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        throw POSIXError(.EEXIST)
    }

    /// The line saying how many files an archive lacks, or nil where it carries every file it names.
    static func lacking(_ exported: Exported, serverName: String) -> String? {
        guard exported.notCarried > 0 else { return nil }
        return String(AttributedString(localized: "It lacks ^[\(exported.notCarried) file](inflect: true) \(serverName) couldn’t send.").characters)
    }

    /// The line for an error: the archive's, the folder's or the server's.
    static func failure(_ error: any Error, serverName: String) -> Failure {
        switch error {
        case is CancellationError:
            return Failure(message: String(localized: "Couldn’t export. The export was stopped."))
        case is Incomplete:
            return Failure(message: String(localized: "Couldn’t export. \(serverName) sent an archive that isn’t whole, so it wasn’t saved."))
        case is OtherMarfa:
            return Failure(message: String(localized: "Couldn’t export. \(serverName) sent another Marfa’s archive, so it wasn’t saved."))
        default:
            break
        }
        if error is CocoaError || (error as NSError).domain == NSPOSIXErrorDomain {
            return Failure(message: String(localized: "Couldn’t export. The app couldn’t write to that folder."))
        }
        let underlying = (error as? ClientError)?.underlyingError ?? error
        let ending = (error as? MarfaServerCalls.Ending)
            ?? (underlying is URLError ? .unreachable : MarfaServerCalls.ending(error))
        switch ending {
        case .unreachable:
            return Failure(message: String(localized: "Couldn’t export. \(serverName) isn’t answering."))
        case .keyRefused:
            return Failure(message: String(localized: "Couldn’t export. Sign in again in Connection first."))
        case .notPermitted:
            return Failure(message: String(localized: "Couldn’t export. The app isn’t allowed to export \(serverName)."))
        case .notFound, .instanceChanged, .refused, .failed:
            return Failure(message: String(localized: "Couldn’t export. \(serverName) didn’t send the archive."))
        }
    }
}

/// Reads an archive's tar headers as it passes on its way to the file, and says whether what arrived is a whole archive:
/// `manifest.json` first, naming the Marfa it is of, then every entry a restore requires (`archive/restore-members`), a
/// `blobs/` entry for each file the manifest counts in `blob_count`, each entry at its whole size, and the end of the tar.
nonisolated struct ArchiveCheck: Sendable {
    /// What a whole archive says of itself.
    struct Whole: Equatable, Sendable {
        let instance: String
        /// The files it names in `file_count` and does not carry: those `files.ndjson.gz` marks `not_carried` or `lost`.
        let notCarried: Int
    }

    static let required: Set<String> = [
        "manifest.json", "files.ndjson.gz", "instance.ndjson.gz", "items.ndjson.gz", "versions.ndjson.gz",
        "edges.ndjson.gz", "rows.ndjson.gz",
    ]
    private static let block = 512
    /// A manifest holds a few counts and names; anything longer is not one.
    private static let manifestLimit = 1 << 20

    private struct Manifest: Decodable {
        let format: String
        let instanceId: String
        let fileCount: Int
        let blobCount: Int
        enum CodingKeys: String, CodingKey {
            case format, instanceId = "instance_id", fileCount = "file_count", blobCount = "blob_count"
        }
    }

    private var header: [UInt8] = []
    /// The bytes of the entry being passed that are still to come, its padding included.
    private var remaining: UInt64 = 0
    /// The manifest's bytes while they arrive, and how long it is.
    private var manifestBytes: [UInt8]?
    private var manifestSize = 0
    private var manifest: Manifest?
    private var names: Set<String> = []
    private var blobs = 0
    private var zeroBlocks = 0
    private var ended = false
    private var broken = false

    /// The archive, once every byte has been seen and it is whole; nil for anything short, damaged or not an archive.
    var whole: Whole? {
        guard ended, !broken, let manifest, manifest.format == "marfa-archive", !manifest.instanceId.isEmpty,
            Self.required.isSubset(of: names), blobs == manifest.blobCount
        else { return nil }
        return Whole(instance: manifest.instanceId, notCarried: max(manifest.fileCount - manifest.blobCount, 0))
    }

    mutating func see(_ piece: [UInt8]) {
        var rest = piece[...]
        while !rest.isEmpty, !broken, !ended {
            if remaining > 0 {
                let taken = Int(min(remaining, UInt64(rest.count)))
                if manifestBytes != nil {
                    let wanted = manifestSize - manifestBytes!.count
                    manifestBytes! += rest.prefix(min(wanted, taken))
                    if manifestBytes!.count == manifestSize { readManifest() }
                }
                rest = rest.dropFirst(taken)
                remaining -= UInt64(taken)
                continue
            }
            let wanted = Self.block - header.count
            header += rest.prefix(wanted)
            rest = rest.dropFirst(wanted)
            guard header.count == Self.block else { return }
            let block = header
            header = []
            readHeader(block)
        }
    }

    private mutating func readHeader(_ block: [UInt8]) {
        if block.allSatisfy({ $0 == 0 }) {
            zeroBlocks += 1
            ended = zeroBlocks == 2
            return
        }
        guard zeroBlocks == 0, Self.checksumHolds(block), let size = Self.size(block) else { return broken = true }
        remaining = (size + UInt64(Self.block - 1)) / UInt64(Self.block) * UInt64(Self.block)
        let kind = block[156]
        // A pax or GNU header describes the entry after it and is not an entry of the archive.
        guard kind == 0 || kind == UInt8(ascii: "0") else { return }
        let name = Self.name(block)
        if names.isEmpty {
            guard name == "manifest.json", size <= UInt64(Self.manifestLimit) else { return broken = true }
            manifestSize = Int(size)
            manifestBytes = []
            if size == 0 { readManifest() }
        }
        guard names.insert(name).inserted else { return broken = true }
        if name.hasPrefix("blobs/") { blobs += 1 }
    }

    private mutating func readManifest() {
        manifest = manifestBytes.flatMap { try? JSONDecoder().decode(Manifest.self, from: Data($0)) }
        manifestBytes = nil
        if manifest == nil { broken = true }
    }

    private static func name(_ block: [UInt8]) -> String {
        func text(_ range: Range<Int>) -> String {
            String(decoding: block[range].prefix { $0 != 0 }, as: UTF8.self)
        }
        let name = text(0..<100)
        let prefix = Array(block[257..<262]) == Array("ustar".utf8) ? text(345..<500) : ""
        return prefix.isEmpty ? name : "\(prefix)/\(name)"
    }

    /// The entry's size, in octal or, past what eleven octal digits hold, in base 256.
    private static func size(_ block: [UInt8]) -> UInt64? {
        let field = block[124..<136]
        if field.first! & 0x80 != 0 {
            guard field.dropFirst().prefix(3).allSatisfy({ $0 == 0 }) else { return nil }
            return field.suffix(8).reduce(0) { $0 << 8 | UInt64($1) }
        }
        let digits = String(decoding: field, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        return digits.isEmpty ? 0 : UInt64(digits, radix: 8)
    }

    /// Whether the header's sum matches its bytes, read with the sum's own field as spaces.
    private static func checksumHolds(_ block: [UInt8]) -> Bool {
        let field = String(decoding: block[148..<156], as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        guard let recorded = Int(field, radix: 8) else { return false }
        let sum = block.indices.reduce(0) { $0 + ((148..<156).contains($1) ? 32 : Int(block[$1])) }
        return sum == recorded
    }
}
