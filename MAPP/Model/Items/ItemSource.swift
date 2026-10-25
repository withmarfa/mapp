import Foundation

nonisolated struct SourceSnapshot: Hashable, Sendable {
    var items: [Item]
    var catalogue: Catalogue
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
    case unavailable(SourceFailure)
}

nonisolated struct Embed: Hashable, Sendable {
    /// The text the page writes in the body to show it.
    let link: String
    let name: String
}

nonisolated protocol EmbedResolver: Sendable {
    /// Attaches the file to the item and says what the page writes in its text to show it. A failure means the
    /// file was not attached.
    func attach(_ file: URL, to item: ItemID) async throws -> Embed
}

/// What attaching files gave: the text to write for each file attached, in order, and the name of each that
/// wasn't, with why.
nonisolated struct AttachReport: Sendable {
    var embeds: [Embed] = []
    var failed: [(name: String, reason: String)] = []
}

/// The Marfa working copy behind the library, as the library and the host use it, so both are tested without a
/// server. A source applies each write to its own state at once and emits the updated item, so the library keeps
/// no overlay of pending writes.
nonisolated protocol ItemSource: AnyObject, Sendable {
    var embeds: any EmbedResolver { get }
    func changes() -> AsyncStream<SourceChange>
    /// Never blocks; writes are made in the order submitted. False where the source is closed and takes nothing.
    @discardableResult
    func submit(_ write: ItemWrite, as id: WriteID) -> Bool
    func body(of item: ItemID) async throws -> ItemBody
    /// The text of each item named that has any, read together, since a library reads every body as it loads.
    func bodies(of items: Set<ItemID>) async throws -> [ItemBody]
    func fileURL(of item: ItemID) async throws -> URL
    /// Best match first.
    func search(_ text: String, in query: ItemQuery) async throws -> [ItemID]
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
}
