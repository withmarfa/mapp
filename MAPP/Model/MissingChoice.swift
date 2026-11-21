import Foundation

/// How a pop-up names a choice the library or the Mac no longer has: a place, a type or a font. One wording for all, and
/// never a blank pop-up or a raw identifier. The app falls back to its default meanwhile, and the stored choice is kept.
nonisolated enum MissingChoice {
    /// "Task (Missing)".
    static func label(_ name: String) -> String {
        String(localized: "\(name) (Missing)")
    }

    /// A type's name from its identifier, for a type the catalogue does not hold: the last part, in words.
    static func typeName(_ identifier: String) -> String {
        let last = identifier.split(separator: ".").last.map(String.init) ?? identifier
        let words = last.split(whereSeparator: { $0 == "_" || $0 == "-" }).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? identifier : words.joined(separator: " ")
    }

    /// A stored place's name, for the pop-up that offers a few places and the library's types.
    static func placeName(_ place: SidebarItem) -> String {
        switch place {
        case .itemType(let identifier): typeName(identifier)
        case .collection, .collections: String(localized: "Collection")
        case .view: String(localized: "View")
        case .source, .sources: String(localized: "Source")
        case .favoriteItem: String(localized: "Favorite")
        case .files: String(localized: "Files")
        case .inbox, .recents, .allItems, .favorites: String(localized: "Place")
        }
    }
}
