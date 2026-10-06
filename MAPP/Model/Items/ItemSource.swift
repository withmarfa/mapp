import Foundation

nonisolated struct SourceSnapshot: Hashable, Sendable {
    var items: [Item]
    var catalogue: Catalogue
    var places: [Place]
}

nonisolated struct SourceFailure: Error, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// The folder or store is gone; choosing it again may help.
        case missing
        /// Permission or a credential was refused.
        case denied
        case failed
    }

    var kind: Kind
    var message: String
}

nonisolated struct SourceCapabilities: OptionSet, Hashable, Sendable {
    let rawValue: Int
    static let archive = SourceCapabilities(rawValue: 1 << 0)
    /// Marfa purges only while the server can be reached, so a source may drop this and publish it again.
    static let purge = SourceCapabilities(rawValue: 1 << 1)
    static let move = SourceCapabilities(rawValue: 1 << 2)
    static let retype = SourceCapabilities(rawValue: 1 << 3)
    static let retier = SourceCapabilities(rawValue: 1 << 4)
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
    /// The base the page resolves the item's relative references against.
    func base(for item: ItemID) -> String
    func resolve(_ reference: String, from item: ItemID) async -> URL?
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
    func fileURL(of item: ItemID) async throws -> URL
    func search(_ text: String, in query: ItemQuery) async throws -> [ItemID]
    /// A files source renames the file to follow its first line here, so a rename is one change, not one per word.
    func endEditing(_ item: ItemID)
    func flush() async
    func close() async
}
