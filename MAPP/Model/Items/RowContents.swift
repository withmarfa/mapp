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
        let membership: Int
        let looks: [TypeID: TypeLook]
        let list: RowList
    }

    private struct Held {
        let item: Item
        let showsTime: Bool
        /// The links the row was made with: they follow other items, so a change to one is seen by reading them again.
        let relations: ItemRelations
    }

    private var basis: Basis?
    private var held: [ItemID: Held] = [:]
    /// The content of each held item, kept beside `held` so a pass that changes nothing answers without building it again.
    private var made: [ItemID: RowContent] = [:]
    /// How many contents have been made, for tests to see that a pass that changes nothing makes none.
    private(set) var builds = 0

    /// The content of each entry's row. What the last pass held for an item that is gone is let go.
    func contents(
        of entries: [Entry], in library: any ItemLibrary, looks: [TypeID: TypeLook], list: RowList
    ) -> [ItemID: RowContent] {
        let next = Basis(library: ObjectIdentifier(library), membership: library.membershipRevision, looks: looks, list: list)
        if next != basis {
            basis = next
            held = [:]
            made = [:]
        }
        // The links a type's look asks for, worked out once for each type in the pass.
        var wanted: [TypeID: Set<Relation>] = [:]
        for entry in entries {
            let id = entry.item.id
            let look = looks[entry.item.type] ?? .empty
            let asked = wanted[entry.item.type] ?? { let asked = look.relations; wanted[entry.item.type] = asked; return asked }()
            // A linked item's title, or its coming or going, changes this row though this item is the same.
            let relations = library.relations(of: entry.item, wanting: asked, limit: RowContent.shownLinks)
            if let known = held[id], known.item == entry.item, known.showsTime == entry.showsTime, known.relations == relations { continue }
            builds += 1
            made[id] = RowContent.make(
                for: entry.item, look: look, catalogue: library.catalogue, list: list, relations: relations, showsTime: entry.showsTime)
            held[id] = Held(item: entry.item, showsTime: entry.showsTime, relations: relations)
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
}
