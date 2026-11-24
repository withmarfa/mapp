import Foundation
import Marfa
import MarfaAPI
import OpenAPIRuntime

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

/// Export Everything: the whole library from the server into a folder the person chose. It needs the server, since the
/// copy on this Mac holds what is cached and not what an archive must hold. Each export writes its own temporary file in
/// the folder, made new and never truncating one already there, and moves it to its final name only once it is whole,
/// without replacing a file of that name. A failed or stopped export removes only its own temporary file.
nonisolated enum LibraryExport {
    /// Why an export did not finish, as one line.
    struct Failure: Error, Equatable {
        let message: String
    }

    /// The archive's name: the server's name and the day, with `number` added from the second on.
    static func fileName(for server: String, on date: Date, number: Int = 1) -> String {
        let day = date.formatted(.iso8601.year().month().day())
        let base = "\(server.replacingOccurrences(of: "/", with: "-")) \(day)"
        return number > 1 ? "\(base) \(number).tar" : "\(base).tar"
    }

    /// The temporary file of the export `id`, hidden in `folder` until the archive is whole.
    static func partialFile(in folder: URL, id: UUID) -> URL {
        folder.appending(path: ".Marfa export \(id.uuidString).partial")
    }

    /// Writes the archive into `folder` and returns the file. Throws `Failure` with the line to show. A cancelled task
    /// stops the export at its next piece.
    @concurrent static func export(
        from source: any ArchiveSource, serverName: String, to folder: URL, now: Date = .now, id: UUID = UUID()
    ) async throws(Failure) -> URL {
        let partial = partialFile(in: folder, id: id)
        let descriptor = open(partial.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            throw Failure(message: String(localized: "Couldn’t export. The app can’t write to that folder."))
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try await source.stream { piece in
                try Task.checkCancellation()
                try handle.write(contentsOf: piece)
            }
            try Task.checkCancellation()
            try handle.close()
            return try publish(partial, in: folder, server: serverName, on: now)
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: partial)
            throw failure(error, serverName: serverName)
        }
    }

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

    /// The line for an error: the server's state, or the folder's.
    static func failure(_ error: any Error, serverName: String) -> Failure {
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
