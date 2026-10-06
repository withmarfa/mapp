import Foundation

/// How the list is ordered: by which date or by title, and whether dated notes fall into sections by day. The
/// defaults here are the only ones; stored settings fall back to them.
nonisolated struct NoteOrder: Equatable {
    var sort: NoteSort = .dateEdited
    var groupsByDate = false
}

nonisolated enum NoteSort: String, CaseIterable {
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
        case .dateEdited, .title: item.modified
        }
    }

    func sorted(_ items: [Item]) -> [Item] {
        switch self {
        case .title:
            items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .dateEdited, .dateCreated:
            items.sorted { date(of: $0) > date(of: $1) }
        }
    }
}
