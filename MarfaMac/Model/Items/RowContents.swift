import Foundation

/// The content of a list's rows, worked out once for each item value rather than each time a row is drawn. A list asks
/// for the rows it shows; an item that is the same, in the same list, on the same catalogue and with the same looks, is
/// answered from the last pass, so a change of selection or of one item makes the content of one row at most.
///
/// The looks are the browser's (`Browser.looks(in:)`), resolved once for the library's membership and the person's
/// choices and handed in, never resolved here or in a row.
@MainActor
final class RowContents {
    /// An item as a list draws it, and whether its date reads as a time of day (inside a day's group).
    struct Entry {
        let item: Item
        let showsTime: Bool
    }

    private struct Basis: Equatable {
        let library: ObjectIdentifier
        let looks: [TypeID: TypeLook]
        let list: RowList
    }

    private struct Held {
        let item: Item
        let showsTime: Bool
        /// The links the row was made with: they follow other items, so a change to one is seen by reading them again.
        let relations: ItemRelations
        /// The files attached to the item, read only where the list shows pictures.
        let attachments: [Item]
    }

    private var basis: Basis?
    /// The library's and the counts' revisions at the last pass, from which only the items that changed are read again.
    private var revisions: (content: Int, counts: Int)?
    private var held: [ItemID: Held] = [:]
    /// The content of each held item, kept beside `held` so a pass that changes nothing answers without building it again.
    private var made: [ItemID: RowContent] = [:]
    /// How many contents have been made, for tests to see that a pass that changes nothing makes none.
    private(set) var builds = 0

    /// The content of each entry's row. What the last pass held for an item that is gone is let go.
    func contents(
        of entries: [Entry], in library: any ItemLibrary, looks: [TypeID: TypeLook], list: RowList
    ) -> [ItemID: RowContent] {
        let next = Basis(library: ObjectIdentifier(library), looks: looks, list: list)
        if next != basis {
            basis = next
            held = [:]
            made = [:]
            revisions = nil
        }
        let changed = changes(in: library)
        // The links a type's look asks for, worked out once for each type in the pass.
        var wanted: [TypeID: (relations: Set<Relation>, counts: Set<CountFact>)] = [:]
        for entry in entries {
            let id = entry.item.id
            // Nothing this row is made of changed since it was made.
            if let changed, !changed.contains(id), let known = held[id], known.showsTime == entry.showsTime { continue }
            let look = looks[entry.item.type] ?? .empty
            let asked = wanted[entry.item.type] ?? { let asked = (look.relations, look.counts); wanted[entry.item.type] = asked; return asked }()
            // A linked item's title, or its coming or going, or a count's answer coming, changes this row though this item is the same.
            let relations = library.relations(of: entry.item, wanting: asked.relations, counts: asked.counts, limit: RowContent.shownLinks)
            // A file is its own picture, so only another item's attachments are read.
            let attachments = list.showsPictures ? CardAttachments.of(entry.item, in: library) : []
            if let known = held[id], known.item == entry.item, known.showsTime == entry.showsTime, known.relations == relations,
               known.attachments == attachments { continue }
            builds += 1
            made[id] = RowContent.make(
                for: entry.item, look: look, catalogue: library.catalogue, list: list, relations: relations, attachments: attachments,
                showsTime: entry.showsTime)
            held[id] = Held(item: entry.item, showsTime: entry.showsTime, relations: relations, attachments: attachments)
        }
        // Every entry is held now, so more held than listed means some item is gone.
        if held.count != entries.count {
            let listed = Set(entries.map(\.item.id))
            for id in held.keys where !listed.contains(id) {
                held[id] = nil
                made[id] = nil
            }
        }
        return made
    }

    /// The items whose rows may differ since the last pass: those the library or the counts say changed. Nil where every
    /// item is read again, as at the first pass, and where the library cannot say, when what was made is let go too, since
    /// a catalogue read again can change any of it.
    private func changes(in library: any ItemLibrary) -> Set<ItemID>? {
        let now = (content: library.contentRevision, counts: library.counts.revision)
        defer { revisions = now }
        guard let revisions else { return nil }
        guard let items = library.changedItems(since: revisions.content) else {
            held = [:]
            made = [:]
            return nil
        }
        return library.counts.changedItems(since: revisions.counts).map { items.union($0) }
    }
}
