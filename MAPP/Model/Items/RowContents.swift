import Foundation

/// The content of a list's rows, worked out once for each item value rather than each time a row is drawn. A list asks
/// for the rows it shows; an item that is the same, in the same list, on the same catalogue and with the same looks, is
/// answered from the last pass, so a change of selection or of one item makes the content of one row at most.
///
/// The looks are resolved once for the catalogue's revision and the person's choices (`TypeLooks.looks`), never in a row.
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
        let choices: [TypeID: TypeLookChoice]
        let list: RowList
    }

    private struct Held {
        let item: Item
        let showsTime: Bool
    }

    private var basis: Basis?
    private var looks: [TypeID: TypeLook] = [:]
    private var held: [ItemID: Held] = [:]
    /// The content of each held item, kept beside `held` so a pass that changes nothing answers without building it again.
    private var made: [ItemID: RowContent] = [:]

    /// The content of each entry's row. What the last pass held for an item that is gone is let go.
    func contents(
        of entries: [Entry], in library: any ItemLibrary, choices: [TypeID: TypeLookChoice], list: RowList
    ) -> [ItemID: RowContent] {
        let next = Basis(library: ObjectIdentifier(library), membership: library.membershipRevision, choices: choices, list: list)
        if next != basis {
            basis = next
            looks = library.catalogue.looks(choices: choices)
            held = [:]
            made = [:]
        }
        for entry in entries {
            let id = entry.item.id
            if let known = held[id], known.item == entry.item, known.showsTime == entry.showsTime { continue }
            let look = looks[entry.item.type] ?? .empty
            made[id] = RowContent.make(
                for: entry.item, look: look, catalogue: library.catalogue, list: list, showsTime: entry.showsTime)
            held[id] = Held(item: entry.item, showsTime: entry.showsTime)
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
