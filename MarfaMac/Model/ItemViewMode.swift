import Foundation

/// The list keeps the page beside it; collection layouts span the window and open an item in their place.
nonisolated enum ItemViewMode: String, Codable, CaseIterable {
    case list, gallery, table, board, timeline, calendar, digest, map

    /// A stored layout this version does not have, such as one a window or a view kept under an earlier name, reads
    /// as the list, so the window opens instead of losing the rest of what it kept.
    init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .list
    }

    /// The SF Symbol for the view, in its menu and on the button that opens it.
    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .gallery: "square.grid.2x2"
        case .table: "tablecells"
        case .board: "rectangle.split.3x1"
        case .timeline: "calendar.day.timeline.left"
        case .calendar: "calendar"
        case .digest: "rectangle.split.1x2"
        case .map: "map"
        }
    }

    /// The layouts that can show items of these types. Board needs a choice field, and Timeline and Calendar a date field to place
    /// items by, and Map the coordinates (`ItemLocation`); a place without one never offers that layout, instead of offering an empty one.
    static func available(forTypes types: Set<TypeID>, catalogue: Catalogue) -> [ItemViewMode] {
        var modes: [ItemViewMode] = [.list, .gallery, .table]
        if types.contains(where: { !ItemBoardLayout.eligibleFields(of: $0, catalogue: catalogue).isEmpty }) { modes.append(.board) }
        if !ItemTimelineLayout.fields(forTypes: types, catalogue: catalogue).isEmpty { modes += [.timeline, .calendar] }
        modes.append(.digest)
        if MapLayout.canPlace(types: types, catalogue: catalogue) { modes.append(.map) }
        return modes
    }

    /// Whether the items fill the window in place of the list and the page.
    var spansWindow: Bool { self != .list }

    /// The command that returns from an item opened in a view that spans the window.
    var backTitle: LocalizedStringResource {
        switch self {
        case .list: "Back"
        case .gallery: "Back to Gallery"
        case .table: "Back to Table"
        case .board: "Back to Board"
        case .timeline: "Back to Timeline"
        case .calendar: "Back to Calendar"
        case .digest: "Back to Digest"
        case .map: "Back to Map"
        }
    }
}
