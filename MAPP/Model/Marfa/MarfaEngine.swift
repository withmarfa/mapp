import Foundation
import Marfa

/// The one place the source changes what it holds. Writes, the copy's changes and the server's answers arrive on
/// one stream and are taken one at a time, so a re-read never lands behind an older one. Each step reads or writes
/// only the copy; the server is `MarfaSync`'s, so nothing here waits on the network.
actor MarfaEngine {
    nonisolated enum Event: Sendable {
        case paint
        case write(ItemWrite, WriteID)
        /// A write of an undo or a redo, held where the copy refuses it for being brought up to date (`MarfaEngine+Holding`).
        case undo(ItemWrite, WriteID, UndoGroup)
        /// The time a held undo may wait has passed.
        case holdExpired(UndoGroup)
        /// What the copy said changed (`WorkingCopy.updates()`); resumed once it is read, so the package coalesces
        /// what arrives meanwhile.
        case update(CopyUpdate, CheckedContinuation<Void, Never>)
        /// A drain ended: the answers the copy recorded are taken, and this is resumed once they are told.
        case answers(CheckedContinuation<Void, Never>)
        case failed(SourceFailure)
        case flush(CheckedContinuation<Void, Never>)
        case close(CheckedContinuation<Void, Never>)
        /// Takes a refused write, and those refused only for it, out of the queue.
        case discard(String, CheckedContinuation<Result<Bool, SourceFailure>, Never>)
        /// Sends a stopped write again.
        case release(String, CheckedContinuation<Result<Bool, SourceFailure>, Never>)
        /// The writes not sent, read from the queue once every event before it is taken, so every write
        /// submitted before it counts; nil where the queue cannot be read.
        case unsent(CheckedContinuation<UnsentWrites?, Never>)
        /// Closes, as `close` does, only if every write not sent, read from the queue in the same step, is one
        /// of those agreed to; nil agrees to whatever the copy holds.
        case closeAgreeing(UnsentWrites?, CheckedContinuation<CloseOutcome, Never>)
        /// The verdict on a write made at the server at once rather than queued, such as a purge.
        case answer(WriteID, WriteOutcome)
        /// Attaches a file, which the package queues as an upload, a file item and an edge.
        case attach(URL, ItemID, CheckedContinuation<Result<Embed, SourceFailure>, Never>)
        /// Adds a file as an item of its own, which the package queues as an upload and a file item.
        case addFile(URL, title: String?, tier: Tier?, parent: ItemID?, CheckedContinuation<Result<ItemID, SourceFailure>, Never>)
        /// What the copy answered an attach it made beside the lane (`token`), with the title the lane chose.
        case attached(
            Result<Marfa.Attached, SourceFailure>, ItemID, title: String, token: UUID,
            CheckedContinuation<Result<Embed, SourceFailure>, Never>)
        /// What the copy answered a file it added beside the lane (`token`), and the item to put it under.
        case addedFile(
            Result<Marfa.Added, SourceFailure>, parent: ItemID?, token: UUID,
            CheckedContinuation<Result<ItemID, SourceFailure>, Never>)
    }

    /// A write the type cannot take.
    nonisolated struct Unsupported: Error {
        var message: String
    }

    /// A write the package refused before queueing it, in the person's words.
    nonisolated struct Refused: Error {
        var problem: SyncProblem
    }

    /// The person's latest edit of an item's text, and the version of the item their own writes account for: the
    /// version that edit was typed on, moved on by each answer to this device's writes of the item.
    nonisolated struct OwnText: Equatable {
        var text: String
        var on: Int64
    }

    nonisolated static var notCurrent: String {
        String(localized: "This library is being brought up to date. Try again in a moment.")
    }

    /// The codes of an undo or a redo that was held while the copy was brought up to date and then not made.
    nonisolated static let heldChangedCode = "undo_changed"
    nonisolated static let heldTimeoutCode = "undo_timeout"

    nonisolated static func isHeldRefusal(_ code: String) -> Bool {
        code == heldChangedCode || code == heldTimeoutCode
    }

    nonisolated static var heldChanged: String {
        String(localized: "This changed while the library was being brought up to date, so the change wasn’t made.")
    }

    nonisolated static var heldTimedOut: String {
        String(localized: "The library is still being brought up to date, so the change wasn’t made.")
    }

    nonisolated static var closedLibrary: String {
        String(localized: "This library is closed.")
    }

    /// The code of the refusal a write gets when it reaches the engine after the copy closed.
    nonisolated static let closedCode = "closed"

    /// A write that reached the source after it closed, which no queue holds.
    nonisolated static var notKept: String {
        String(localized: "This library was closed before the change could be kept.")
    }

    nonisolated static var noText: String {
        String(localized: "This kind of item has no text to edit.")
    }

    let sync: MarfaSync
    let copy: WorkingCopy
    private let downloads: MarfaDownloads
    let reading: any MarfaReading
    let hub: MarfaHub
    let tell: @Sendable (Event) -> Bool
    var catalogue = Catalogue()
    /// The library's rows: every row the copy holds but the `system.*` ones (`MarfaMapping.isLibraryItem`).
    var rows: [String: Marfa.Item] = [:]
    /// The views saved on the server, as the copy last held them.
    var views: [LibraryView] = []
    /// What each item's text names, read by the package from the copy, for the items whose text can name anything.
    var bodyLinks: [String: BodyLinks] = [:]
    var edges = MarfaEdgeTable()
    var queue: [Marfa.QueuedWrite] = []
    var syncStates: [ItemID: SyncState] = [:]
    var changedSync: Set<ItemID> = []
    /// Refusals and conflicts answered, which the copy clears when it hands the answers over (`Queue.takeAnswered`)
    /// unless the write carried content, kept until a later write of the same kind, or an edit, is accepted or
    /// merged. Answers recorded before this launch are taken in at the first update.
    var remembered: [ItemID: (state: SyncState, kind: WriteKind)] = [:]
    var readQueueOnce = false
    /// Until the queue is first read, nothing can be said of what waits.
    var queueRead = false
    /// Refused writes as last read, kept once the copy clears those that carried no content, so each stays
    /// before the person until they discard it or a later write of its kind lands.
    var refusals: [String: Marfa.QueuedWrite] = [:]
    /// The item each conflicted copy was made from, as its verdict named it, which is known before the copy's link has reached the copy.
    var originals: [String: String] = [:]
    /// The item each conflicted copy was made from, and the copies each original has that are not in the bin, as
    /// the package reads the copy's `derived-from` link: a copy and its original know each other from the copy
    /// alone, offline and after a relaunch.
    var linkedOriginals: [String: String] = [:]
    var linkedCopies: [String: [String]] = [:]
    /// The items an edge move touched, read again once its answer is taken: the two ends it left and the one it went
    /// to, since a refusal puts the edge back and the answer names only its source.
    var movedEnds: [String: Set<String>] = [:]
    /// The app's writes queued and not yet answered.
    var writes = MarfaWriteRecord()
    /// The attaches and added files the copy is reading beside the lane, so a large file never holds the person's
    /// saves (`MarfaEngine+Attachments`). A close, and a read of what is unsent, wait for them first.
    var besideTheLane: [UUID: Task<Void, Never>] = [:]
    /// The titles, lowercased, of the files being attached to each item, so two attached at once get different names.
    var attachingTitles: [String: Set<String>] = [:]
    var failures: [SourceFailure] = []
    /// The person's latest edit of each item's text, which their next edit of it follows.
    var ownText: [ItemID: OwnText] = [:]
    /// Answered writes already taken into `ownText`, so none is counted twice.
    var counted: Set<String> = []
    /// Answers to the person's creates and updates that the copy has cleared (`Queue.takeAnswered`) and the text of
    /// their item has not yet been counted past, so the queue is read with them (`queueWithAnswers`).
    var answeredHeld: [String: Marfa.QueuedWrite] = [:]
    /// Writes the copy keeps with a verdict (a refused write that carried content, a blocked or a dead one), whose
    /// verdict the app's write has been told, so each is told once.
    var told: Set<String> = []
    /// Writes of an undo or a redo that the copy refused while it was brought up to date, in the order they were
    /// made, until the copy is whole.
    var held: [Held] = []
    /// How long a held undo waits for a copy that is not catching up before it is given back.
    var holdLimit: Duration {
        #if DEBUG
        if let limit = hooks.holdLimit.current { return limit }
        #endif
        return .seconds(30)
    }

    /// Edits queued as read on a version older than the copy held, whose answer lands on whatever the server held.
    var sentAsRead: Set<String> = []
    var painted = false
    /// Whether the package's first update, which always asks to read everything, has been taken.
    var tookFirstUpdate = false
    /// Where the copy's changes are next read from (`readChanged`). The rows and edges held agree with the copy at
    /// this point for every row and edge the copy has not named as changed since; nil until a whole read takes one,
    /// and after a whole read that could not read every row's links.
    var cursor: ChangeCursor?
    /// Whether the last update carried a fill, and what connection it named, so the copy's status is read again only
    /// when a fill ended or the connection changed, not for each local write.
    var lastUpdateFilled = false
    var lastConnection: CopyConnection?
    /// When a hydration's progress may next read the copy whole (`takeFillProgress`).
    var fillReadAllowed = ContinuousClock.now
    private var closed = false

    #if DEBUG
    nonisolated let hooks = TestHooks()
    #endif

    init(copy: WorkingCopy, hub: MarfaHub, downloads: MarfaDownloads, reading: (any MarfaReading)? = nil,
         refreshing: (any MarfaRefreshing)? = nil,
         tell: @escaping @Sendable (Event) -> Bool) {
        self.copy = copy
        self.downloads = downloads
        self.reading = reading ?? MarfaRead(copy: copy)
        self.hub = hub
        self.tell = tell
        sync = MarfaSync(copy: copy, hub: hub, downloads: downloads, refreshing: refreshing, tell: tell)
    }

    func run(_ events: AsyncStream<Event>) async {
        for await event in events { await process(event) }
        // Finished only once the events that came after the close are answered, so a write made too late is told
        // to its library rather than dropped unseen.
        hub.finish()
        hub.activity.finish()
    }

    /// One event, timed and recorded on the hub as the step the engine is in, which anyone can read without
    /// awaiting this actor (`EngineActivity`).
    private func process(_ event: Event) async {
        let kind = event.kind
        hub.activity.begin(kind)
        let interval = Telemetry.begin(.engine, kind)
        await apply(event)
        let elapsed = interval.end()
        if event.isWrite {
            hub.activity.tookWrite()
        }
        hub.activity.end()
        Telemetry.engineEventTook(kind, elapsed)
    }

    private func apply(_ event: Event) async {
        if closed {
            if case .write(_, let id) = event {
                hub.publish(.answered(id, .refused(SyncProblem(code: Self.closedCode, message: Self.notKept))))
            }
            if case .undo(_, let id, _) = event {
                hub.publish(.answered(id, .refused(SyncProblem(code: Self.closedCode, message: Self.notKept))))
            }
            if case .flush(let done) = event { done.resume() }
            if case .close(let done) = event { done.resume() }
            if case .update(_, let done) = event { done.resume() }
            if case .answers(let done) = event { done.resume() }
            if case .discard(_, let done) = event { done.resume(returning: .success(false)) }
            if case .release(_, let done) = event { done.resume(returning: .success(false)) }
            if case .unsent(let done) = event { done.resume(returning: nil) }
            if case .closeAgreeing(_, let done) = event { done.resume(returning: .closed) }
            if case .attach(_, _, let done) = event {
                done.resume(returning: .failure(SourceFailure(kind: .missing, message: Self.closedLibrary)))
            }
            if case .addFile(_, _, _, _, let done) = event {
                done.resume(returning: .failure(SourceFailure(kind: .missing, message: Self.closedLibrary)))
            }
            // The copy took the file before it closed, so the answer says so, and nothing is read again.
            if case .attached(let result, let item, let title, let token, let done) = event {
                settled(token, attaching: title, to: item)
                done.resume(returning: result.map { Self.embed(of: $0, title: title) })
                hub.activity.answeredAside()
            }
            if case .addedFile(let result, _, let token, let done) = event {
                settled(token)
                done.resume(returning: result.flatMap(Self.addedID))
                hub.activity.answeredAside()
            }
            return
        }
        switch event {
        case .paint: await paint()
        case .write(let write, let id): await perform(write, as: id)
        case .undo(let write, let id, let group): await perform(write, as: id, holding: group)
        case .holdExpired(let group): expire(group)
        case .update(let update, let done):
            await take(update: update)
            done.resume()
        case .answers(let done):
            await takeAnswers()
            done.resume()
        case .answer(let write, let outcome): hub.publish(.answered(write, outcome))
        case .attach(let file, let item, let done): attach(file, to: item, answering: done)
        case .addFile(let file, let title, let tier, let parent, let done):
            addFile(file, title: title, tier: tier, under: parent, answering: done)
        case .attached(let result, let item, let title, let token, let done):
            done.resume(returning: await take(attached: result, to: item, title: title, token: token))
        case .addedFile(let result, let parent, let token, let done):
            done.resume(returning: await take(added: result, under: parent, token: token))
        case .failed(let failure):
            failures.append(failure)
            publish([])
        case .flush(let done):
            Task { [sync] in
                await sync.flush()
                done.resume()
            }
        case .discard(let id, let done): done.resume(returning: await discard(id))
        case .release(let id, let done): done.resume(returning: await release(id))
        case .unsent(let done):
            done.resume(returning: await unsentWrites())
        case .closeAgreeing(let agreed, let done):
            let unsent = await unsentWrites()
            let covered = if let unsent { agreed.map { unsent.ids.isSubset(of: $0.ids) } ?? true } else { agreed == nil }
            if covered {
                await shutDown()
                done.resume(returning: .closed)
            } else {
                done.resume(returning: .waiting(unsent))
            }
        case .close(let done):
            await shutDown()
            done.resume()
        }
    }

    /// Read from the queue itself, since the last report can hold a count from before a read that failed.
    private func unsentWrites() async -> UnsentWrites? {
        await besideTheLaneQueued()
        guard let queue = try? await Self.asking({ try await copy.queue.all() }) else { return nil }
        let named = Set(queue.compactMap(\.itemId))
        let types = Dictionary(uniqueKeysWithValues: named.compactMap { id in rows[id].map { (id, TypeID($0.type)) } })
        return UnsentWrites(
            ids: MarfaProblems.unsent(queue), texts: MarfaProblems.unsentTexts(queue, catalogue: catalogue, types: types))
    }

    private func shutDown() async {
        await besideTheLaneQueued()
        closed = true
        for entry in held {
            hub.publish(.answered(entry.id, .refused(SyncProblem(code: Self.closedCode, message: Self.notKept))))
        }
        held = []
        await sync.stop()
        await downloads.stop()
        await copy.close()
    }

    /// The package refuses every call while the copy changes its key (`keyChanging`) and asks for it again; that
    /// is a wait, never a refusal or a failure to show.
    nonisolated static func asking<T>(_ work: () async throws -> T) async throws -> T {
        while true {
            do {
                return try await work()
            } catch MarfaError.keyChanging {
                // Throws once the task is cancelled, which ends the asking.
                try await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    /// A read the copy refuses while a hydration is under way is no failure to tell: the copy's next update
    /// asks for everything when the hydration ends, and the engine reads it all again then. A source move hydrates a large library again
    /// after every move, so telling it would put up an alert after an ordinary change of parent.
    func readFailed(_ error: any Error) {
        if case MarfaError.hydrationIncomplete = error { return }
        failures.append(Self.failure(error))
    }

    static func failure(_ error: any Error) -> SourceFailure {
        if let failure = error as? SourceFailure { return failure }
        return SourceFailure(kind: .failed, message: (error as? MarfaError)?.message ?? error.localizedDescription)
    }
}
