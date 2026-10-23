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

// Not `Tag`, which would shadow Yams.Tag and Testing.Tag.
nonisolated enum ItemTag {
    static let favorite = "favorite"
}

/// Something about an item as read that keeps it from being edited, such as front matter that does not parse.
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
    var title: String
    var titleRule: TitleRule
    /// The catalogue's fields in its order, then the rest.
    var properties: [Property] = []
    var preview = ""
    var content: Content = .markdown
    var state: ItemState = .active
    var tier: Tier = .library
    var container: ContainerID?
    var tags: Set<String> = []
    var version: ItemVersion
    var created: Date
    var modified: Date
    var trashed: Date?
    var edgesOut: [Edge] = []
    var sync: SyncState = .settled
    var problem: ItemProblem?
    /// Each link in this item's text, in order, with what the library bound it to, including those that name no
    /// note, more than one, or none yet. A library that binds each spelling on its own, as Marfa does, answers a
    /// link by its own binding. Empty where links are read afresh.
    var boundLinks: [BoundLink] = []
    /// What made the item, as the library names it: for a Marfa item, the source of the key that wrote it. Nil
    /// where the library does not know, as a folder does not.
    var source: String?

    /// The items the links in this item's text were already bound to, by the name each link is spelled with (read
    /// as `NoteLinks.nameKey`). A library that keeps a name's first target, as Marfa does, answers a new link with
    /// the same name with that target, whatever now goes by the name.
    var establishedLinks: [String: ItemID] {
        var established: [String: ItemID] = [:]
        for bound in boundLinks {
            guard case .resolved(let id) = bound.resolution else { continue }
            let key = NoteLinks.nameKey(bound.link.lookupName)
            if established[key] == nil { established[key] = id }
        }
        return established
    }

    var isFavorite: Bool { tags.contains(ItemTag.favorite) }

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
}
