import Foundation

/// One section as the sidebar draws it: what the person arranged, and the places it holds.
nonisolated struct SidebarGroupPlan: Identifiable, Equatable {
    let group: SidebarGroup
    /// The places it holds, in order, hidden ones included, so Show can offer them back. Empty for a shortcuts block
    /// and the types section, which list their own kinds of row.
    let members: [SidebarPlace]
    let isEmpty: Bool

    var id: String { group.id }
    var shown: [SidebarPlace] { members.filter { !hiddenKeys.contains($0.key) } }
    let hiddenKeys: Set<String>

    /// The sections of every tab, in the layout's order.
    @MainActor
    static func plans(in library: any ItemLibrary, layout: SidebarLayout, views: [LibraryView], showsTypes: Bool) -> [SidebarGroupPlan] {
        let savedViews = layout.isHidden(.views) ? [] : views.map { SidebarPlace.view($0.id) }
        let candidates = SidebarPlace.destinations + SidebarPlace.builtInViews + savedViews + extras(in: library, layout: layout, views: views)
        return layout.allGroups.map { group in
            let mine = group.holdsPlaces ? candidates.filter { layout.home(of: $0) == group.id } : []
            let members = ordered(mine, in: group.id, layout: layout)
            let hidden = layout.hidden
            let isEmpty: Bool = switch group.kind {
            case .shortcuts: group.shortcuts.isEmpty
            case .types: !showsTypes
            default: !members.contains { !hidden.contains($0.key) }
            }
            return SidebarGroupPlan(group: group, members: members, isEmpty: isEmpty, hiddenKeys: hidden)
        }
    }

    /// The places the person put in a section that are not there by default, kept only while the library still holds
    /// them: a collection or a source deleted, or gone from a sync, leaves its row out and its section as it was. The
    /// layout is not touched, so the row returns with the collection.
    @MainActor
    private static func extras(in library: any ItemLibrary, layout: SidebarLayout, views: [LibraryView]) -> [SidebarPlace] {
        let keys = (layout.homes ?? [:]).keys.sorted()
        guard !keys.isEmpty else { return [] }
        let collections = Set(library.collections.map(\.id))
        let sources = keys.contains { $0.hasPrefix("source:") } ? Set(library.sourceCounts.map(\.code)) : []
        return keys.compactMap(SidebarPlace.init(key:)).filter { place in
            switch place {
            case .collection(let id): collections.contains(id)
            case .source(let code): sources.contains(code)
            default: false
            }
        }
    }

    /// The places as the person ordered them. A section that holds only its default places keeps the sidebar's own
    /// blocks in order, whatever `order` says: the library's indexes, then Inbox, Recents and Favorites, then the saved
    /// views, each block in the person's order within it. Settings > Sidebar moves the blocks as separate lists, so
    /// `order` can name the saved views before Inbox, and a layout from before sections existed must read as it did.
    /// Once something has been put in the section by hand (`SidebarLayout.put`, or dragging its rows in place), the
    /// section is one list in the person's order.
    private static func ordered(_ places: [SidebarPlace], in group: String, layout: SidebarLayout) -> [SidebarPlace] {
        if places.contains(where: { layout.homes?[$0.key] == group }) { return layout.ordered(places) }
        let blocks = [
            SidebarPlace.destinations, SidebarPlace.builtInViews,
            places.filter { if case .view = $0 { true } else { false } },
        ]
        return blocks.flatMap { layout.ordered($0.filter(places.contains)) }
    }
}
