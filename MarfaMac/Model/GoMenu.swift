import Foundation

/// What the Go menu lists, from the library and the person's sidebar layout: the places, then the saved views, then the
/// types as the sidebar shows them, then every other type under All Types: the ones after Show More, and the ones the
/// person hid. A saved view the person hid is left out. The menu reaches every type and every place, so a window with
/// the sidebar hidden reaches them.
@MainActor
struct GoMenu: Equatable {
    /// One command of the menu.
    struct Entry: Identifiable, Equatable {
        let id: String
        let item: PlaceView
        let title: String
        let icon: RowIcon
    }

    /// The Library, its pages and Archive.
    let places: [Entry]
    /// The Feed and Favorites.
    let builtInViews: [Entry]
    /// The saved views, in the sidebar's order.
    let views: [Entry]
    /// The first `SidebarPlan.shownTypeCount` types with their subtypes, as the sidebar shows them before Show More.
    let types: [Entry]
    /// Every other type, subtypes included: those the sidebar keeps behind Show More and those it hides.
    let moreTypes: [Entry]

    init(library: any ItemLibrary, layout: SidebarLayout) {
        let plan = SidebarPlan(library, layout: layout)
        func entries(_ places: [SidebarPlace]) -> [Entry] {
            places.compactMap { place in
                guard let item = place.opens, let symbol = place.symbol else { return nil }
                return Entry(id: place.key, item: item, title: library.name(of: item), icon: .symbol(symbol))
            }
        }
        places = entries([.library] + SidebarPlace.pages) + [Self.archive(in: library)]
        builtInViews = entries([.feed])
            + [Entry(id: "favorites", item: .favorites, title: library.name(of: .favorites), icon: .symbol("star"))]
        let layouts = ViewLayouts.stored()
        views = plan.views.filter { plan.isShown(.view($0.id)) }.map {
            Entry(
                id: SidebarPlace.view($0.id).key, item: .saved($0.id), title: $0.title,
                icon: .symbol(SidebarPlace.symbol(ofView: $0.id, in: layouts)))
        }
        let nodes = layout.allGroups.contains { $0.kind == .types && layout.hides($0) } ? [] : plan.shownTypes
        types = nodes.prefix(SidebarPlan.shownTypeCount).flatMap { Self.entries(of: $0, under: nil) }
        let listed = Set(types.map(\.id))
        moreTypes = plan.types.flatMap { Self.entries(of: $0, under: nil) }.filter { !listed.contains($0.id) }
    }

    /// The Archive: no sidebar row opens it, so it stands here and in the palette by its own mark.
    static let archiveSymbol = "archivebox"
    static let archiveID = "archive"

    private static func archive(in library: any ItemLibrary) -> Entry {
        Entry(id: archiveID, item: .archive, title: library.name(of: .archive), icon: .symbol(archiveSymbol))
    }

    /// The commands a type row stands for: its own list where it opens one, then each subtype's, named by their path
    /// so a menu with no indentation still tells Session under Agent from Session under Chat.
    private static func entries(of node: TypeNode, under parent: String?) -> [Entry] {
        let title = parent.map { $0 + " > " + node.label } ?? node.label
        let own = node.opens && node.type != nil
            ? [Entry(id: SidebarPlace.type(node.id).key, item: .type(TypeID(node.type?.rawValue ?? node.id)), title: title, icon: .type(node.icon))]
            : []
        return own + node.children.flatMap { entries(of: $0, under: title) }
    }

    /// What choosing `entry` opens now. A view deleted, or a type renamed or removed, since the menu was drawn opens
    /// Items, the place that always exists, and nothing else.
    func destination(of entry: Entry, in library: any ItemLibrary) -> PlaceView {
        if let id = entry.item.savedView {
            return library.views.contains { $0.id == id } ? .saved(id, in: library) : .library
        }
        if case .type(let type) = entry.item.place {
            return Self.holds(library.typeTree, type: type) ? entry.item : .library
        }
        return entry.item
    }

    private static func holds(_ nodes: [TypeNode], type: TypeID) -> Bool {
        nodes.contains { ($0.type == type && $0.count > 0) || holds($0.children, type: type) }
    }
}
