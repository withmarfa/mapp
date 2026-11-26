import Foundation
import Marfa

/// Which copy an address opens. A Marfa is known by the instance it says it is, read without a sign-in, so one typed
/// two ways or moved to another address keeps its copy, and another at an address used before gets its own. A sign-in
/// stays with its origin: the copy is opened with the new address's own, and the package asks which instance answers
/// before it sends that copy anything.
extension MarfaHost {
    /// The folder `connection` should open, for the instance its server says it is. Nil `instance`, where the server
    /// did not say, finds only the copy the origin already has.
    func plannedFolder(for connection: MarfaConnection, instance: String?) async -> String {
        let resolved = location.directory(for: connection).lastPathComponent
        let exists = FileManager.default.fileExists(atPath: location.directory(named: resolved).path)
        guard let instance else { return resolved }
        let held: String? = if let recorded = location.copies.instance(ofFolder: resolved) {
            recorded
        } else if exists {
            await learnInstance(ofFolder: resolved)
        } else {
            nil
        }
        if held == instance { return resolved }
        // A copy not yet filled, or one that cannot be read now, is the origin's own: it is never given to another.
        if held == nil, exists { return resolved }
        if let elsewhere = await folder(holding: instance, besides: resolved) { return elsewhere }
        if held == nil { return resolved }
        return location.newDirectory(for: connection, instance: instance).lastPathComponent
    }

    /// Records that `connection` opens `folder`, and gives back the record as it was, so a step that does not finish
    /// puts it back. Only a new folder takes the instance the server said: one already there is known by what its
    /// copy says.
    func place(_ connection: MarfaConnection, in folder: String, instance: String?) throws(Problem) -> MarfaCopies.Record {
        let earlier = location.copies.current
        let isNew = !FileManager.default.fileExists(atPath: location.directory(named: folder).path)
        do {
            try location.copies.change { record in
                record.origins[MarfaCopies.origin(of: connection)] = folder
                if let instance, isNew, record.instances[folder] == nil { record.instances[folder] = instance }
            }
        } catch {
            throw .unavailable(message: Words.copyCouldNotBeOpened)
        }
        copiesRevision += 1
        return earlier
    }

    func restorePlacement(_ earlier: MarfaCopies.Record) {
        location.copies.restore(earlier)
        copiesRevision += 1
    }

    /// Records the copy `source` opened for `connection`, and the instance the copy says it holds, read offline.
    func recordCopy(of connection: MarfaConnection, from source: any ItemSource) async {
        let folder = location.directory(for: connection).lastPathComponent
        let instance = await source.instanceID()
        try? location.copies.change { record in
            record.origins[MarfaCopies.origin(of: connection)] = folder
            if let instance { record.instances[folder] = instance }
        }
        copiesRevision += 1
    }

    /// Another folder whose copy holds `instance`: one recorded, then one read now from a copy not yet recorded.
    private func folder(holding instance: String, besides own: String) async -> String? {
        let present = Set(location.folders())
        if let recorded = location.copies.folders(holding: instance).first(where: { $0 != own && present.contains($0) }) {
            return recorded
        }
        let known = location.copies.current.instances
        for folder in present.sorted() where folder != own && known[folder] == nil {
            if await learnInstance(ofFolder: folder) == instance { return folder }
        }
        return nil
    }

    /// Reads the instance a copy holds without taking it from whoever writes it. A copy that cannot be read says none.
    private func learnInstance(ofFolder folder: String) async -> String? {
        guard let instance = await Self.instance(in: location.store(in: folder)) else { return nil }
        try? location.copies.change { $0.instances[folder] = instance }
        copiesRevision += 1
        return instance
    }

    nonisolated static func instance(in store: URL) async -> String? {
        guard FileManager.default.fileExists(atPath: store.path), let copy = try? await WorkingCopy.openReader(store: store)
        else { return nil }
        let status = try? await copy.status()
        await copy.close()
        return status?.instanceId
    }

    // MARK: Other copies of this Marfa

    /// The other copies of the Marfa `connection` opens that this Mac holds: one its origin made under its other
    /// spelling, and one recorded as the same instance. A copy the person discarded is not among them.
    func otherCopies(of connection: MarfaConnection) -> [String] {
        let primary = location.directory(for: connection).lastPathComponent
        let present = Set(location.folders())
        let instance = location.copies.instance(ofFolder: primary)
        // A spelling's copy known to hold another instance is that instance's, never sent to this one.
        var others = location.otherSpellings(of: connection).filter { folder in
            guard let instance, let held = location.copies.instance(ofFolder: folder) else { return true }
            return held == instance
        }
        if let instance {
            others += location.copies.folders(holding: instance).filter { $0 != primary && present.contains($0) }
        }
        let discardedFolders = Set(discarded.keys)
        var seen = Set<String>()
        return others.filter { !discardedFolders.contains($0) && seen.insert($0).inserted }
    }

    /// Sends what waits in the other copies of this Marfa, each from its own store and to the instance it was made
    /// against, with this address's sign-in. Nothing is merged: a copy whose queue is then empty is removed, as its
    /// removal checks again, and one that still holds changes stays where it is and the person is told once a run.
    func sendOtherCopies(of connection: MarfaConnection, from source: any ItemSource) {
        let folders = otherCopies(of: connection)
        guard !folders.isEmpty, sendingOthers == nil else { return }
        let stores = folders.map { location.store(in: $0) }
        sendingOthers = Task { [weak self, signIns] in
            defer { if let self, self.connection == connection { self.sendingOthers = nil } }
            guard let server = try? await Self.offMain({ try signIns.server(for: connection) }) else { return }
            for store in stores {
                guard !Task.isCancelled else { return }
                let outcome = await Self.send(store, to: server)
                guard let self, self.connection == connection else { return }
                switch outcome {
                case .removed:
                    let folder = store.deletingLastPathComponent().lastPathComponent
                    try? self.location.copies.change { $0.instances[folder] = nil }
                    self.copiesRevision += 1
                case .waiting(let count):
                    guard count > 0, self.toldOtherCopies.insert(store.path).inserted else { continue }
                    self.notices.tell(
                        String(localized: "Changes Still Waiting"),
                        String(localized: "\(count) changes made at another address for this Marfa are kept on this Mac in \(store.deletingLastPathComponent().path) and are sent the next time the app connects."))
                }
            }
        }
    }

    enum OtherCopyOutcome: Equatable {
        case removed
        /// Kept, holding `count` changes the server has not taken; 0 where they could not be read.
        case waiting(Int)
    }

    /// Opens another copy with `server`, sends its queue once, takes the answers, and removes the copy only where its
    /// queue is then empty. A copy another program holds, one another version made and one that cannot be read stay.
    nonisolated static func send(_ store: URL, to server: Server) async -> OtherCopyOutcome {
        guard let copy = try? await WorkingCopy.open(store: store, server: server) else { return .waiting(0) }
        guard copy.handle == .writer else {
            await copy.close()
            return .waiting(0)
        }
        _ = try? await copy.queue.drain()
        _ = try? await copy.queue.takeAnswered()
        await copy.close()
        guard let unsent = try? await WorkingCopy.unsentWrites(in: store) else { return .waiting(0) }
        guard unsent.writes.isEmpty else { return .waiting(unsent.writes.count) }
        do {
            try await WorkingCopy.remove(store: store, confirming: unsent)
            try await offMain { try removeIfEmpty(store.deletingLastPathComponent()) }
            return .removed
        } catch {
            return .waiting(0)
        }
    }
}
