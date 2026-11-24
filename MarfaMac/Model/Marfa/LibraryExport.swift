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

/// Closing the gate lets the main actor cancel an export without waiting on the disk. A move that has passed the gate's
/// check can still finish.
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
}

/// Export Everything: the whole library from the server into a folder the person chose. It needs the server, since the
/// copy on this Mac holds what is cached and not what an archive must hold. The folder is opened once, and from then on
/// reached through that descriptor for publishing, even if the folder's path changes. The export writes and checks the
/// archive through the same open file descriptor (`Staging` and `ArchiveCheck`).
nonisolated enum LibraryExport {
    /// Why an export did not finish, as one line, and whether it was because the server did not answer.
    struct Failure: Error, Equatable {
        let message: String
        var unreachable = false
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
    /// not a whole archive the app can check and, where `instance` is given, for an archive of another Marfa. Cancelling
    /// the task or closing `gate` stops the export at its next cancellation check.
    @concurrent static func export(
        from source: any ArchiveSource, serverName: String, to folder: URL, now: Date = .now, instance: String? = nil,
        gate: ExportGate = ExportGate()
    ) async throws(Failure) -> Exported {
        let cannotWrite = Failure(message: String(localized: "Couldn’t export. The app can’t write to that folder."))
        let destination = open(folder.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard destination >= 0 else { throw cannotWrite }
        defer { close(destination) }
        guard let staging = Staging.make(for: folder, destination: destination) else { throw cannotWrite }
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

    private struct Incomplete: Error {}
    private struct Uncheckable: Error {}
    private struct OtherMarfa: Error {}

    /// Moves the whole archive into the folder under the first free name. The move refuses a name that is taken, so a file
    /// another export or another app put there in the meantime is never replaced.
    private static func publish(_ staging: Staging, into destination: Int32, server: String, on date: Date, gate: ExportGate) throws -> String {
        for number in 1...10_000 {
            let name = fileName(for: server, on: date, number: number)
            try gate.checkOpen()
            let code = staging.move(into: destination, as: name)
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

/// The file an export writes before its archive is whole, made with `O_EXCL` and held open from then on. It is made in a
/// private directory the system gives on the folder's volume, or, where the system gives none there, as a hidden file in
/// the folder itself.
nonisolated private final class Staging: Sendable {
    let file: Int32
    /// The private directory, where the file is in one.
    let workspace: URL?
    /// The directory the file is in: the private directory, or the folder.
    private let directory: Int32
    private let name: String

    private init(file: Int32, directory: Int32, name: String, workspace: URL?) {
        self.file = file
        self.directory = directory
        self.name = name
        self.workspace = workspace
    }

    static func make(for folder: URL, destination: Int32) -> Staging? {
        let flags = O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC
        var target = stat()
        guard fstat(destination, &target) == 0 else { return nil }
        if let workspace = try? FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: folder, create: true)
        {
            let directory = open(workspace.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            var info = stat()
            // A private directory on another volume could not move the archive into the folder in one step.
            if directory >= 0, fstat(directory, &info) == 0, info.st_dev == target.st_dev {
                let file = openat(directory, "export.tar", flags, 0o644)
                if file >= 0 { return Staging(file: file, directory: directory, name: "export.tar", workspace: workspace) }
            }
            if directory >= 0 { close(directory) }
            rmdir(workspace.path)
        }
        let directory = dup(destination)
        guard directory >= 0 else { return nil }
        let name = ".Marfa export \(UUID().uuidString).partial"
        let file = openat(directory, name, flags, 0o644)
        guard file >= 0 else {
            close(directory)
            return nil
        }
        return Staging(file: file, directory: directory, name: name, workspace: nil)
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

    /// Moves the file into `destination` as `final`, refusing a name that is taken, and answers 0 or the error's code.
    func move(into destination: Int32, as final: String) -> Int32 {
        guard holdsOwnFile() else { return ENOENT }
        return renameatx_np(directory, name, destination, final, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
    }

    func end() {
        if holdsOwnFile() { unlinkat(directory, name, 0) }
        close(file)
        close(directory)
        if let workspace { rmdir(workspace.path) }
    }

    /// Whether the file's name in its directory is still the file this export holds open.
    private func holdsOwnFile() -> Bool {
        var named = stat()
        var held = stat()
        return fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0 && fstat(file, &held) == 0
            && named.st_dev == held.st_dev && named.st_ino == held.st_ino
    }
}

/// Reads an archive back from the file it was written to, through the descriptor the export holds, and says whether it is
/// a whole archive the app can check: plain ustar entries only; `manifest.json` first, naming the Marfa it is of; then the
/// six line files in the order the server writes them (`archive/archive-entries`), each one gzip stream that inflates to
/// its end with its checksum and size whole; then a `blobs/<hex>` entry, named by the hex of a SHA-256 hash, for each file
/// the manifest counts in `blob_count`; and the end of the tar, with only zeros after it. Malformed input is a refusal,
/// never a trap: every offset and count is checked.
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
        let blobCount: UInt64
        enum CodingKeys: String, CodingKey {
            case format, instanceId = "instance_id", fileCount = "file_count", blobCount = "blob_count"
        }
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
        var lines = lineFiles[...]
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
            } else if let line = lines.first {
                guard entry.name == line, inflates(file, from: offset, count: entry.size) else { throw .notWhole }
                lines.removeFirst()
            } else {
                guard isBlob(entry.name), blobs.insert(entry.name).inserted else { throw .notWhole }
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

    /// Whether the `count` bytes at `offset` are exactly one gzip stream: zlib inflates it to its end and checks the
    /// trailer's CRC and size before it says the stream ended, and nothing may follow it.
    private static func inflates(_ file: Int32, from offset: UInt64, count: UInt64) -> Bool {
        guard count > 0, let start = off_t(exactly: offset) else { return false }
        var stream = z_stream()
        // 15 window bits, plus 16 for a gzip header and trailer.
        guard inflateInit2_(&stream, 31, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return false }
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
            guard readFully(file, UnsafeMutableRawBufferPointer(rebasing: input[0..<size]), at: position) else { return false }
            position += off_t(size)
            left -= UInt64(size)
            stream.next_in = input.baseAddress!.assumingMemoryBound(to: Bytef.self)
            stream.avail_in = uInt(size)
            repeat {
                stream.next_out = output.baseAddress!.assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(chunk)
                let status = inflate(&stream, Z_NO_FLUSH)
                if status == Z_STREAM_END { return left == 0 && stream.avail_in == 0 }
                // A buffer error with no input left only asks for more.
                guard status == Z_OK || (status == Z_BUF_ERROR && stream.avail_in == 0) else { return false }
                if status == Z_BUF_ERROR { break }
            } while stream.avail_in > 0 || stream.avail_out == 0
        }
        return false
    }
}
