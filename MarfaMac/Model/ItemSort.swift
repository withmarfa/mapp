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

    func sorted(_ items: [Item]) -> [Item] {
        switch self {
        case .title:
            items.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        case .dateEdited, .dateCreated:
            items.sorted { date(of: $0) > date(of: $1) }
        }
    }
}
