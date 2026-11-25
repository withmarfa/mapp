import Foundation

/// How the list is ordered: by which date or by title, and whether dated items fall into sections by day. The
/// defaults here are the only ones; stored settings fall back to them.
nonisolated struct ItemOrder: Equatable {
    var sort: ItemSort = .dateEdited
    var groupsByDate = true
}

nonisolated enum ItemSort: String, CaseIterable {
    case dateEdited
    case dateCreated
    case title

    var title: LocalizedStringResource {
        switch self {
        case .dateEdited: "Date Edited"
        case .dateCreated: "Date Created"
        case .title: "Title"
        }
    }

    func date(of item: Item) -> Date {
        switch self {
        case .dateCreated: item.created
        case .dateEdited: item.trashed ?? item.modified
        case .title: item.modified
        }
    }

    /// The items in this order, those that compare equal in the order given.
    func sorted(_ items: [Item]) -> [Item] {
        items.indices.sorted { precedes(items[$0], $0, items[$1], $1) }.map { items[$0] }
    }

    /// `kept` and `fresh` as one list in the order `sorted` gives, where each is in that order already and `positions` says
    /// where each item stands among the items given. An update re-places only the items that changed this way.
    func merged(_ kept: [Item], _ fresh: [Item], positions: [ItemID: Int]) -> [Item] {
        guard !fresh.isEmpty else { return kept }
        var merged: [Item] = []
        merged.reserveCapacity(kept.count + fresh.count)
        var (i, j) = (0, 0)
        while i < kept.count, j < fresh.count {
            if precedes(fresh[j], positions[fresh[j].id] ?? 0, kept[i], positions[kept[i].id] ?? 0) {
                merged.append(fresh[j])
                j += 1
            } else {
                merged.append(kept[i])
                i += 1
            }
        }
        merged.append(contentsOf: kept[i...])
        merged.append(contentsOf: fresh[j...])
        return merged
    }

    private func precedes(_ a: Item, _ aPosition: Int, _ b: Item, _ bPosition: Int) -> Bool {
        switch self {
        case .title:
            switch a.displayTitle.localizedStandardCompare(b.displayTitle) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return aPosition < bPosition
            }
        case .dateEdited, .dateCreated:
            let (first, second) = (date(of: a), date(of: b))
            return first != second ? first > second : aPosition < bPosition
        }
    }
}
