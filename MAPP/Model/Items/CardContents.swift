import Foundation
import Marfa

/// What a card leaves out of its type's look, because the card says it another way.
nonisolated struct CardShape: Hashable, Sendable {
    /// The field a board is grouped by, which the lane already says, so the card does not.
    var leaving: String?
    /// Whether the board's lanes are status groups, where each item's status is the lane whichever field holds it.
    var groupsByStatus = false
    /// Whether the card's picture area shows the item's opening lines, so the line under the title does not repeat them.
    var dropsOpening = false
}

nonisolated extension TypeLook {
    /// The look without what a card leaves out.
    func shaped(by shape: CardShape) -> TypeLook {
        var look = self
        if shape.dropsOpening { look.secondary.removeAll { $0 == .opening } }
        if let key = shape.leaving {
            look.secondary.removeAll { $0 == .field(key) }
            look.facts.removeAll { $0 == .field(key) }
        }
        return look
    }
}

nonisolated extension RowContent {
    /// What a gallery card or a board card says about an item: the content of a row, with no date, and without what the
    /// card leaves out (`CardShape`). A card never says the date, and a board's lane says the field it is grouped by.
    static func card(
        for item: Item, look: TypeLook, catalogue: Catalogue, list: RowList, shape: CardShape,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> RowContent {
        var content = make(
            for: item, look: look.shaped(by: shape), catalogue: catalogue, list: list, includesDate: false, calendar: calendar,
            locale: locale)
        let status = catalogue.itemTypes[item.type]?.statusField?.key
        if shape.groupsByStatus || (status != nil && status == shape.leaving) {
            content.chips.removeAll { if case .status = $0 { true } else { false } }
        }
        return content
    }
}

/// The content of a gallery's or a board's cards, worked out once for each item value rather than each time a card is
/// drawn, as `RowContents` does for rows. An item that is the same, on the same catalogue, with the same looks, in the
/// same list and shape, is answered from the last pass, so a change of selection makes no card's content, an edit to
/// one item makes one, and a pass that changes nothing makes none. The looks are the browser's (`Browser.looks(in:)`),
/// resolved once for the library's membership and the person's choices.
@MainActor
final class CardContents {
    private struct Basis: Equatable {
        let library: ObjectIdentifier
        let membership: Int
        let looks: [TypeID: TypeLook]
        let list: RowList
        let shape: CardShape
    }

    private var basis: Basis?
    private var held: [ItemID: Item] = [:]
    /// The content of each held item, kept beside `held` so a pass that changes nothing answers without building it again.
    private var made: [ItemID: RowContent] = [:]
    /// How many contents have been made, for tests to see that a pass that changes nothing makes none.
    private(set) var builds = 0

    /// The content of each item's card. What the last pass held for an item that is gone is let go.
    func contents(
        of items: [Item], in library: any ItemLibrary, looks: [TypeID: TypeLook], list: RowList, shape: CardShape
    ) -> [ItemID: RowContent] {
        let next = Basis(library: ObjectIdentifier(library), membership: library.membershipRevision, looks: looks, list: list, shape: shape)
        if next != basis {
            basis = next
            held = [:]
            made = [:]
        }
        for item in items {
            let id = item.id
            if held[id] == item { continue }
            builds += 1
            made[id] = RowContent.card(
                for: item, look: looks[item.type] ?? .empty, catalogue: library.catalogue, list: list, shape: shape)
            held[id] = item
        }
        // Every item is held now, so more held than listed means some item is gone.
        if held.count != items.count {
            let listed = Set(items.map(\.id))
            for id in held.keys where !listed.contains(id) {
                held[id] = nil
                made[id] = nil
            }
        }
        return made
    }
}
