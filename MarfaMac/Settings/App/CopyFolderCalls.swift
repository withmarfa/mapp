import Foundation
import Marfa

/// The Folders page's calls over the open working copy, which owns a folder's writes: it checks a change against the
/// folder it holds, sends it at once and queues nothing. A folder is held by a pin, as the copy's slice leaves every
/// `system.*` type out; the engine keeps it out of the library.
nonisolated struct CopyFolderCalls: FolderCalls {
    /// Nil where no copy of a Marfa server is open, as with the sample library.
    let copy: WorkingCopy?

    func settings(of id: String) async throws(OwnerFailure) -> FolderSettingsReading {
        let copy = try held()
        return try await Self.run {
            _ = try await MarfaEngine.asking { try await copy.pin(id) }
            guard let folder = try await copy.items.folder(id) else { throw MarfaError.notFound(code: "not_held", message: "", server: nil) }
            return FolderSettingsReading(folder)
        }
    }

    func change(_ id: String, _ change: FolderSettingChange, baseVersion: Int64) async throws(OwnerFailure) -> FolderSettingsReading {
        let copy = try held()
        return try await Self.run {
            FolderSettingsReading(try await MarfaEngine.asking { try await copy.changeFolder(id, change.change, baseVersion: baseVersion) })
        }
    }

    func stopSyncing(_ id: String) async throws(OwnerFailure) {
        let copy = try held()
        try await Self.run {
            _ = try await MarfaEngine.asking { try await copy.revokeFolder(id) }
            // A stopped folder is not followed, so the copy need not hold it.
            _ = try? await copy.unpin(id)
        }
    }

    private func held() throws(OwnerFailure) -> WorkingCopy {
        guard let copy else { throw .unsupported }
        return copy
    }

    private static func run<Value>(_ work: () async throws -> Value) async throws(OwnerFailure) -> Value {
        do { return try await work() } catch { throw ClientOwnerCalls.failure(error) }
    }
}
