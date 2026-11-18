import Foundation

/// A count a look can show on the bottom line or as a table column. It is worked out when read from what Marfa holds
/// and never stored, so it cannot go stale in the item.
nonisolated enum CountFact: Hashable, Sendable {
    /// How many items are filed under the item: "4 subtasks" for a type that has a status, "4 items" for any other.
    case children
    /// How many of the children that have a status are finished, completed or canceled: "3 of 7 done".
    case progress
    /// How many items are in a collection: "12 items".
    case members
    /// How many rows the item holds in a table, named as Marfa names it: "214 messages".
    case rows(table: String)

    /// What Marfa is asked, which children and progress share.
    var query: CountQuery {
        switch self {
        case .children, .progress: .children
        case .members: .members
        case .rows(let table): .rows(table: table)
        }
    }

    static let rowsPrefix = "count:rows:"

    /// The words a look stores and exports it as, which a stored look reads the same in every version.
    var word: String {
        switch self {
        case .children: "count:children"
        case .progress: "count:progress"
        case .members: "count:members"
        case .rows(let table): Self.rowsPrefix + table
        }
    }

    init?(word: String) {
        switch word {
        case "count:children": self = .children
        case "count:progress": self = .progress
        case "count:members": self = .members
        default:
            guard word.hasPrefix(Self.rowsPrefix), word.count > Self.rowsPrefix.count else { return nil }
            self = .rows(table: String(word.dropFirst(Self.rowsPrefix.count)))
        }
    }
}
