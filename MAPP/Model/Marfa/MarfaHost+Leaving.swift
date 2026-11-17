import Foundation
import Marfa

/// Leaving a copy: what the person agreed to lose with it, and ending its sign-in and, where it was discarded, the
/// copy itself.
extension MarfaHost {
    /// What the person agreed to lose when they chose to discard the copy: the changes they were shown, none where
    /// nothing waited, or, for a copy another version made, which the app cannot list, the count it held. Nil where
    /// they chose to keep it. The package removes a copy only when what it holds is what was read from it, so a copy
    /// whose changes were not shown is refused here, before anything is left.
    func agreedLoss(_ choice: DisconnectChoice?, of connection: MarfaConnection) throws(Problem) -> Agreed? {
        switch choice {
        case .keepCopy:
            return nil
        case nil:
            return .ids([])
        case .discardCopy(let shown?):
            return .ids(shown.ids)
        case .discardCopy(nil):
            if case .otherVersion(let held?) = state { return .count(held) }
            throw .cannotDiscard(folder: location.directory(for: connection).path)
        }
    }

    /// Removes the store when every change it holds that the server has not taken is one the person agreed to lose.
    /// The package then removes exactly the changes read here, and refuses if they changed since.
    nonisolated static func removeStore(_ store: URL, agreedToLose agreed: Agreed) async throws {
        let held: Marfa.UnsentWrites
        do {
            held = try await WorkingCopy.unsentWrites(in: store)
        } catch let error as MarfaError {
            switch error {
            case .readingHandle, .invalid: throw error
            default: throw MarfaError.unsentDiffers(path: store.path, unsent: nil, message: "")
            }
        } catch {
            throw MarfaError.unsentDiffers(path: store.path, unsent: nil, message: "")
        }
        guard agreed.covers(held.writes.map(\.id)) else {
            throw MarfaError.unsentDiffers(path: store.path, unsent: UInt64(held.writes.count), message: "")
        }
        try await WorkingCopy.remove(store: store, confirming: held)
    }

    /// Ends the sign-in, and removes the copy where it was discarded (`agreed` is the changes the person agreed
    /// to lose with it), once the copy is closed. A discarded copy is marked before anything is removed and
    /// unmarked only once it is gone or the package has refused it, so neither a removal that fails nor a quit
    /// part way lets it be opened again as it was.
    func finishLeaving(_ connection: MarfaConnection, agreed: Agreed?) async -> Problem? {
        if let agreed { markDiscarded(connection, agreed: agreed) }
        var signIn: String?
        var copy: String?
        var kept: CopyKept?
        var revoked = true
        do {
            revoked = try await signIns.signOut(of: connection)
        } catch {
            signIn = Self.message(error)
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
        if let kept { return .copyKept(kept, signIn: signIn) }
        if signIn != nil || copy != nil { return .notRemoved(signIn: signIn, copy: copy) }
        return revoked ? nil : .notRevoked
    }

    private var discarded: [String: Agreed] {
        (defaults.dictionary(forKey: Self.discardedKey) ?? [:]).compactMapValues(Agreed.init(stored:))
    }

    private func markDiscarded(_ connection: MarfaConnection, agreed: Agreed?) {
        var marks = defaults.dictionary(forKey: Self.discardedKey) ?? [:]
        marks[connection.address.absoluteString] = agreed?.stored
        defaults.set(marks, forKey: Self.discardedKey)
    }

    /// A copy the person discarded is removed before its address is opened again, or not opened at all.
    func clearDiscarded(_ connection: MarfaConnection) async throws(Problem) {
        guard let agreed = discarded[connection.address.absoluteString] else { return }
        switch await removeCopy(connection, agreed: agreed) {
        case .removed:
            markDiscarded(connection, agreed: nil)
        case .failed(let message):
            throw .notRemoved(signIn: nil, copy: message)
        case .kept(let reason):
            markDiscarded(connection, agreed: nil)
            throw .copyKept(reason, signIn: nil)
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
    /// reading its changes to removing it, so a discard never takes a copy from another copy of the app still
    /// writing it, and never loses a change the person was not shown: `agreed` is the changes they were. A copy
    /// that holds no more than those (a write was sent while the sheet was open, or the store is already gone
    /// from an earlier part-way removal) loses nothing the person did not agree to. A copy whose changes moved
    /// between the read and the removal is read and asked again, once.
    func removeCopy(_ connection: MarfaConnection, agreed: Agreed, retrying: Bool = false) async -> Removal {
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
        } catch MarfaError.unsentDiffers(_, let now?, _) {
            if !retrying { return await removeCopy(connection, agreed: agreed, retrying: true) }
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
