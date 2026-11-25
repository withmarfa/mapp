import Foundation

/// What a command or an editor changes of an item, which `Item.obstacle(to:)` judges.
nonisolated enum ItemChange: Hashable, Sendable, CaseIterable {
    /// Library or Feed.
    case tier
    /// Archive and Unarchive.
    case state
    /// To Recently Deleted.
    case delete
    case favorite, tags, collections, links, title, text, fields, type
}

nonisolated extension Item {
    /// Why the item can't take `change`, or nil where it can: the one rule every editor, command and planner asks.
    ///
    /// - In Recently Deleted, nothing changes; Recover and Delete Immediately are not changes here.
    /// - Archived blocks nothing.
    /// - Read only, which a connector keeps, blocks the title, text, fields and type, which its next run puts back. Its
    ///   tags, state and tier it leaves as they stand (`items/natural-key-tags`, `items/tier-upsert`).
    /// - A file has no text and keeps its type. Its title and the fields a person may change are edited as any other's;
    ///   what the server sets (`MarfaMapping.fileFacts`) is never a row.
    /// - A problem, values the library could not read, blocks the writes of the row itself: title, fields, type and
    ///   tier, and the text only where the text could not be read either.
    func obstacle(to change: ItemChange) -> BatchSkips.Reason? {
        if state == .trashed { return .inBin }
        switch change {
        case .state, .delete, .favorite, .tags, .collections, .links:
            return nil
        case .tier:
            return problem == nil ? nil : .cantChange
        case .title, .fields:
            if readOnly { return .readOnly }
            return problem == nil ? nil : .cantChange
        case .text:
            if isFile { return .file }
            if readOnly { return .readOnly }
            return problem?.withholdsText == true ? .cantChange : nil
        case .type:
            if isFile { return .file }
            if readOnly { return .readOnly }
            return problem == nil ? nil : .cantChange
        }
    }

    func allows(_ change: ItemChange) -> Bool { obstacle(to: change) == nil }
}
