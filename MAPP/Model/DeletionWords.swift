import Foundation

/// The words of the two delete confirmations, worked out for a count. A dialog's title is shown as typed, so the
/// plural is resolved here, through `AttributedString(localized:)`, and the dialog is given the finished sentence.
nonisolated enum DeletionWords {
    /// The title asking to move `count` items to Recently Deleted.
    static func moveTitle(count: Int) -> String {
        AttributedString(localized: "^[Move \(count) item](inflect: true) to Recently Deleted?").text
    }

    /// What the question says before moving several items. Where the server says the move also takes more items, it
    /// says at least how many: the server counts only items the sign-in can read. Where that couldn't be read, or
    /// nothing goes with them, it says only that they can be brought back.
    static func moveMessage(alsoTaking count: Int?) -> String {
        guard let count, count > 0 else { return String(localized: "You can bring them back from Recently Deleted.") }
        let also = count == 1
            ? String(localized: "Moving them also moves at least 1 more item that goes with them.")
            : String(localized: "Moving them also moves at least \(count) more items that go with them.")
        return also + " " + String(localized: "You can bring everything back from Recently Deleted.")
    }

    /// What the toast says after `count` items moved to Recently Deleted. One item is named by `title` where it has
    /// one.
    static func movedMessage(count: Int, title: String? = nil) -> String {
        if count == 1 {
            if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                return String(localized: "Moved “\(title)” to Recently Deleted")
            }
            return String(localized: "Moved to Recently Deleted")
        }
        return AttributedString(localized: "^[Moved \(count) item](inflect: true) to Recently Deleted").text
    }

    /// The title of the question before a collection is deleted.
    static func collectionTitle(_ title: String) -> String {
        String(localized: "Delete the collection “\(title)”?")
    }

    /// What deleting a collection does: it goes for every app, and the items in it stay.
    static func collectionMessage(keeping count: Int) -> String {
        let what = String(localized: "The collection is deleted for every app connected to your Marfa server.")
        switch count {
        case 0: return what
        case 1: return what + " " + String(localized: "Its 1 item is kept.")
        default: return what + " " + String(localized: "Its \(count) items are kept.")
        }
    }

    /// The title asking to erase `count` items already in Recently Deleted.
    static func purgeTitle(count: Int) -> String {
        AttributedString(localized: "^[Delete \(count) item](inflect: true) immediately?").text
    }

    /// What erasing `count` items already in Recently Deleted means, in the singular for one.
    static func purgeMessage(count: Int) -> String {
        count == 1
            ? String(localized: "It’s already in Recently Deleted. Deleting it now erases it permanently, and you can’t undo it.")
            : String(localized: "They’re already in Recently Deleted. Deleting them now erases them permanently, and you can’t undo it.")
    }
}
