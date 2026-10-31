import Foundation
import Marfa

/// Leaving a copy: what the person agreed to lose with it, and removing its key and, where it was discarded, the
/// copy itself.
extension MarfaHost {
    /// The number of changes the person agreed to lose when they chose to discard the copy: the count they were
    /// shown, 0 where nothing waited. Nil where they chose to keep it. The package removes a copy only when this
    /// is its own count, so a copy whose count was not shown is refused here, before anything is left.
    func agreedLoss(_ choice: DisconnectChoice?, of connection: MarfaConnection) throws(Problem) -> UInt64? {
        switch choice {
        case .keepCopy:
            return nil
        case nil:
            return 0
        case .discardCopy(let shown?):
            return UInt64(shown.count)
        case .discardCopy(nil):
            // A copy another version made says how many it held, and the person was shown that.
            if case .otherVersion(let held?) = state { return held }
            throw .cannotDiscard(folder: location.directory(for: connection).path)
        }
    }

    /// Removes the key, and the copy where it was discarded (`agreed` is the number of changes the person agreed
    /// to lose with it), once the copy is closed. A discarded copy is marked before anything is removed and
    /// unmarked only once it is gone or the package has refused it, so neither a removal that fails nor a quit
    /// part way lets it be opened again as it was.
    func finishLeaving(_ connection: MarfaConnection, agreed: UInt64?) async -> Problem? {
        if let agreed { markDiscarded(connection, agreed: agreed) }
        var key: String?
        var copy: String?
        var kept: CopyKept?
        do {
            try await Self.offMain { [keys] in try keys.delete(for: connection) }
        } catch {
            key = Self.message(error)
        }
        if let agreed {
            switch await removeCopy(connection, agreed: agreed) {
            case .removed:
                markDiscarded(connection, agreed: nil)
            case .failed(let message):
                copy = message
            case .kept(let reason):
                markDiscarded(connection, agreed: nil)
                kept = reason
            }
        }
        if let kept { return .copyKept(kept, key: key) }
        return key == nil && copy == nil ? nil : .notRemoved(key: key, copy: copy)
    }

    private var discarded: [String: Int] {
        defaults.dictionary(forKey: Self.discardedKey) as? [String: Int] ?? [:]
    }

    private func markDiscarded(_ connection: MarfaConnection, agreed: UInt64?) {
        var marks = discarded
        marks[connection.address.absoluteString] = agreed.map { Int(clamping: $0) }
        defaults.set(marks, forKey: Self.discardedKey)
    }

    /// A copy the person discarded is removed before its address is opened again, or not opened at all.
    func clearDiscarded(_ connection: MarfaConnection) async throws(Problem) {
        guard let agreed = discarded[connection.address.absoluteString] else { return }
        switch await removeCopy(connection, agreed: UInt64(agreed)) {
        case .removed:
            markDiscarded(connection, agreed: nil)
        case .failed(let message):
            throw .notRemoved(key: nil, copy: message)
        case .kept(let reason):
            markDiscarded(connection, agreed: nil)
            throw .copyKept(reason, key: nil)
        }
    }

    enum Removal {
        case removed
        /// Still on disk, and still marked to go; the words are why.
        case failed(String)
        /// Still on disk, and no longer marked to go.
        case kept(CopyKept)
    }

    /// Has the package remove the copy and what it fetched. The package holds the copy's writer lock from
    /// counting its changes to removing it, so a discard never takes a copy from another copy of the app still
    /// writing it, and never loses a change the person was not shown: `agreed` is the number they were. A copy
    /// that holds no more than that (a write was sent while the sheet was open, or the store is already gone
    /// from an earlier part-way removal) loses nothing the person did not agree to, so it is asked again, once,
    /// with the number it holds.
    func removeCopy(_ connection: MarfaConnection, agreed: UInt64, retrying: Bool = false) async -> Removal {
        let directory = location.directory(for: connection)
        do {
            try await remover(location.store(for: connection), agreed)
            // The package removes the copy's files and leaves the folder that held them.
            try await Self.offMain {
                if FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.removeItem(at: directory)
                }
            }
            return .removed
        } catch MarfaError.readingHandle {
            return .failed(Words.inUse)
        } catch MarfaError.unsentDiffers(_, let now?, _, _) {
            if now <= agreed, !retrying { return await removeCopy(connection, agreed: now, retrying: true) }
            return .kept(.changed(now: now))
        } catch MarfaError.unsentDiffers {
            return .kept(.unreadable(folder: directory.path))
        } catch MarfaError.invalid {
            return .kept(.notMapps(folder: directory.path))
        } catch {
            return .failed(Self.message(error))
        }
    }
}
