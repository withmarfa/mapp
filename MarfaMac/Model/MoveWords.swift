import Foundation

/// The words of the two questions asked before a move, worked out for a name and a count. An alert's title is shown
/// as typed, so the plural is resolved here and the alert is given the finished sentence.
nonisolated enum MoveWords {
    /// The title asking whether to archive what is under the items too. `title` names one item; `beneath` counts the
    /// items under all of them.
    static func archiveTitle(selected: Int, title: String?, beneath: Int) -> String {
        if selected == 1, let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return AttributedString(localized: "Archive “\(title)” and the ^[\(beneath) item](inflect: true) under it?").text
        }
        return AttributedString(localized: "Archive ^[\(selected) item](inflect: true) and the ^[\(beneath) item](inflect: true) under them?").text
    }

    static let archiveMessage = String(localized: "Archived items leave your lists. You can find them in Library > Archive.")

    /// The button that archives only what was chosen.
    static func archiveOnly(selected: Int) -> String {
        selected == 1 ? String(localized: "Archive Only This Item") : String(localized: "Archive Only These Items")
    }

    /// The title asking whether to move items to the Feed that the Feed would let go.
    static func feedTitle(selected: Int, title: String?) -> String {
        if selected == 1, let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return String(localized: "Move “\(title)” to the Feed?")
        }
        return AttributedString(localized: "Move ^[\(selected) item](inflect: true) to the Feed?").text
    }

    /// What the question says: how many of the `selected` items are older than the Feed keeps.
    static func feedMessage(selected: Int, pastWindow: Int) -> String {
        if selected == 1 {
            return String(localized: "The Feed lets items go after a while, and this one is older. It would go to Recently Deleted within the hour.")
        }
        return pastWindow == 1
            ? String(localized: "The Feed lets items go after a while, and 1 of these is older. It would go to Recently Deleted within the hour.")
            : String(localized: "The Feed lets items go after a while, and \(pastWindow) of these are older. They would go to Recently Deleted within the hour.")
    }
}
