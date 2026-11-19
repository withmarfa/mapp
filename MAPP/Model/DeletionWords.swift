import Foundation

/// The words of the two delete confirmations, worked out for a count. A dialog's title is shown as typed, so the
/// plural is resolved here, through `AttributedString(localized:)`, and the dialog is given the finished sentence.
nonisolated enum DeletionWords {
    /// The title asking to move `count` items to Recently Deleted.
    static func moveTitle(count: Int) -> String {
        AttributedString(localized: "^[Move \(count) item](inflect: true) to Recently Deleted?").text
    }

    /// What the toast says after `count` items moved to Recently Deleted.
    static func movedMessage(count: Int) -> String {
        count == 1
            ? String(localized: "Moved to Recently Deleted")
            : AttributedString(localized: "^[Moved \(count) item](inflect: true) to Recently Deleted").text
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
