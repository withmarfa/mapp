import Foundation
import Observation

/// What the capsule and the pile say about the items chosen: which commands apply and how to name the choice. It is
/// worked out once for each change of the choice or of the items, never for each frame or for each button.
struct SelectionFacts: Equatable {
    /// Includes items removed by sync so command planners can count them.
    var ids: Set<ItemID> = []
    /// The moves that would change at least one chosen item (`ItemLibrary.selectionCommands`).
    var moves: Set<ItemMove> = []
    /// Every chosen item is in Recently Deleted, where Recover and Delete Immediately take the place of the rest.
    var isAllInBin = false
    var canTag = false
    var canCollect = false
    var canChangeType = false
    /// Whether every chosen item that takes the star has it, so Favorite becomes Remove from Favorites.
    var allFavorites = false
    var canFavorite = false
    /// The count and what the items are, such as "4 Tasks", or "4 Items" where their types differ.
    var title = ""
    /// The item the pile shows on top: the one edited last.
    var topID: ItemID?

    var count: Int { ids.count }

    /// Archive is the one command for a mixed choice; Unarchive stands in only where nothing chosen can be archived.
    var archiveMove: ItemMove { moves.contains(.unarchive) && !moves.contains(.archive) ? .unarchive : .archive }

    @MainActor
    static func make(_ selection: Set<ItemID>, in library: any ItemLibrary) -> SelectionFacts {
        var facts = SelectionFacts()
        var held: [Item] = []
        held.reserveCapacity(selection.count)
        for id in selection {
            if let item = library.item(id) { held.append(item) }
        }
        facts.ids = selection
        guard !held.isEmpty else { return facts }
        facts.moves = library.selectionCommands(facts.ids)
        facts.isAllInBin = held.allSatisfy { $0.state == .trashed }
        facts.canTag = held.contains { $0.allows(.tags) }
        facts.canCollect = !library.joinableCollections.isEmpty && held.contains(where: library.canJoinCollection)
        facts.canChangeType = library.offersTypeChange(for: facts.ids)
        // An item in the bin keeps its tags, so it neither decides the toggle nor takes the change.
        let starred = held.filter { $0.state != .trashed && $0.obstacle(to: .favorite) == nil }
        facts.canFavorite = !starred.isEmpty
        facts.allFavorites = !starred.isEmpty && starred.allSatisfy(\.isFavorite)
        if held.count == selection.count, let first = held.first, held.allSatisfy({ $0.type == first.type }) {
            let plural = library.catalogue.plural(for: first.type)
            facts.title = String(localized: "\(selection.count) \(plural)")
        } else {
            facts.title = String(localized: "\(selection.count) Items")
        }
        facts.topID = Self.edited(lastOf: held)
        return facts
    }

    private static func edited(lastOf items: [Item]) -> ItemID? {
        items.max { ($0.modified, $0.id.rawValue) < ($1.modified, $1.id.rawValue) }?.id
    }

    /// The item edited last among `selection`, which an edit changes without changing any command.
    @MainActor
    static func topID(of selection: Set<ItemID>, in library: any ItemLibrary) -> ItemID? {
        edited(lastOf: selection.compactMap(library.item))
    }
}

/// The facts of the window's choice while it holds several items, and none otherwise. A window holds one, which the
/// capsule and the pile read, so a change of the choice runs their bodies and nothing else's.
@Observable @MainActor
final class SelectionSummary {
    private(set) var facts = SelectionFacts()

    /// Works the facts out again for `selection`. A choice of one item or none has none, since it shows its own page.
    func update(_ selection: Set<ItemID>, in library: any ItemLibrary) {
        let new = selection.count > 1 ? SelectionFacts.make(selection, in: library) : SelectionFacts()
        if new != facts { facts = new }
    }

    /// Rechecks edit order after a content change, without rebuilding command availability.
    func refreshTop(_ selection: Set<ItemID>, in library: any ItemLibrary) {
        guard facts.count > 1, selection == facts.ids else { return }
        let top = SelectionFacts.topID(of: selection, in: library)
        if top != facts.topID { facts.topID = top }
    }
}
