import Foundation

/// How Search Items and the palette's item matches look: whether archived and Feed items are searched, the order of the
/// results and whether each shows the words that matched. One value each in the defaults, synced through the Marfa
/// (`PreferencesMap`). What a server leaves out of search is `SearchLeaveOuts`.
nonisolated enum SearchOptions {
    static let includesArchivedKey = "searchIncludesArchived"
    /// Whether the feed tier is searched, under the word earlier copies stored.
    static let includesInboxKey = "searchIncludesInbox"
    static let orderKey = "searchOrder"
    static let showsSnippetsKey = "searchShowsSnippets"

    static let keys = [includesArchivedKey, includesInboxKey, orderKey, showsSnippetsKey]

    static let includesArchivedStandard = true
    static let includesInboxStandard = true
    static let showsSnippetsStandard = true

    /// The order a search lists its results in: as the copy ranked them, or by when each was last edited.
    nonisolated enum Order: String, CaseIterable, Identifiable, Sendable {
        case bestMatch, mostRecent

        static let standard = Order.bestMatch

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bestMatch: String(localized: "Best Match")
            case .mostRecent: String(localized: "Most Recent")
            }
        }

        /// `items` in this order. Best match is the order the copy answered in; most recent is a stable sort, so equal
        /// dates keep the copy's ranking.
        func ordered(_ items: [Item]) -> [Item] {
            switch self {
            case .bestMatch: items
            case .mostRecent: items.enumerated().sorted { ($1.element.modified, $0.offset) < ($0.element.modified, $1.offset) }.map(\.element)
            }
        }
    }

    /// The stored order; a value this version does not know is the standard.
    static func order(in defaults: UserDefaults = .standard) -> Order {
        defaults.string(forKey: orderKey).flatMap(Order.init) ?? .standard
    }
}
