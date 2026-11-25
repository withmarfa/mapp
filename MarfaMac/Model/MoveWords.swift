import Foundation

/// The words of the two questions asked before a move, worked out for a name and a count. An alert's title is shown
/// as typed, so the plural is resolved here and the alert is given the finished sentence.
nonisolated enum MoveWords {
    /// The title asking whether to archive what is under the items too. `title` names one item; `beneath` counts the
    /// items under all of them.
    static func archiveTitle(selected: Int, title: String?, beneath: Int) -> String {
        if selected == 1 {
            if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                return AttributedString(localized: "Archive “\(title)” and the ^[\(beneath) item](inflect: true) under it?").text
            }
            return AttributedString(localized: "Archive this item and the ^[\(beneath) item](inflect: true) under it?").text
        }
        return AttributedString(localized: "Archive ^[\(selected) item](inflect: true) and the ^[\(beneath) item](inflect: true) under them?").text
    }

    static let archiveMessage = String(localized: "Archived items leave your lists. You can find them in Library > Archive.")

    /// The button that archives only what was chosen.
    static func archiveOnly(selected: Int) -> String {
        selected == 1 ? String(localized: "Archive Only This Item") : String(localized: "Archive Only These Items")
    }

    /// The title asking whether to move or unarchive items that the Feed would let go. `move` is Move to Feed or Unarchive.
    static func feedTitle(_ move: ItemMove, selected: Int, title: String?) -> String {
        let title = selected == 1 ? title?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        if move == .unarchive {
            if let title, !title.isEmpty { return String(localized: "Unarchive “\(title)”?") }
            return AttributedString(localized: "Unarchive ^[\(selected) item](inflect: true)?").text
        }
        if let title, !title.isEmpty { return String(localized: "Move “\(title)” to the Feed?") }
        return AttributedString(localized: "Move ^[\(selected) item](inflect: true) to the Feed?").text
    }

    /// What the question says: how long the Feed keeps the items, where those past the window share one type, how many
    /// of the `selected` items are older, and that they would go to Recently Deleted.
    static func feedMessage(_ move: ItemMove, selected: Int, question: FeedLimitQuestion) -> String {
        let past = question.pastWindow
        let keeps = if let window = question.window {
            AttributedString(localized: "\(window.typePlural) leave the Feed after ^[\(window.days) day](inflect: true)").text
        } else {
            String(localized: "The Feed lets items go after a while")
        }
        let older = if selected == 1 {
            String(localized: ", and this one is older.")
        } else if past == selected {
            selected == 2 ? String(localized: ", and both are older.") : String(localized: ", and all \(selected) are older.")
        } else if past == 1 {
            String(localized: ", and 1 of the \(selected) items is older.")
        } else {
            String(localized: ", and \(past) of the \(selected) items are older.")
        }
        let goes = switch (move == .unarchive, past == 1) {
        case (false, true): String(localized: "It would go to Recently Deleted within the hour.")
        case (false, false): String(localized: "They would go to Recently Deleted within the hour.")
        case (true, true): String(localized: "Unarchived, it would go to Recently Deleted within the hour.")
        case (true, false): String(localized: "Unarchived, they would go to Recently Deleted within the hour.")
        }
        return keeps + older + " " + goes
    }
}
