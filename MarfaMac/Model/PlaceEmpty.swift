import Foundation

/// What a place says when it holds nothing: a title, one line of fewer than 40 characters under it, and a New button
/// only where a person can make something there. Every layout draws it from here (`PlaceEmptyState`), so the words are decided once.
nonisolated struct PlaceEmpty: Equatable {
    let title: String
    let line: String?
    /// The type the button makes, held by the new item; nil where there is no button.
    let makes: String?
    /// The button's name, such as New Project, with `makes`.
    let buttonTitle: String?
    /// A line is shorter than this many characters.
    static let lineLimit = 40

    /// `offered` is the types a person can make (`QuickAdd.types`), empty while the library cannot be written to or is
    /// not read yet. Only a type's own place has a button, and only for a type that is offered.
    static func of(_ place: PlaceView, in catalogue: Catalogue, offered: [String]) -> PlaceEmpty {
        func plain(_ title: String, _ line: String? = nil) -> PlaceEmpty {
            PlaceEmpty(title: title, line: line, makes: nil, buttonTitle: nil)
        }
        if place.savedView != nil {
            return plain(String(localized: "No Items"), String(localized: "No items match this view."))
        }
        if place.isFavorites {
            return plain(String(localized: "No Favorites"), String(localized: "Items you favorite show here."))
        }
        switch place.place {
        case .feed:
            return plain(String(localized: "Feed Is Empty"), String(localized: "Items from your apps wait here."))
        case .archive:
            return plain(String(localized: "Nothing is archived."))
        case .collection:
            return plain(String(localized: "No Items"), String(localized: "Items you add show here."))
        case .source:
            return plain(String(localized: "No Items"), String(localized: "Nothing from this source yet."))
        case .library:
            return plain(String(localized: "No Items"), String(localized: "Items you make show here."))
        case .type(let type):
            guard catalogue.itemTypes[type] != nil else { return plain(String(localized: "No Items")) }
            let id = type.rawValue
            let plural = catalogue.plural(for: type)
            let label = catalogue.label(for: type)
            let makes = offered.contains(id) ? id : nil
            // A long custom plural would run past the limit, so a fixed short line takes its place.
            let built = String(localized: "\(plural) you make show here.")
            return PlaceEmpty(
                title: String(localized: "No \(plural)"), line: built.count < Self.lineLimit ? built : String(localized: "Nothing here yet."),
                makes: makes, buttonTitle: makes == nil ? nil : String(localized: "New \(label)"))
        case .types:
            return plain(String(localized: "No Types"), String(localized: "Types that hold items show here."))
        case .collections:
            return plain(String(localized: "No Collections"), String(localized: "Collections you make show here."))
        case .sources:
            return plain(String(localized: "No Sources"), String(localized: "Sources show where items came from."))
        }
    }
}
