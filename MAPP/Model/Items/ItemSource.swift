import Foundation

nonisolated struct SourceSnapshot: Hashable, Sendable {
    var items: [Item]
    var catalogue: Catalogue
    /// The views saved on the server, which are no items of the library.
    var views: [LibraryView] = []
}

nonisolated struct SourceFailure: LocalizedError, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// The store is gone.
        case missing
        /// Permission or a credential was refused.
        case denied
        case failed
        /// A different version of the app made the library's copy, so this one can't read it. `unsent` counts the
        /// changes in it that the server has not taken, which only that version can send; nil where it can't tell.
        case otherVersion(unsent: UInt64?)
        /// Another process, such as another copy of the app, holds the library's copy as its writer.
        case inUse
    }

    var kind: Kind
    var message: String

    /// The message is already in the person's words, so it is what any alert shows.
    var errorDescription: String? { message }
}

nonisolated enum SourceChange: Hashable, Sendable {
    /// Replaces everything held; always the first change.
    case loaded(SourceSnapshot)
    case upserted([Item])
    case removed([ItemID])
    case bodyChanged(ItemID, ItemVersion)
    case answered(WriteID, WriteOutcome)
    case catalogue(Catalogue)
    /// Every view the copy holds, whenever one comes, goes or is renamed.
    case views([LibraryView])
    case unavailable(SourceFailure)
}

nonisolated struct Embed: Hashable, Sendable {
    /// The text the page writes in the body to show it.
    let link: String
    let name: String
}

/// Where files go to the source: attached to an item, or added as items of their own.
nonisolated protocol EmbedResolver: Sendable {
    /// Attaches each file to the item and says what the page writes in its text to show it. A failure means no
    /// text is to be written, though files already attached may remain.
    func attach(_ files: [URL], to item: ItemID) async throws -> [Embed]
    /// Adds a file as an item of its own, of the file type its media type calls for, titled `title` or by its name,
    /// under `parent` where one is given.
    func addFile(_ file: URL, title: String?, tier: Tier?, parent: ItemID?) async throws -> ItemID
}

/// The Marfa working copy behind the library, as the library and the host use it, so both are tested without a
/// server. A source applies each write to its own state at once and emits the updated item, so the library keeps
/// no overlay of pending writes.
nonisolated protocol ItemSource: AnyObject, Sendable {
    var embeds: any EmbedResolver { get }
    func changes() -> AsyncStream<SourceChange>
    /// Never blocks; writes are made in the order submitted. False where the source is closed and takes nothing.
    /// A write that belongs to an undo or a redo names it in `undoing`: where the copy refuses it for being brought up
    /// to date, the source holds it and makes it once the copy is whole, if what it touches is as it was, and
    /// otherwise answers it as refused, so the undo is never lost to a catch-up.
    @discardableResult
    func submit(_ write: ItemWrite, as id: WriteID, undoing: UndoGroup?) -> Bool
    func body(of item: ItemID) async throws -> ItemBody
    /// The text of each item named that has any, read together, since a library reads every body as it loads.
    func bodies(of items: Set<ItemID>) async throws -> [ItemBody]
    func fileURL(of item: ItemID) async throws -> URL
    /// The items the view lists that the copy holds, in the view's order. Throws where the copy cannot answer the
    /// view, such as one whose filter needs links the copy does not hold whole.
    func items(inView view: ItemID) async throws -> [ItemID]
    /// What the copy's own search finds in `target`, best match first, at most `SearchResults.limit`.
    func search(_ text: String, in target: SearchTarget) async throws -> SourceSearch

    // MARK: Views, written to the server at once and never queued

    /// Each throws `ViewWriteFailure`. A write that failed for want of the server is sent again with the same
    /// `idempotencyKey`, so a request the server took before the answer was lost is not made twice.
    func createView(_ settings: LibraryViewSettings, idempotencyKey: String) async throws -> LibraryView
    /// Replaces the settings `change` names, based on the version of the view that was read.
    func changeView(_ view: ItemID, _ change: LibraryViewChange, baseVersion: Int64, idempotencyKey: String) async throws -> LibraryView
    /// Deletes the view for good, for every app; a view has no bin.
    func deleteView(_ view: ItemID, idempotencyKey: String) async throws
    /// Returns once every write submitted before it is in the source's own keeping, never waiting on the network.
    func queueSubmitted() async
    func close() async

    // MARK: The server

    var downloadedFiles: (any DownloadedFiles)? { get }
    var connectionState: MarfaConnectionState { get }
    func connectionStates() -> AsyncStream<MarfaConnectionState>
    /// What the source has yet to send, and each write that needs the person.
    var syncReport: SyncReport { get }
    /// Starts with the report as it stands, then each one that differs.
    func syncReports() -> AsyncStream<SyncReport>
    /// False where the action is not offered for the problem, or the queue would not take it, such as a write
    /// the server refused, which is never sent again.
    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool

    // MARK: What the host does with it

    /// Hydrates or catches up, then sends what waits; never waited on.
    func refresh()
    /// Goes on with `key` whatever the server answers, so a caller that keeps another key gives that one back.
    func tryKey(_ key: String) async throws -> MarfaSync.KeyCheck
    /// The writes not sent once every write submitted before the call is in the queue; nil where the queue
    /// cannot be read.
    func unsentWrites() async -> UnsentWrites?
    /// Closes only if every write not sent, read in the same step, is one of `agreed` (nil agrees to whatever
    /// the copy holds); otherwise stays open and answers what is not sent.
    func close(agreeing agreed: UnsentWrites?) async -> CloseOutcome
}

nonisolated extension ItemSource {
    var downloadedFiles: (any DownloadedFiles)? { nil }

    @discardableResult
    func submit(_ write: ItemWrite, as id: WriteID) -> Bool {
        submit(write, as: id, undoing: nil)
    }
}

/// The writes of one run of an undo or a redo, which a source holds or drops together.
nonisolated struct UndoGroup: Hashable, Sendable {
    private let rawValue = UUID()
}
