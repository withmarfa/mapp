import Foundation

/// A view saved on the server (Marfa's `system.view`): a named list of items that every app shows, with the order and
/// grouping it suggests. Which layout shows it is each app's own, so a view holds none.
nonisolated struct LibraryView: Identifiable, Hashable, Sendable {
    let id: ItemID
    var title: String
    /// Changes with every change to the view, so one whose query changed but not its title still differs.
    var version: Int64 = 0
    var query = LibraryViewQuery()
    var sort: [LibraryViewSort] = []
    var group: LibraryViewGroup?

    var settings: LibraryViewSettings {
        LibraryViewSettings(title: title, query: query, sort: sort, group: group)
    }

    /// By title, as the sidebar lists them, with the id settling two of one title.
    static func ordered(_ views: [LibraryView]) -> [LibraryView] {
        views.sorted {
            switch $0.title.localizedStandardCompare($1.title) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: $0.id.rawValue < $1.id.rawValue
            }
        }
    }
}

/// Which items a view lists. Every condition given must hold; an empty or nil one places no condition, except
/// `states`, where nil means active and archived items, as Marfa reads it.
nonisolated struct LibraryViewQuery: Hashable, Sendable {
    /// Each type with its subtypes.
    var types: [TypeID] = []
    /// Nil lists both tiers.
    var tier: Tier?
    var states: Set<ItemState>?
    /// A Marfa filter expression, such as `properties.status eq "open"`.
    var filter: String?
    /// The item and every item below it through `parent-of`.
    var beneath: ItemID?
}

/// One key of a view's order: an item's own field, such as `updated_at`, or `properties.<name>`.
nonisolated struct LibraryViewSort: Hashable, Sendable {
    var field: String
    var ascending: Bool
}

/// What a view's items are grouped by: a field as a sort names it, or a link as `edge[<type>]` or
/// `backref[<type>]`. A date field may be grouped by day, week, month or year.
nonisolated struct LibraryViewGroup: Hashable, Sendable {
    nonisolated enum Bucket: Hashable, Sendable {
        case day, week, month, year
    }

    var field: String
    var bucket: Bucket?
}

/// Everything a new view is saved with.
nonisolated struct LibraryViewSettings: Hashable, Sendable {
    var title: String
    var query = LibraryViewQuery()
    var sort: [LibraryViewSort] = []
    var group: LibraryViewGroup?
}

/// The settings a change replaces, each whole; a nil one is left as it is.
nonisolated struct LibraryViewChange: Hashable, Sendable {
    nonisolated enum Grouping: Hashable, Sendable {
        case set(LibraryViewGroup)
        case clear
    }

    var title: String?
    var query: LibraryViewQuery?
    /// An empty list removes the view's order.
    var sort: [LibraryViewSort]?
    var group: Grouping?

    var isEmpty: Bool { title == nil && query == nil && sort == nil && group == nil }
}

/// Why the server did not save, change or delete a view. Views are written to the server at once, never queued.
nonisolated struct ViewWriteFailure: Error, Hashable, Sendable, LocalizedError {
    nonisolated enum Kind: Hashable, Sendable {
        /// The server could not be reached; nothing was saved.
        case offline
        /// Someone changed the same setting since the view was read.
        case conflict
        /// The server no longer has the view.
        case gone
        /// The key may not write views.
        case notPermitted
        /// The server refused what was sent.
        case refused
    }

    var kind: Kind
    var message: String
    var errorDescription: String? { message }
}
