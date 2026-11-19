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
        let defaults = SidebarPlace.destinations + SidebarPlace.builtInViews + savedViews
        let candidates = defaults + extras(in: library, layout: layout, views: views)
        return layout.allGroups.map { group in
            let mine = group.holdsPlaces ? candidates.filter { layout.home(of: $0) == group.id } : []
            let members = ordered(mine, defaults: defaults, layout: layout)
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

    /// The places as the person ordered them. While some have never been placed, the sidebar's own blocks keep their
    /// order, so a layout from before sections existed reads as it did: Inbox, Recents and Favorites before the saved
    /// views, whatever the views' own order.
    private static func ordered(_ places: [SidebarPlace], defaults: [SidebarPlace], layout: SidebarLayout) -> [SidebarPlace] {
        let placed = Set(layout.order)
        if places.allSatisfy({ placed.contains($0.key) }) { return layout.ordered(places) }
        let own = Set(defaults)
        let blocks = [SidebarPlace.destinations, SidebarPlace.builtInViews, defaults.filter { if case .view = $0 { true } else { false } }]
        return blocks.flatMap { layout.ordered($0.filter(places.contains)) } + layout.ordered(places.filter { !own.contains($0) })
    }
}
