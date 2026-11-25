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
    /// - Read only blocks edits to the connector-managed title, text, properties and type.
    /// - A file has no text and keeps its type. Its page hides the fields in `MarfaMapping.fileFacts`.
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

    /// Why the item can't take a change to its field `key`: what blocks `.fields`, or a fact Marfa sets on a file
    /// (`MarfaMapping.fileFacts`), which a list of mixed types may still show as a column.
    func obstacle(toField key: String) -> BatchSkips.Reason? {
        if let reason = obstacle(to: .fields) { return reason }
        return isFile && MarfaMapping.fileFacts.contains(key) ? .fileFact : nil
    }
}
