import Foundation

/// What the Go menu lists, from the library and the person's sidebar layout: the places, then the saved views, then the
/// types as the sidebar holds them, then every other type under All Types. A view or a type the person hid in the
/// sidebar is left out; the places stay, so a window with the sidebar hidden reaches them.
@MainActor
struct GoMenu: Equatable {
    /// One command of the menu.
    struct Entry: Identifiable, Equatable {
        let place: SidebarPlace
        let item: SidebarItem
        let title: String
        let icon: RowIcon

        var id: String { place.key }
    }

    /// The Library group's places, then Inbox, Recents and Favorites.
    let places: [Entry]
    /// The saved views, in the sidebar's order.
    let views: [Entry]
    /// The first `SidebarPlan.shownTypeCount` types with their subtypes, as the sidebar shows them before Show More.
    let types: [Entry]
    /// The types after those, which the sidebar keeps behind Show More.
    let moreTypes: [Entry]

    init(library: any ItemLibrary, layout: SidebarLayout) {
        let plan = SidebarPlan(library, layout: layout)
        places = (SidebarPlace.destinations + SidebarPlace.builtInViews).compactMap { place in
            guard let item = place.item, let symbol = place.symbol else { return nil }
            return Entry(place: place, item: item, title: library.name(of: item), icon: .symbol(symbol))
        }
        views = layout.isHidden(.views) ? [] : plan.views.filter { plan.isShown(.view($0.id)) }.map {
            Entry(place: .view($0.id), item: .view($0.id), title: $0.title, icon: .symbol(SidebarPlace.viewSymbol))
        }
        let nodes = layout.isHidden(.types) ? [] : plan.shownTypes
        let count = SidebarPlan.shownTypeCount
        types = nodes.prefix(count).flatMap { Self.entries(of: $0, under: nil) }
        moreTypes = nodes.dropFirst(count).flatMap { Self.entries(of: $0, under: nil) }
    }

    /// The commands a type row stands for: its own list where it opens one, then each subtype's, named by their path
    /// so a menu with no indentation still tells Session under Agent from Session under Chat.
    private static func entries(of node: TypeNode, under parent: String?) -> [Entry] {
        let title = parent.map { $0 + " > " + node.label } ?? node.label
        let own = node.opens && node.type != nil
            ? [Entry(place: .type(node.id), item: .itemType(node.type?.rawValue ?? node.id), title: title, icon: .type(node.icon))]
            : []
        return own + node.children.flatMap { entries(of: $0, under: title) }
    }

    /// What choosing `entry` opens now. A view deleted, or a type renamed or removed, since the menu was drawn opens
    /// Items, the place that always exists, and nothing else.
    func destination(of entry: Entry, in library: any ItemLibrary) -> SidebarItem {
        switch entry.item {
        case .view(let id):
            return library.views.contains { $0.id == id } ? entry.item : .allItems
        case .itemType(let raw):
            return Self.holds(library.typeTree, type: raw) ? entry.item : .allItems
        default:
            return entry.item
        }
    }

    private static func holds(_ nodes: [TypeNode], type raw: String) -> Bool {
        nodes.contains { ($0.type?.rawValue == raw && $0.count > 0) || holds($0.children, type: raw) }
    }
}
