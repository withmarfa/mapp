import Foundation

/// A heading of an item's text, for the panel's Outline.
nonisolated struct OutlineHeading: Identifiable, Hashable, Sendable {
    let level: Int
    /// The words as the page renders them: bold, links and code marks are gone.
    let text: String
    /// The heading's place in the page's own list of headings, from 0, counting each one the item has (a heading with
    /// no words too, though the Outline lists none). The page reveals the heading at this place, so two headings that
    /// read the same each go to their own.
    let index: Int
    var id: Int { index }
}

/// The headings the page last reported for the item on it, and the load they belong to. The page is the only source:
/// it lists the headings as its editor counts them, so the Outline never disagrees with what a row reveals.
nonisolated struct PageOutline: Equatable, Sendable {
    let item: ItemID
    let generation: Int
    /// The headings with words, each with its place in the page's list.
    let headings: [OutlineHeading]

    /// The headings the Outline lists for `id`: none for any other item than the one the page holds.
    func headings(for id: ItemID) -> [OutlineHeading] { item == id ? headings : [] }

    /// What to keep of a list the page reported under `generation`, given the load now on the page and the item it
    /// holds: a list for any other load is stale and kept for nothing.
    static func accepting(_ headings: [OutlineHeading], generation: Int, current: Int, item: ItemID?) -> PageOutline? {
        guard generation == current, let item else { return nil }
        return PageOutline(item: item, generation: generation, headings: headings)
    }
}
