import Foundation

/// How a place shows its items. The list keeps the page beside it; the gallery and the table span the window and
/// open an item in their place.
nonisolated enum ItemViewMode: String, Codable, CaseIterable {
    case list, gallery, table

    /// The SF Symbol for the view, in its menu and on the button that opens it.
    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .gallery: "square.grid.2x2"
        case .table: "tablecells"
        }
    }

    /// Whether the items fill the window in place of the list and the page.
    var spansWindow: Bool { self != .list }

    /// The command that returns from an item opened in a view that spans the window.
    var backTitle: LocalizedStringResource {
        switch self {
        case .list: "Back"
        case .gallery: "Back to Gallery"
        case .table: "Back to Table"
        }
    }
}
