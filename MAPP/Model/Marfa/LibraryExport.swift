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
/// copy on this Mac holds what is cached and not what an archive must hold. The archive is written beside its final
/// name and moved into place only once it is whole, so a failed export leaves no file that looks complete.
nonisolated enum LibraryExport {
    /// Why an export did not finish, as one line.
    struct Failure: Error, Equatable {
        let message: String
    }

    /// The archive's name: the server's name and the day, with a number added where the folder already holds one.
    static func fileName(for server: String, on date: Date, existing: (String) -> Bool) -> String {
        let day = date.formatted(.iso8601.year().month().day())
        let base = "\(server.replacingOccurrences(of: "/", with: "-")) \(day)"
        var name = "\(base).tar"
        var number = 2
        while existing(name) {
            name = "\(base) \(number).tar"
            number += 1
        }
        return name
    }

    /// Writes the archive into `folder` and returns the file. Throws `Failure` with the line to show.
    @concurrent static func export(
        from source: any ArchiveSource, serverName: String, to folder: URL, now: Date = .now
    ) async throws(Failure) -> URL {
        let manager = FileManager.default
        let name = fileName(for: serverName, on: now) { manager.fileExists(atPath: folder.appending(path: $0).path) }
        let final = folder.appending(path: name)
        let partial = folder.appending(path: name + ".partial")
        guard manager.createFile(atPath: partial.path, contents: nil), let handle = try? FileHandle(forWritingTo: partial) else {
            throw Failure(message: String(localized: "Couldn’t export. MAPP can’t write to that folder."))
        }
        do {
            try await source.stream { try handle.write(contentsOf: $0) }
            try handle.close()
            try manager.moveItem(at: partial, to: final)
            return final
        } catch {
            try? handle.close()
            try? manager.removeItem(at: partial)
            throw failure(error, serverName: serverName)
        }
    }

    /// The line for an error: the server's state, or the folder's.
    static func failure(_ error: any Error, serverName: String) -> Failure {
        if error is CocoaError || (error as NSError).domain == NSPOSIXErrorDomain {
            return Failure(message: String(localized: "Couldn’t export. MAPP couldn’t write to that folder."))
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
            return Failure(message: String(localized: "Couldn’t export. MAPP isn’t allowed to export \(serverName)."))
        case .notFound, .instanceChanged, .refused, .failed:
            return Failure(message: String(localized: "Couldn’t export. \(serverName) didn’t send the archive."))
        }
    }
}
