import Foundation

/// What a view keeps about its board: how large a card is, and whether it says its sub-items. A member left out is the
/// default, so a stored value never holds one that was not chosen.
nonisolated struct BoardChoices: Codable, Hashable, Sendable {
    var compact: Bool?
    var hidesSubItems: Bool?

    var isCompact: Bool { compact ?? false }
    var showsSubItems: Bool { !(hidesSubItems ?? false) }

    /// These choices with the defaults left out, nil where none remain.
    var kept: BoardChoices? {
        var kept = self
        if kept.compact == false { kept.compact = nil }
        if kept.hidesSubItems == false { kept.hidesSubItems = nil }
        return kept == BoardChoices() ? nil : kept
    }
}
