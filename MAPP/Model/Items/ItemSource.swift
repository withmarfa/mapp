import Foundation

nonisolated struct SourceSnapshot: Hashable, Sendable {
    var items: [Item]
    var catalogue: Catalogue
    var places: [Place]
}

nonisolated struct SourceFailure: LocalizedError, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// The folder or store is gone; choosing it again may help.
        case missing
        /// Permission or a credential was refused.
        case denied
        case failed
    }

    var kind: Kind
    var message: String

    /// The message is already in the person's words, so it is what any alert shows.
    var errorDescription: String? { message }
}

nonisolated struct SourceCapabilities: OptionSet, Hashable, Sendable {
    let rawValue: Int
    static let archive = SourceCapabilities(rawValue: 1 << 0)
    /// Marfa purges only while the server can be reached, so a source may drop this and publish it again.
    static let purge = SourceCapabilities(rawValue: 1 << 1)
    static let move = SourceCapabilities(rawValue: 1 << 2)
    static let retype = SourceCapabilities(rawValue: 1 << 3)
    static let retier = SourceCapabilities(rawValue: 1 << 4)
    /// Rename Note gives an item's file a new name. A title is a property, which any library edits.
    static let renameFiles = SourceCapabilities(rawValue: 1 << 5)
    /// Folders can be made, renamed, deleted and reordered.
    static let folders = SourceCapabilities(rawValue: 1 << 6)
    static let importFiles = SourceCapabilities(rawValue: 1 << 7)
}

nonisolated enum SourceChange: Hashable, Sendable {
    /// Replaces everything held; always the first change.
    case loaded(SourceSnapshot)
    case upserted([Item])
    case removed([ItemID])
    case bodyChanged(ItemID, ItemVersion)
    case answered(WriteID, WriteOutcome)
    case catalogue(Catalogue)
    case places([Place])
    case unavailable(SourceFailure)
}

nonisolated struct Embed: Hashable, Sendable {
    /// The text the page writes in the body to show it.
    let link: String
    let name: String
}

nonisolated protocol EmbedResolver: Sendable {
    /// Attaches each file to the item and says what the page writes in its text to show it. A failure means no
    /// text is to be written, though files already attached may remain.
    func attach(_ files: [URL], to item: ItemID) async throws -> [Embed]
}

/// Storage behind the library. A source applies each write to its own state at once and emits the updated item,
/// so the library keeps no overlay of pending writes.
nonisolated protocol ItemSource: AnyObject, Sendable {
    var capabilities: SourceCapabilities { get }
    var embeds: any EmbedResolver { get }
    func changes() -> AsyncStream<SourceChange>
    /// Never blocks; writes are made in the order submitted.
    func submit(_ write: ItemWrite, as id: WriteID)
    func body(of item: ItemID) async throws -> ItemBody
    /// The text of each item named that has any, read together, since a library reads every body as it loads.
    func bodies(of items: Set<ItemID>) async throws -> [ItemBody]
    func fileURL(of item: ItemID) async throws -> URL
    /// Best match first.
    func search(_ text: String, in query: ItemQuery) async throws -> [ItemID]
    /// A files source renames the file to follow its first line here, so a rename is one change, not one per word.
    func endEditing(_ item: ItemID)
    func flush() async
    func close() async
}
