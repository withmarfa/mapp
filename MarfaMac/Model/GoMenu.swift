import Foundation

/// What the Go menu lists, from the library and the person's sidebar layout: the places, then the saved views, then the
/// types as the sidebar shows them, then every other type under All Types: the ones after Show More, and the ones the
/// person hid. A saved view the person hid is left out. The menu reaches every type and every place, so a window with
/// the sidebar hidden reaches them.
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
    /// Every other type, subtypes included: those the sidebar keeps behind Show More and those it hides.
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
        types = nodes.prefix(SidebarPlan.shownTypeCount).flatMap { Self.entries(of: $0, under: nil) }
        let listed = Set(types.map(\.id))
        moreTypes = plan.types.flatMap { Self.entries(of: $0, under: nil) }.filter { !listed.contains($0.id) }
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
