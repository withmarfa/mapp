import Foundation
import Marfa
import struct MarfaCore.Item
import struct MarfaCore.Edge
import struct MarfaCore.Edit
import struct MarfaCore.Draft
import struct MarfaCore.ListFilters
import enum MarfaCore.ItemState
import enum MarfaCore.JsonValue

/// The one place the source changes what it holds. Writes, the copy's changes and the server's answers arrive on
/// one stream and are taken one at a time, so a re-read never lands behind an older one. Each step reads or writes
/// only the copy; the server is `MarfaSync`'s, so nothing here waits on the network.
actor MarfaEngine {
    nonisolated enum Event: Sendable {
        case paint
        case fillProgress(CheckedContinuation<Void, Never>)
        /// The copy's changes have a new stream after the last one ended, so what changed between them was not heard.
        case resumed
        case write(ItemWrite, WriteID)
        case change(Marfa.Change)
        /// Resumed once the answers are taken and forgotten.
        case drained(DrainReport, CheckedContinuation<Void, Never>)
        case failed(SourceFailure)
        case flush(CheckedContinuation<Void, Never>)
        /// Resumed once every event before it is taken, so each write submitted before it is in the queue or
        /// refused; it never waits on the network, so quitting offline does not wait for a server.
        case queued(CheckedContinuation<Void, Never>)
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
        /// The server's bin as `MarfaSync` read it, which the copy never holds; `complete` where every page was read.
        case binned([Marfa.Item], complete: Bool)
        /// The verdict on a write made at the server at once rather than queued, such as a purge.
        case answer(WriteID, WriteOutcome)
        /// Attaches a file, which the package queues as an upload, a file item and an edge.
        case attach(URL, ItemID, CheckedContinuation<Result<Embed, SourceFailure>, Never>)
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
    /// Rows the server holds in its bin that the copy does not: Recently Deleted's items once their delete is
    /// answered, which the copy lets go of. Read from the server, kept as it last said and as the copy last held.
    var binned: [String: Marfa.Item] = [:]
    /// Binned rows whose restore is queued: shown nowhere until the server answers, then in the copy or back in the bin.
    var restoring: [String: Marfa.Item] = [:]
    /// What each item's text names, read by the package from the copy, for the items whose text can name anything.
    var bodyLinks: [String: BodyLinks] = [:]
    var edges = MarfaEdgeTable()
    var queue: [Marfa.QueuedWrite] = []
    var items: [ItemID: Item] = [:]
    var bodies: [ItemID: Int] = [:]
    var syncStates: [ItemID: SyncState] = [:]
    var changedSync: Set<ItemID> = []
    /// Refusals and conflicts answered, which the queue forgets unless the write carried content, kept until a later
    /// write of the same kind, or an edit, is accepted or merged. Answers already in the queue at launch, from a
    /// launch that closed before forgetting them, are taken in at the first read of the queue.
    var remembered: [ItemID: (state: SyncState, kind: WriteKind)] = [:]
    var readQueueOnce = false
    /// Until the queue is first read, nothing can be said of what waits.
    var queueRead = false
    /// Refused writes as last read, kept once the queue forgets those that carried no content, so each stays
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
    /// The app's write for each queued write it made, until every one of them is answered.
    var submitted: [String: WriteID] = [:]
    var outstanding: [WriteID: Set<String>] = [:]
    var outcomes: [WriteID: WriteOutcome] = [:]
    var failures: [SourceFailure] = []
    /// The person's latest edit of each item's text, which their next edit of it follows.
    var ownText: [ItemID: OwnText] = [:]
    /// Answered writes already taken into `ownText`, so none is counted twice.
    var counted: Set<String> = []
    /// Writes with an answer this engine has taken and the copy has not yet forgotten. Only these are forgotten: a
    /// drain the copy runs itself may have recorded others since, which their own report brings here. Only a verdict
    /// the copy can forget is kept here; a blocked or dead write stays in the queue to be released, and keeps its id.
    var takenAnswers: Set<String> = []

    nonisolated static func canForget(_ verdict: Marfa.Verdict) -> Bool {
        switch verdict {
        case .accepted, .merged, .conflicted, .refused: true
        case .blocked, .dead: false
        }
    }
    /// Edits queued as read on a version older than the copy held, whose answer lands on whatever the server held.
    var sentAsRead: Set<String> = []
    var following: Task<Void, Never>?
    var painted = false
    private var closed = false

    #if DEBUG
    /// Run before each drain's answers are taken, for the tests.
    var answering: (@Sendable () async -> Void)?

    func whenAnswering(_ hook: (@Sendable () async -> Void)?) {
        answering = hook
    }

    /// Run after the queue was last read and before the answers are forgotten, for the tests.
    var forgetting: (@Sendable () async -> Void)?

    func whenForgetting(_ hook: (@Sendable () async -> Void)?) {
        forgetting = hook
    }
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
        for await event in events {
            if closed {
                if case .write(_, let id) = event {
                    hub.publish(.answered(id, .refused(SyncProblem(code: Self.closedCode, message: Self.notKept))))
                }
                if case .flush(let done) = event { done.resume() }
                if case .queued(let done) = event { done.resume() }
                if case .fillProgress(let done) = event { done.resume() }
                if case .close(let done) = event { done.resume() }
                if case .drained(_, let taken) = event { taken.resume() }
                if case .discard(_, let done) = event { done.resume(returning: .success(false)) }
                if case .release(_, let done) = event { done.resume(returning: .success(false)) }
                if case .unsent(let done) = event { done.resume(returning: nil) }
                if case .closeAgreeing(_, let done) = event { done.resume(returning: .closed) }
                if case .attach(_, _, let done) = event {
                    done.resume(returning: .failure(SourceFailure(kind: .missing, message: Self.closedLibrary)))
                }
                continue
            }
            switch event {
            case .paint: await paint()
            case .fillProgress(let done):
                if let status = try? await reading.status() {
                    let fill = LibraryFill(status, completeness: status.hydration == .stale ? .stale :
                                            status.hydration == .complete ? .complete : .partial)
                    if hub.report.value.fill != fill {
                        await reload()
                    }
                }
                done.resume()
            case .resumed:
                await reload()
                // The follow of the server is new with the stream, so the copy is brought up to date, which also
                // sets the library right again after a fault.
                await sync.refresh()
            case .write(let write, let id): await perform(write, as: id)
            case .change(let change): await handle(change)
            case .binned(let found, let complete): take(bin: found, complete: complete)
            case .answer(let write, let outcome): hub.publish(.answered(write, outcome))
            case .attach(let file, let item, let done): done.resume(returning: await attach(file, to: item))
            case .drained(let report, let taken):
                await answer(report)
                taken.resume()
            case .failed(let failure):
                failures.append(failure)
                publish([])
            case .flush(let done):
                Task { [sync] in
                    await sync.flush()
                    done.resume()
                }
            case .queued(let done): done.resume()
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
        // Finished only once the events that came after the close are answered, so a write made too late is told
        // to its library rather than dropped unseen.
        hub.finish()
    }

    /// Read from the queue itself, since the last report can hold a count from before a read that failed.
    private func unsentWrites() async -> UnsentWrites? {
        guard let queue = try? await Self.asking(hub, { try await copy.queue.all() }) else { return nil }
        let named = Set(queue.compactMap(\.itemId))
        let types = Dictionary(uniqueKeysWithValues: named.compactMap { id in rows[id].map { (id, TypeID($0.type)) } })
        return UnsentWrites(
            ids: MarfaProblems.unsent(queue), texts: MarfaProblems.unsentTexts(queue, catalogue: catalogue, types: types))
    }

    private func shutDown() async {
        closed = true
        following?.cancel()
        await sync.stop()
        await downloads.stop()
        await copy.close()
    }

    /// The package refuses every call while the copy changes its key, as `invalid`, and asks for it again; that
    /// is a wait, never a refusal or a failure to show. Any other `invalid` is passed on.
    nonisolated static func asking<T>(_ hub: MarfaHub, _ work: () async throws -> T) async throws -> T {
        while true {
            let mark = hub.keyChanges
            do {
                return try await work()
            } catch let error as MarfaError {
                guard case .invalid = error, hub.keyChanged(since: mark) else { throw error }
                // Throws once the task is cancelled, which ends the asking.
                try await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    /// A read the copy refuses while a hydration is under way is no failure to tell: the copy says `.refreshed` when
    /// the hydration ends, and the engine reads it all again then. A source move hydrates a large library again
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
