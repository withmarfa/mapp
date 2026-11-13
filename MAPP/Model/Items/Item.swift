import Foundation
import UniformTypeIdentifiers

nonisolated enum ItemState: Hashable, Sendable, CaseIterable {
    case active, archived, trashed
}

nonisolated enum Tier: Hashable, Sendable, CaseIterable {
    case library, feed
}

nonisolated indirect enum PropertyValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([PropertyValue])
    case object([String: PropertyValue])

    var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}

nonisolated struct Property: Identifiable, Hashable, Sendable {
    let key: String
    let value: PropertyValue
    var id: String { key }
}

// Not `Tag`, which would shadow Testing.Tag.
nonisolated enum ItemTag {
    static let favorite = "favorite"
    /// What Marfa allows a tag, in UTF-16 code units, and how many an item holds (`items/tag-text`, `items/tags-count`).
    static let maxLength = 128
    static let maxPerItem = 100

    /// Why a tag was not added, in the words the person is told. Nothing was sent.
    enum Refusal: Error, Hashable, Sendable {
        case empty, tooLong, dotSegment
        /// The Favorite command's tag, or one the library sets itself.
        case favorite, reserved
        case alreadyHas, full, cantEdit

        var message: String {
            switch self {
            case .empty: String(localized: "Enter a tag.")
            case .tooLong: String(localized: "A tag can be at most \(ItemTag.maxLength) characters.")
            case .dotSegment: String(localized: "A tag can’t be “.” or “..”.")
            case .favorite: String(localized: "Favorites are set with Add to Favorites.")
            case .reserved: String(localized: "The library sets this tag itself.")
            case .alreadyHas: String(localized: "Already tagged.")
            case .full: String(localized: "An item can have at most \(ItemTag.maxPerItem) tags.")
            case .cantEdit: String(localized: "This item’s tags can’t be changed.")
            }
        }
    }

    /// The tag as it is kept: Marfa holds a tag as written, so only the spaces around it, which a paste brings, go.
    /// Case is kept, since `Work` and `work` are two tags.
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The refusal the rules of a tag's text give, before any item is looked at.
    static func refusal(of tag: String) -> Refusal? {
        if tag.isEmpty { return .empty }
        if tag.utf16.count > maxLength { return .tooLong }
        if tag == "." || tag == ".." { return .dotSegment }
        return nil
    }
}

/// Something about an item as read that keeps it from being edited, such as properties the library could not read.
nonisolated struct ItemProblem: Hashable, Sendable {
    let message: String
    /// The library could not read the item's text either, so the page shows none and says why.
    var withholdsText = false
}

nonisolated struct Item: Identifiable, Hashable, Sendable {
    enum TitleRule: Hashable, Sendable {
        case property(String)
        case firstLine
    }

    enum Content: Hashable, Sendable {
        case markdown
        case file(UTType, byteCount: Int64)
    }

    let id: ItemID
    var type: TypeID
    /// What MAPP edits and writes as the item's title; never shown as the item's name (`displayTitle`).
    var title: String
    /// The name the core gives the item, by its type's display hints and fallback fields, or nil where the server
    /// would say "Untitled". Only shown, never written.
    var name: String? = nil
    var titleRule: TitleRule
    /// The catalogue's fields in its order, then the rest.
    var properties: [Property] = []
    var preview = ""
    var content: Content = .markdown
    var state: ItemState = .active
    var tier: Tier = .library
    var tags: Set<String> = []
    var version: ItemVersion
    var created: Date
    var modified: Date
    /// When the item happened, as Marfa's `occurred_at` says (a quote was captured, a message was sent), or nil where the
    /// server has none; a look's `occurred` date falls back to `created`.
    var occurred: Date?
    var trashed: Date?
    var edgesOut: [Edge] = []
    var sync: SyncState = .settled
    var problem: ItemProblem?
    /// Whether the server advises that a person's connector keeps this item, so a change made here would be put back
    /// on the connector's next run. Advice only: the server refuses no write, and the value can be older than 15
    /// minutes. MAPP offers no change to such an item (`allowsChanges`).
    var readOnly = false
    /// Each embed in this item's text, in order, with the file item the library bound it to or why it has none.
    var boundEmbeds: [BoundEmbed] = []
    /// What made the item, as the library names it: for a Marfa item, the source of the key that wrote it. Nil
    /// where the library does not know. An item written in MAPP has one too, so this does not separate captured
    /// items from the person's own.
    var source: String?

    var isFavorite: Bool { tags.contains(ItemTag.favorite) }

    /// The name as a person reads it: the core's, or MAPP's own "Untitled" where the core gives none. Only shown,
    /// never written into the item.
    var displayTitle: String { name ?? String(localized: "Untitled") }

    /// Whether the core names the item, so its row can set the placeholder apart.
    var isUntitled: Bool { name == nil }

    func value(of key: String) -> PropertyValue? {
        properties.first { $0.key == key }?.value
    }
}

/// A body is read on its own, since only an open editor needs it and it is the bulk of an item.
nonisolated struct ItemBody: Hashable, Sendable {
    let id: ItemID
    let text: String
    let version: ItemVersion
}

nonisolated enum EdgeTarget: Hashable, Sendable {
    case item(ItemID)
    /// A reference no item answers to, or more than one does, kept as spelled so it can be shown and fixed.
    case unresolved(spelling: String, ambiguous: Bool)
    /// Not looked up on the server yet, which a later sync does.
    case pending(spelling: String)
    /// The server refused the lookup or the write of the edge.
    case refused(spelling: String, reason: String)
}

nonisolated enum EdgeOrigin: Hashable, Sendable {
    case property(String)
    case body
}

/// An edge as the item that writes it holds it, following Marfa's folder rule: it sits in the `edgesOut` of the
/// item at the end its type is written at, named as that end writes it. A child's `child-of` is in the child's
/// `edgesOut` with the parent as its target; `Catalogue.edgeType(named:)` gives the canonical direction.
nonisolated struct Edge: Identifiable, Hashable, Sendable {
    let id: EdgeID
    let type: String
    let source: ItemID
    let target: EdgeTarget
    let origin: EdgeOrigin
    /// The edge's `position` property, where it has one, as an `in-collection` edge orders a collection's members.
    var position: Double? = nil
}

nonisolated extension Item {
    /// The item this one is filed under: the target of its `child-of` edge.
    var parentID: ItemID? {
        edgesOut.lazy.compactMap { edge -> ItemID? in
            guard edge.type == "child-of", case .item(let id) = edge.target else { return nil }
            return id
        }.first
    }

    /// The collections this item is in: the targets of its `in-collection` edges, in the order it holds them.
    var collectionIDs: [ItemID] {
        edgesOut.compactMap { edge -> ItemID? in
            guard edge.type == MarfaMapping.collectionEdge, case .item(let id) = edge.target else { return nil }
            return id
        }
    }

    /// Whether its properties and relationships can be changed. A file, a deleted item, one with a problem or one a
    /// connector keeps is read only.
    var isEditable: Bool { allowsChanges && !isFile }

    /// Whether its text can be written in: text the library could not read is not shown, so nothing typed over the
    /// empty page is written.
    var isWritable: Bool { state == .active && !isFile && !readOnly && problem?.withholdsText != true }

    /// Whether its tags can be changed: a file can be tagged, a deleted item, one with a problem or one a connector
    /// keeps cannot.
    var canEditTags: Bool { allowsChanges }

    /// The one place that decides an item takes changes to its values and tags, which every editor on the page and in
    /// the inspector asks through `isEditable` and `canEditTags`.
    private var allowsChanges: Bool { state == .active && problem == nil && !readOnly }

    var isFile: Bool {
        if case .file = content { true } else { false }
    }

    /// What the library says a file item is, which is nil for a note and `.data` where it does not know.
    var fileType: UTType? {
        if case .file(let type, _) = content { type } else { nil }
    }
}
