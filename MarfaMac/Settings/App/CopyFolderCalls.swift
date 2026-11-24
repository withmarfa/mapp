import Foundation
import Marfa

/// The Folders page's calls over the open working copy, which owns a folder's writes: it checks a change against the
/// folder it holds, sends it at once and queues nothing. A folder is held by a pin, as the copy's slice leaves every
/// `system.*` type out; the engine keeps it out of the library.
///
/// A pin is taken only to show a folder the copy does not hold yet, one at a time, since a pin made while another read
/// runs ends that read. A pin stays until Stop Syncing: each is one record and its edges, so they are bounded by the
/// number of folders.
actor CopyFolderCalls: FolderCalls {
    /// Nil where no copy of a Marfa server is open, as with the sample library.
    nonisolated let copy: WorkingCopy?
    /// The folders seen revoked, which are never pinned again.
    private var revoked: Set<String> = []
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(copy: WorkingCopy?) {
        self.copy = copy
    }

    func settings(of id: String) async throws(OwnerFailure) -> FolderSettingsReading {
        let copy = try held()
        await enter()
        defer { leave() }
        guard !revoked.contains(id) else { throw .notFound }
        return try await run {
            if try await Self.retrying({ try await copy.items.folder(id) }) == nil {
                _ = try await Self.retrying { try await copy.pin(id) }
            }
            guard let folder = try await Self.retrying({ try await copy.items.folder(id) }) else {
                throw MarfaError.notFound(code: "not_held", message: "", server: nil)
            }
            let reading = FolderSettingsReading(folder)
            if reading.isStopped { revoked.insert(id) }
            return reading
        }
    }

    func change(_ id: String, _ change: FolderSettingChange, baseVersion: Int64) async throws(OwnerFailure) -> FolderSettingsReading {
        let copy = try held()
        return try await run {
            FolderSettingsReading(try await MarfaEngine.asking { try await copy.changeFolder(id, change.change, baseVersion: baseVersion) })
        }
    }

    func stopSyncing(_ id: String) async throws(OwnerFailure) {
        let copy = try held()
        await enter()
        defer { leave() }
        try await run {
            _ = try await MarfaEngine.asking { try await copy.revokeFolder(id) }
            revoked.insert(id)
            // A revoked folder is not followed, so the copy need not hold it.
            _ = try? await copy.unpin(id)
        }
    }

    private func held() throws(OwnerFailure) -> WorkingCopy {
        guard let copy else { throw .unsupported }
        return copy
    }

    /// Lets one read, pin or stop run at a time.
    private func enter() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func leave() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
    }

    /// Asks once more where the copy's pins or reach changed under the read, as another pin does.
    private static func retrying<Value>(_ work: () async throws -> Value) async throws -> Value {
        do {
            return try await MarfaEngine.asking(work)
        } catch let MarfaError.streamIncomplete(reason, _, _) where reason == "local_copy_changed" {
            return try await MarfaEngine.asking(work)
        }
    }

    private func run<Value>(_ work: () async throws -> Value) async throws(OwnerFailure) -> Value {
        do { return try await work() } catch { throw ClientOwnerCalls.failure(error) }
    }
}
