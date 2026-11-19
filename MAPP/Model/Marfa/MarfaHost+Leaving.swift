import Foundation
import Marfa

/// Leaving a copy: what the person agreed to lose with it, and ending its sign-in and, where it was discarded, the
/// copy itself.
extension MarfaHost {
    /// What the person agreed to lose when they chose to discard the copy: the changes they were shown, or none
    /// where nothing waited. Nil where they chose to keep it. The package removes a copy only when what it holds is
    /// what was read from it, so a copy whose changes were not shown is refused here, before anything is left.
    func agreedLoss(_ choice: DisconnectChoice?, of connection: MarfaConnection) throws(Problem) -> Agreed? {
        switch choice {
        case .keepCopy:
            return nil
        case nil:
            return Agreed(ids: [])
        case .discardCopy(let shown?):
            return Agreed(ids: shown.ids)
        case .discardCopy(nil):
            throw .cannotDiscard(folder: location.directory(for: connection).path)
        }
    }

    /// The changes a copy that is not open holds, as its removal will check them: a copy another version made, one
    /// another program holds, or one that would not open. Nil where the package can't read them, so the person
    /// can only keep it.
    nonisolated static func unsentChanges(in store: URL) async -> UnsentChanges? {
        guard let held = try? await WorkingCopy.unsentWrites(in: store) else { return nil }
        return MarfaProblems.unsentChanges(held.writes)
    }

    /// Removes the store when every change it holds that the server has not taken is one the person agreed to lose.
    /// The package then removes exactly the changes read here, and refuses if they changed since.
    nonisolated static func removeStore(_ store: URL, agreedToLose agreed: Agreed) async throws {
        let held: Marfa.UnsentWrites
        do {
            held = try await WorkingCopy.unsentWrites(in: store)
        } catch let error as MarfaError {
            switch error {
            case .readingHandle, .storeBusy, .invalid: throw error
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

    /// What a copy's discard mark was before a step marked it early.
    struct PriorMark {
        let agreed: Agreed?
    }

    /// Marks the copy the person chose to discard, and forgets its address where the step leaves it, before the
    /// copy closes, so a quit while it closes never opens it again to send what the person discarded. The mark names
    /// only what the person was shown, so a write that lands meanwhile keeps the copy (`removeCopy`). Nil where
    /// there is nothing to mark early: a kept copy, or no discard chosen, whose closing decides first.
    func markBeforeLeaving(
        _ connection: MarfaConnection, agreed: Agreed?, choice: DisconnectChoice?, forgettingAddress: Bool = true
    ) -> PriorMark? {
        guard case .discardCopy = choice, let agreed else { return nil }
        let prior = PriorMark(agreed: discarded[connection.address.absoluteString])
        if forgettingAddress { defaults.removeObject(forKey: Self.addressKey) }
        markDiscarded(connection, agreed: agreed)
        return prior
    }

    /// Undoes `markBeforeLeaving` for a closing that refused: the copy is still open and still the person's.
    func restoreAfterRefusal(_ connection: MarfaConnection, _ prior: PriorMark, rememberingAddress: Bool = true) {
        markDiscarded(connection, agreed: prior.agreed)
        if rememberingAddress { defaults.set(connection.address.absoluteString, forKey: Self.addressKey) }
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
        var outcome = SignOutOutcome.endedAtServer
        do {
            outcome = try await signIns.signOut(of: connection)
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
        return outcome == .notConfirmed ? .notRevoked : nil
    }

    var discarded: [String: Agreed] {
        (defaults.dictionary(forKey: Self.discardedKey) ?? [:]).mapValues(Agreed.init(stored:))
    }

    func markDiscarded(_ connection: MarfaConnection, agreed: Agreed?) {
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

    /// Removes `directory` only while nothing is in it. `rmdir` refuses a folder with anything in it, as one made since
    /// is, so no check and removal can come apart.
    nonisolated static func removeIfEmpty(_ directory: URL) throws {
        guard rmdir(directory.path) != 0 else { return }
        switch errno {
        case ENOENT, ENOTEMPTY, EEXIST: return
        default: throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: directory.path, NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(errno))])
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
            // The package removes the copy's files and leaves the folder that held them, which it releases its
            // lock on first: the folder goes only if it is empty, so a copy opened in the gap is never taken with it.
            try await Self.offMain { try Self.removeIfEmpty(directory) }
            return .removed
        } catch MarfaError.readingHandle, MarfaError.storeBusy {
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
