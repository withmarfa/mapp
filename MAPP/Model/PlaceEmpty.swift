import Foundation

/// What a place says when it holds nothing: a title, one line of fewer than 40 characters under it, and a New button
/// only where a person can make something there. Every layout draws it from here (`PlaceEmptyState`), so the words are decided once.
nonisolated struct PlaceEmpty: Equatable {
    let title: String
    let line: String?
    /// The type the button makes, held by quick add; nil where there is no button.
    let makes: String?
    /// The button's name, such as New Project, with `makes`.
    let buttonTitle: String?

    /// `offered` is the types a person can make (`QuickAdd.types`), empty while the library cannot be written to or is
    /// not read yet. Only a type's own place has a button, and only for a type that is offered.
    static func of(_ place: SidebarItem, in catalogue: Catalogue, offered: [String]) -> PlaceEmpty {
        func plain(_ title: String, _ line: String? = nil) -> PlaceEmpty {
            PlaceEmpty(title: title, line: line, makes: nil, buttonTitle: nil)
        }
        switch place {
        case .inbox:
            return plain(String(localized: "Inbox Is Empty"), String(localized: "Items from your apps wait here."))
        case .favorites:
            return plain(String(localized: "No Favorites"), String(localized: "Items you favorite show here."))
        case .recents:
            return plain(String(localized: "No Recent Items"), String(localized: "Items you edit show here."))
        case .files:
            return plain(String(localized: "No Files"), String(localized: "Files you add show here."))
        case .collection:
            return plain(String(localized: "No Items"), String(localized: "Items you add show here."))
        case .source:
            return plain(String(localized: "No Items"), String(localized: "Nothing from this source yet."))
        case .view:
            return plain(String(localized: "No Items"), String(localized: "No items match this view."))
        case .allItems:
            return plain(String(localized: "No Items"), String(localized: "Items you make show here."))
        case .itemType(let id):
            guard catalogue.itemTypes[TypeID(id)] != nil else { return plain(String(localized: "No Items")) }
            let plural = catalogue.plural(for: TypeID(id))
            let label = catalogue.label(for: TypeID(id))
            let makes = offered.contains(id) ? id : nil
            return PlaceEmpty(
                title: String(localized: "No \(plural)"), line: String(localized: "\(plural) you make show here."),
                makes: makes, buttonTitle: makes == nil ? nil : String(localized: "New \(label)"))
        case .collections, .sources, .favoriteItem, .recentlyDeleted:
            return plain(String(localized: "No Items"))
        }
    }
}
