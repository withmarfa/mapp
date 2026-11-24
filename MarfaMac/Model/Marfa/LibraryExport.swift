import CryptoKit
import Foundation
import Marfa
import MarfaAPI
import OpenAPIRuntime
import Synchronization
import zlib

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

/// Closing the gate stops an export at its next check. The move into the folder runs while the gate is held, so once
/// `close()` returns no move is under way and none starts; on a local APFS or HFS+ volume that move is one quick rename.
nonisolated final class ExportGate: Sendable {
    private struct State {
        var open = true
        var workspace: URL?
    }

    private let state = Mutex(State())

    var isClosed: Bool { state.withLock { !$0.open } }

    /// The export's private directory, once it has one.
    var workspace: URL? { state.withLock { $0.workspace } }

    func close() {
        state.withLock { $0.open = false }
    }

    /// Takes `workspace` as the export's private directory, or answers false where the gate is already closed.
    func hold(_ workspace: URL?) -> Bool {
        state.withLock {
            guard $0.open else { return false }
            $0.workspace = workspace
            return true
        }
    }

    /// Throws where the gate is closed or the task cancelled, so the export stops.
    func checkOpen() throws {
        guard !isClosed, !Task.isCancelled else { throw CancellationError() }
    }

    /// Runs `move` only while the gate is open and holds the gate until it ends, so a close waits for it.
    func whileOpen(_ move: () -> Int32) throws -> Int32 {
        try state.withLock { current throws in
            guard current.open, !Task.isCancelled else { throw CancellationError() }
            return move()
        }
    }
}

/// The volume a folder is on, as an export judges it.
nonisolated struct ExportVolume: Equatable, Sendable {
    /// The file system's name, such as `apfs`, `hfs`, `msdos`, `exfat` or `smbfs`.
    var format: String
    var isLocal: Bool
    var supportsExclusiveRenaming: Bool
    var uuid: String?

    /// Whether an archive can be published there in one move that never replaces a file: a local APFS or HFS+ volume.
    var isAccepted: Bool {
        isLocal && supportsExclusiveRenaming && ["apfs", "hfs"].contains(format) && uuid != nil
    }

    /// The volume of the directory `descriptor` holds open, or nil where it can't be read.
    static func of(_ descriptor: Int32) -> ExportVolume? {
        var info = statfs()
        guard fstatfs(descriptor, &info) == 0 else { return nil }
        let format = withUnsafeBytes(of: info.f_fstypename) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard path.withUnsafeMutableBytes({ fcntl(descriptor, F_GETPATH, $0.baseAddress!) }) == 0 else { return nil }
        let place = path.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        let values = try? URL(filePath: place, directoryHint: .isDirectory)
            .resourceValues(forKeys: [.volumeSupportsExclusiveRenamingKey, .volumeUUIDStringKey])
        return ExportVolume(
            format: format, isLocal: info.f_flags & UInt32(MNT_LOCAL) != 0,
            supportsExclusiveRenaming: values?.volumeSupportsExclusiveRenaming == true, uuid: values?.volumeUUIDString)
    }
}

/// The folder Export Automatically writes to, as it was when chosen: its path, and its volume and inode, so a folder moved
/// or replaced since then is told apart from it.
nonisolated struct ExportFolder: Codable, Equatable, Sendable {
    let path: String
    let volume: String
    let inode: UInt64

    var url: URL { URL(filePath: path, directoryHint: .isDirectory) }
}

/// Export Everything: the whole library from the server into a folder the person chose. It needs the server, since the
/// copy on this Mac holds what is cached and not what an archive must hold. The folder must be on a local APFS or HFS+
/// volume. It is opened once, and from then on reached through that descriptor for publishing, even if the folder's path
/// changes. The export writes and checks the archive through the same open file descriptor (`Staging` and `ArchiveCheck`).
nonisolated enum LibraryExport {
    /// Why an export did not finish, as one line, and whether it was because the server did not answer.
    struct Failure: Error, Equatable {
        let message: String
        var unreachable = false

        static var cannotWrite: Failure { Failure(message: String(localized: "Couldn’t export. The app can’t write to that folder.")) }
        static var notOwnDisk: Failure { Failure(message: String(localized: "Choose a folder on this Mac’s own disk.")) }
        static var replaced: Failure {
            Failure(message: String(localized: "The export folder was moved or replaced. Choose it again."))
        }
    }

    /// Reads the volume of a folder's descriptor; tests give another.
    typealias VolumeReader = @Sendable (Int32) -> ExportVolume?

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

    /// Checks a folder chosen for Export Automatically as an export would, making and removing its private file, and
    /// answers what to record of it.
    @concurrent static func choose(_ folder: URL, volume: VolumeReader = ExportVolume.of) async -> Result<ExportFolder, Failure> {
        do throws(Failure) {
            let (destination, identity) = try open(folder, expecting: nil, volume: volume)
            defer { Darwin.close(destination) }
            try Staging.make(for: folder, destination: destination).end()
            return .success(identity)
        } catch {
            return .failure(error)
        }
    }

    /// Writes the archive into `folder` and returns it. Throws `Failure` with the line to show, also for a folder that is
    /// not on a local APFS or HFS+ volume or, where `expecting` is given, is no longer the folder it names; for a stream
    /// that is not a whole archive the app can check; and, where `instance` is given, for an archive of another Marfa.
    /// Cancelling the task or closing `gate` stops the export at its next check.
    @concurrent static func export(
        from source: any ArchiveSource, serverName: String, to folder: URL, expecting: ExportFolder? = nil, now: Date = .now,
        instance: String? = nil, gate: ExportGate = ExportGate(), volume: VolumeReader = ExportVolume.of
    ) async throws(Failure) -> Exported {
        let (destination, _) = try open(folder, expecting: expecting, volume: volume)
        defer { Darwin.close(destination) }
        let staging = try Staging.make(for: folder, destination: destination)
        defer { staging.end() }
        guard gate.hold(staging.workspace) else { throw failure(CancellationError(), serverName: serverName) }
        do {
            try await source.stream { piece in
                try gate.checkOpen()
                try staging.write(piece)
            }
            guard fsync(staging.file) == 0 else { throw posixError() }
            try gate.checkOpen()
            let archive: ArchiveCheck.Whole
            switch ArchiveCheck.verdict(of: staging.file, stop: { gate.isClosed || Task.isCancelled }) {
            case .whole(let whole): archive = whole
            case .notWhole: throw Incomplete()
            case .uncheckable: throw Uncheckable()
            }
            try gate.checkOpen()
            if let instance, archive.instance != instance { throw OtherMarfa() }
            let name = try publish(staging, into: destination, server: serverName, on: now, gate: gate)
            return Exported(file: folder.appending(path: name), instance: archive.instance, notCarried: archive.notCarried)
        } catch {
            throw failure(error, serverName: serverName)
        }
    }

    /// Opens `folder` as a directory, never through a link at its end, on a volume the export accepts. Where `expecting`
    /// is given, the directory must still be the one it names.
    private static func open(_ folder: URL, expecting: ExportFolder?, volume: VolumeReader) throws(Failure) -> (Int32, ExportFolder) {
        let destination = Darwin.open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard destination >= 0 else { throw expecting == nil ? .cannotWrite : .replaced }
        var info = stat()
        guard fstat(destination, &info) == 0 else {
            Darwin.close(destination)
            throw .cannotWrite
        }
        guard let read = volume(destination), read.isAccepted, let uuid = read.uuid else {
            Darwin.close(destination)
            throw .notOwnDisk
        }
        let identity = ExportFolder(path: folder.path, volume: uuid, inode: UInt64(info.st_ino))
        if let expecting, expecting.volume != identity.volume || expecting.inode != identity.inode {
            Darwin.close(destination)
            throw .replaced
        }
        return (destination, identity)
    }

    private struct Incomplete: Error {}
    private struct Uncheckable: Error {}
    private struct OtherMarfa: Error {}

    /// Moves the whole archive into the folder under the first free name. The move refuses a name that is taken, so a file
    /// another export or another app put there in the meantime is never replaced.
    private static func publish(_ staging: Staging, into destination: Int32, server: String, on date: Date, gate: ExportGate) throws -> String {
        for number in 1...10_000 {
            let name = fileName(for: server, on: date, number: number)
            let code = try staging.move(into: destination, as: name, gate: gate)
            if code == 0 { return name }
            guard code == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        }
        throw POSIXError(.EEXIST)
    }

    fileprivate static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    /// The line saying how many files an archive lacks, or nil where it carries every file it names.
    static func lacking(_ exported: Exported, serverName: String) -> String? {
        guard exported.notCarried > 0 else { return nil }
        return String(AttributedString(localized: "It lacks ^[\(exported.notCarried) file](inflect: true) \(serverName) couldn’t send.").characters)
    }

    /// The line for an error: the archive's, the folder's or the server's.
    static func failure(_ error: any Error, serverName: String) -> Failure {
        switch error {
        case let failure as Failure:
            return failure
        case is CancellationError:
            return Failure(message: String(localized: "Couldn’t export. The export was stopped."))
        case is Incomplete:
            return Failure(message: String(localized: "Couldn’t export. \(serverName) sent an archive that isn’t whole, so it wasn’t saved."))
        case is Uncheckable:
            return Failure(message: String(localized: "Couldn’t export. \(serverName) sent an archive the app can’t check, so it wasn’t saved."))
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
            return Failure(message: String(localized: "Couldn’t export. \(serverName) isn’t answering."), unreachable: true)
        case .keyRefused:
            return Failure(message: String(localized: "Couldn’t export. Sign in again in Connection first."))
        case .notPermitted:
            return Failure(message: String(localized: "Couldn’t export. The app isn’t allowed to export \(serverName)."))
        case .notFound, .instanceChanged, .refused, .failed:
            return Failure(message: String(localized: "Couldn’t export. \(serverName) didn’t send the archive."))
        }
    }
}

/// The file an export writes before its archive is whole, made with `O_EXCL` in a private directory the system gives on
/// the folder's volume, and held open from then on. The directory and the file are reached and removed only through
/// descriptors, never by path.
nonisolated private final class Staging: Sendable {
    let file: Int32
    let workspace: URL
    /// The private directory's parent, which the directory is removed through.
    private let parent: Int32
    /// The private directory.
    private let directory: Int32
    private static let name = "export.tar"

    private init(file: Int32, parent: Int32, directory: Int32, workspace: URL) {
        self.file = file
        self.parent = parent
        self.directory = directory
        self.workspace = workspace
    }

    /// Makes the file, refusing a folder whose private directory the system puts on another volume.
    static func make(for folder: URL, destination: Int32) throws(LibraryExport.Failure) -> Staging {
        var target = stat()
        guard fstat(destination, &target) == 0,
            let workspace = try? FileManager.default.url(
                for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: folder, create: true)
        else { throw .cannotWrite }
        // The system's directory of private directories can't be listed, only searched.
        let parent = open(workspace.deletingLastPathComponent().path, O_SEARCH | O_CLOEXEC)
        guard parent >= 0 else { throw .cannotWrite }
        let directory = openat(parent, workspace.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        var info = stat()
        let opened = directory >= 0 && fstat(directory, &info) == 0
        let file = opened && info.st_dev == target.st_dev
            ? openat(directory, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644) : -1
        guard file >= 0 else {
            if directory >= 0 { close(directory) }
            unlinkat(parent, workspace.lastPathComponent, AT_REMOVEDIR)
            close(parent)
            throw opened && info.st_dev != target.st_dev ? .notOwnDisk : .cannotWrite
        }
        return Staging(file: file, parent: parent, directory: directory, workspace: workspace)
    }

    func write(_ bytes: [UInt8]) throws {
        try bytes.withUnsafeBytes { raw in
            var done = 0
            while done < raw.count {
                let written = Darwin.write(file, raw.baseAddress! + done, raw.count - done)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw LibraryExport.posixError() }
                done += written
            }
        }
    }

    /// Moves the file into `destination` as `final`, refusing a name that is taken, and answers 0 or the error's code. The
    /// gate is checked last, after the file's own check.
    func move(into destination: Int32, as final: String, gate: ExportGate) throws -> Int32 {
        guard holdsOwnFile() else { return ENOENT }
        return try gate.whileOpen {
            renameatx_np(directory, Self.name, destination, final, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
        }
    }

    /// Removes the file and then the private directory, which fails harmlessly where anything else is in it.
    func end() {
        if holdsOwnFile() { unlinkat(directory, Self.name, 0) }
        close(file)
        close(directory)
        unlinkat(parent, workspace.lastPathComponent, AT_REMOVEDIR)
        close(parent)
    }

    /// Whether the file's name in the private directory is still the file this export holds open. The directory is the
    /// app's own, so another process of the same user changing it is out of scope.
    private func holdsOwnFile() -> Bool {
        var named = stat()
        var held = stat()
        return fstatat(directory, Self.name, &named, AT_SYMLINK_NOFOLLOW) == 0 && fstat(file, &held) == 0
            && named.st_dev == held.st_dev && named.st_ino == held.st_ino
    }
}

/// Reads an archive back from the file it was written to, through the descriptor the export holds, and says whether it is
/// a whole archive the app can check: plain ustar entries only; `manifest.json` first, naming the Marfa it is of; then the
/// six line files in the order the server writes them (`archive/archive-entries`), each one gzip stream that inflates to
/// its end with its checksum and size whole, holding as many lines as the manifest counts for it; then a `blobs/<hex>`
/// entry for each file the manifest counts in `blob_count`, its bytes hashing to the SHA-256 its name gives; and the end
/// of the tar, with only zeros after it. Malformed input is a refusal, never a trap: every offset and count is checked.
nonisolated enum ArchiveCheck {
    enum Verdict: Equatable {
        case whole(Whole)
        /// Short, damaged or not an archive.
        case notWhole
        /// A tar the app does not read: pax or GNU headers, or an entry neither a file nor a directory.
        case uncheckable
    }

    /// What a whole archive says of itself.
    struct Whole: Equatable, Sendable {
        let instance: String
        /// The files it names in `file_count` and does not carry: those `files.ndjson.gz` marks `not_carried` or `lost`.
        let notCarried: Int
    }

    static let lineFiles = [
        "files.ndjson.gz", "instance.ndjson.gz", "items.ndjson.gz", "versions.ndjson.gz", "edges.ndjson.gz", "rows.ndjson.gz",
    ]
    private static let block: UInt64 = 512
    /// A manifest holds a few counts and names; anything longer is not one.
    private static let manifestLimit: UInt64 = 1 << 20
    private static let chunk = 1 << 16

    private struct Manifest: Decodable {
        let format: String
        let instanceId: String
        let fileCount: UInt64
        let itemCount: UInt64
        let versionCount: UInt64
        let edgeCount: UInt64
        let rowCount: UInt64
        let blobCount: UInt64
        enum CodingKeys: String, CodingKey {
            case format, instanceId = "instance_id", fileCount = "file_count", itemCount = "item_count"
            case versionCount = "version_count", edgeCount = "edge_count", rowCount = "row_count", blobCount = "blob_count"
        }

        /// The lines the manifest counts in each line file, in the order of `lineFiles`; it counts `instance.ndjson.gz` by
        /// kind, not by line.
        var lines: [UInt64?] { [fileCount, nil, itemCount, versionCount, edgeCount, rowCount] }
    }

    private enum Refusal: Error {
        case notWhole, uncheckable
    }

    /// Reads `file` from its start. `stop` is asked before each entry, and a stop is a refusal.
    static func verdict(of file: Int32, stop: () -> Bool = { false }) -> Verdict {
        do {
            return .whole(try read(file, stop: stop))
        } catch .uncheckable {
            return .uncheckable
        } catch {
            return .notWhole
        }
    }

    private static func read(_ file: Int32, stop: () -> Bool) throws(Refusal) -> Whole {
        var info = stat()
        guard fstat(file, &info) == 0, info.st_size >= 0 else { throw .notWhole }
        let length = UInt64(info.st_size)
        var offset: UInt64 = 0
        var manifest: Manifest?
        var lines = lineFiles.indices[...]
        var blobs: Set<String> = []
        while true {
            if stop() { throw .notWhole }
            let header = try bytes(file, at: offset, count: block, length: length)
            offset = try add(offset, block)
            if header.allSatisfy({ $0 == 0 }) {
                guard try bytes(file, at: offset, count: block, length: length).allSatisfy({ $0 == 0 }) else { throw .notWhole }
                try zerosOnly(file, from: add(offset, block), length: length)
                break
            }
            let entry = try Entry(header)
            let end = try add(offset, entry.size)
            let next = try add(end, (block - end % block) % block)
            guard next <= length else { throw .notWhole }
            if entry.isDirectory {
                guard manifest != nil, entry.size == 0 else { throw .notWhole }
            } else if manifest == nil {
                guard entry.name == "manifest.json", entry.size <= manifestLimit else { throw .notWhole }
                let data = Data(try bytes(file, at: offset, count: entry.size, length: length))
                guard let read = try? JSONDecoder().decode(Manifest.self, from: data), read.format == "marfa-archive",
                    !read.instanceId.isEmpty, read.blobCount <= read.fileCount
                else { throw .notWhole }
                manifest = read
            } else if let line = lines.first, let manifest {
                guard entry.name == lineFiles[line], let counted = lineCount(file, from: offset, count: entry.size),
                    manifest.lines[line].map({ $0 == counted }) != false
                else { throw .notWhole }
                lines.removeFirst()
            } else {
                guard isBlob(entry.name), blobs.insert(entry.name).inserted,
                    hash(file, from: offset, count: entry.size, length: length) == String(entry.name.dropFirst(6))
                else { throw .notWhole }
            }
            offset = next
        }
        guard let manifest, lines.isEmpty, UInt64(blobs.count) == manifest.blobCount,
            let notCarried = Int(exactly: manifest.fileCount - manifest.blobCount)
        else { throw .notWhole }
        return Whole(instance: manifest.instanceId, notCarried: notCarried)
    }

    /// One ustar header: a regular file or a directory, with its name and size.
    private struct Entry {
        let name: String
        let size: UInt64
        let isDirectory: Bool

        init(_ header: [UInt8]) throws(Refusal) {
            guard Self.checksumHolds(header) else { throw .notWhole }
            guard header[257..<263].elementsEqual("ustar\u{0}".utf8), header[263..<265].elementsEqual("00".utf8) else {
                throw .uncheckable
            }
            switch header[156] {
            case 0, UInt8(ascii: "0"): isDirectory = false
            case UInt8(ascii: "5"): isDirectory = true
            default: throw .uncheckable
            }
            guard let size = Self.size(Array(header[124..<136])) else { throw .notWhole }
            self.size = size
            let base = try Self.text(header[0..<100])
            let prefix = try Self.text(header[345..<500])
            guard !base.isEmpty else { throw .notWhole }
            name = prefix.isEmpty ? base : "\(prefix)/\(base)"
        }

        private static func text(_ field: ArraySlice<UInt8>) throws(Refusal) -> String {
            guard let text = String(validating: field.prefix { $0 != 0 }, as: UTF8.self) else { throw .notWhole }
            return text
        }

        /// Octal digits ended by a NUL or a space or, past what eleven octal digits hold, base 256.
        private static func size(_ field: [UInt8]) -> UInt64? {
            if field[0] == 0x80 {
                guard field[1..<4].allSatisfy({ $0 == 0 }) else { return nil }
                return field[4..<12].reduce(0) { $0 << 8 | UInt64($1) }
            }
            return octal(field[...])
        }

        private static func octal(_ field: ArraySlice<UInt8>) -> UInt64? {
            let digits = field.prefix { (UInt8(ascii: "0")...UInt8(ascii: "7")).contains($0) }
            guard !digits.isEmpty, field.dropFirst(digits.count).allSatisfy({ $0 == 0 || $0 == UInt8(ascii: " ") }) else { return nil }
            return UInt64(String(decoding: digits, as: UTF8.self), radix: 8)
        }

        /// Whether the header's sum matches its bytes, read with the sum's own field as spaces.
        private static func checksumHolds(_ header: [UInt8]) -> Bool {
            guard let recorded = octal(header[148..<156].drop { $0 == UInt8(ascii: " ") }) else { return false }
            let sum = header.indices.reduce(UInt64(0)) { $0 + ((148..<156).contains($1) ? 32 : UInt64(header[$1])) }
            return sum == recorded
        }
    }

    /// Whether `name` is a `blobs/` entry named by the lowercase hex of a SHA-256 hash, as the server names them.
    private static func isBlob(_ name: String) -> Bool {
        guard name.hasPrefix("blobs/") else { return false }
        let hex = name.utf8.dropFirst(6)
        return hex.count == 64 && hex.allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains($0) }
    }

    private static func add(_ one: UInt64, _ other: UInt64) throws(Refusal) -> UInt64 {
        let (sum, overflow) = one.addingReportingOverflow(other)
        guard !overflow else { throw .notWhole }
        return sum
    }

    /// `count` bytes at `offset`, all within the file's `length`.
    private static func bytes(_ file: Int32, at offset: UInt64, count: UInt64, length: UInt64) throws(Refusal) -> [UInt8] {
        guard count <= length, offset <= length - count, let start = off_t(exactly: offset), let size = Int(exactly: count) else {
            throw .notWhole
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard buffer.withUnsafeMutableBytes({ readFully(file, $0, at: start) }) else { throw .notWhole }
        return buffer
    }

    /// Fills `buffer` from `offset`, answering false where the file ends first or a read fails.
    private static func readFully(_ file: Int32, _ buffer: UnsafeMutableRawBufferPointer, at offset: off_t) -> Bool {
        var done = 0
        while done < buffer.count {
            let read = pread(file, buffer.baseAddress! + done, buffer.count - done, offset + off_t(done))
            if read < 0, errno == EINTR { continue }
            guard read > 0 else { return false }
            done += read
        }
        return true
    }

    /// Whether everything from `offset` to the file's end is zero, as a tar may be padded after its end.
    private static func zerosOnly(_ file: Int32, from offset: UInt64, length: UInt64) throws(Refusal) {
        var position = offset
        while position < length {
            let count = min(length - position, UInt64(chunk))
            guard try bytes(file, at: position, count: count, length: length).allSatisfy({ $0 == 0 }) else { throw .notWhole }
            position += count
        }
    }

    /// The lowercase hex of the SHA-256 of the `count` bytes at `offset`, read in pieces, or nil where they can't be read.
    private static func hash(_ file: Int32, from offset: UInt64, count: UInt64, length: UInt64) -> String? {
        var hasher = SHA256()
        var position = offset
        let end = offset + count
        while position < end {
            let size = min(end - position, UInt64(chunk))
            guard let piece = try? bytes(file, at: position, count: size, length: length) else { return nil }
            hasher.update(data: piece)
            position += size
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The lines in the `count` bytes at `offset`, or nil where they are not exactly one gzip stream: zlib inflates it to
    /// its end and checks the trailer's CRC and size before it says the stream ended, and nothing may follow it. A line is
    /// a run of bytes other than a newline, as the server's restore counts them.
    private static func lineCount(_ file: Int32, from offset: UInt64, count: UInt64) -> UInt64? {
        guard count > 0, let start = off_t(exactly: offset) else { return nil }
        var lines: UInt64 = 0
        var inLine = false
        func countLines(_ produced: Int, in output: UnsafeMutableRawBufferPointer) {
            for byte in output[0..<produced] {
                if byte == UInt8(ascii: "\n") {
                    inLine = false
                } else if !inLine {
                    inLine = true
                    lines += 1
                }
            }
        }
        var stream = z_stream()
        // 15 window bits, plus 16 for a gzip header and trailer.
        guard inflateInit2_(&stream, 31, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }
        let input = UnsafeMutableRawBufferPointer.allocate(byteCount: chunk, alignment: 1)
        let output = UnsafeMutableRawBufferPointer.allocate(byteCount: chunk, alignment: 1)
        defer {
            input.deallocate()
            output.deallocate()
        }
        var position = start
        var left = count
        while left > 0 {
            let size = Int(min(left, UInt64(chunk)))
            guard readFully(file, UnsafeMutableRawBufferPointer(rebasing: input[0..<size]), at: position) else { return nil }
            position += off_t(size)
            left -= UInt64(size)
            stream.next_in = input.baseAddress!.assumingMemoryBound(to: Bytef.self)
            stream.avail_in = uInt(size)
            repeat {
                stream.next_out = output.baseAddress!.assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(chunk)
                let status = inflate(&stream, Z_NO_FLUSH)
                countLines(chunk - Int(stream.avail_out), in: output)
                if status == Z_STREAM_END { return left == 0 && stream.avail_in == 0 ? lines : nil }
                // A buffer error with no input left only asks for more.
                guard status == Z_OK || (status == Z_BUF_ERROR && stream.avail_in == 0) else { return nil }
                if status == Z_BUF_ERROR { break }
            } while stream.avail_in > 0 || stream.avail_out == 0
        }
        return nil
    }
}
