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
        var content = make(for: item, look: look.shaped(by: shape), catalogue: catalogue, list: list, calendar: calendar, locale: locale)
        content.date = nil
        let status = catalogue.itemTypes[item.type]?.statusField?.key
        if shape.groupsByStatus || (status != nil && status == shape.leaving) {
            content.chips.removeAll { if case .status = $0 { true } else { false } }
        }
        return content
    }
}

/// The content of a gallery's or a board's cards, worked out once for each item value rather than each time a card is
/// drawn, as `RowContents` does for rows. An item that is the same, on the same catalogue, with the same looks, in the
/// same list and shape, is answered from the last pass, so a change of selection makes no card's content and an edit
/// to one item makes one. The looks are resolved once for the library's membership and the person's choices.
@MainActor
final class CardContents {
    private struct Basis: Equatable {
        let library: ObjectIdentifier
        let membership: Int
        let choices: [TypeID: TypeLookChoice]
        let list: RowList
        let shape: CardShape
    }

    private struct Held {
        let item: Item
        let content: RowContent
    }

    private var basis: Basis?
    private var looks: [TypeID: TypeLook] = [:]
    private var held: [ItemID: Held] = [:]

    /// The content of each item's card. What the last pass held for an item that is gone is let go.
    func contents(
        of items: [Item], in library: any ItemLibrary, choices: [TypeID: TypeLookChoice], list: RowList, shape: CardShape
    ) -> [ItemID: RowContent] {
        let next = Basis(library: ObjectIdentifier(library), membership: library.membershipRevision, choices: choices, list: list, shape: shape)
        if next != basis {
            basis = next
            looks = library.catalogue.looks(choices: choices)
            held = [:]
        }
        var kept: [ItemID: Held] = [:]
        kept.reserveCapacity(items.count)
        for item in items {
            if let known = held[item.id], known.item == item {
                kept[item.id] = known
                continue
            }
            let content = RowContent.card(
                for: item, look: looks[item.type] ?? .empty, catalogue: library.catalogue, list: list, shape: shape)
            kept[item.id] = Held(item: item, content: content)
        }
        held = kept
        return kept.mapValues(\.content)
    }
}
