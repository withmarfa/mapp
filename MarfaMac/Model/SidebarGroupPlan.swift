import Foundation

/// One section as the sidebar draws it: what the person arranged, and the places it holds.
nonisolated struct SidebarGroupPlan: Identifiable, Equatable {
    let group: SidebarGroup
    /// The places it holds, in order, hidden ones included, so Customize Sidebar can offer them back. Empty for the
    /// Commands and the types section, which list their own kinds of row.
    let members: [SidebarPlace]
    let isEmpty: Bool

    var id: String { group.id }
    var shown: [SidebarPlace] { members.filter { !hiddenKeys.contains($0.key) && !hidesSavedViews(of: $0) } }
    let hiddenKeys: Set<String>

    private func hidesSavedViews(of place: SidebarPlace) -> Bool {
        if case .view = place { hiddenKeys.contains(SidebarLayout.savedViewsKey) } else { false }
    }

    /// The sections of every tab, in the layout's order.
    @MainActor
    static func plans(in library: any ItemLibrary, layout: SidebarLayout, views: [LibraryView], showsTypes: Bool) -> [SidebarGroupPlan] {
        let candidates = SidebarPlace.places + SidebarPlace.pages + views.map { SidebarPlace.view($0.id) }
            + extras(in: library, layout: layout)
        let homes = Dictionary(candidates.map { ($0.key, layout.home(of: $0)) }, uniquingKeysWith: { first, _ in first })
        return layout.allGroups.map { group in
            let mine = group.holdsPlaces ? candidates.filter { homes[$0.key] == group.id } : []
            let members = ordered(mine, in: group.id, layout: layout)
            let plan = SidebarGroupPlan(group: group, members: members, isEmpty: false, hiddenKeys: layout.hidden)
            let isEmpty: Bool = switch group.kind {
            case .shortcuts: group.shortcuts.isEmpty
            case .types: !showsTypes
            default: plan.shown.isEmpty
            }
            return SidebarGroupPlan(group: group, members: members, isEmpty: isEmpty, hiddenKeys: layout.hidden)
        }
    }

    /// The places the person put in a section that have no section of their own, kept only while the library still
    /// holds them: a collection, a source or an item deleted, or gone from a sync, leaves its row out and its section as
    /// it was. The layout is not touched, so the row returns with it.
    @MainActor
    private static func extras(in library: any ItemLibrary, layout: SidebarLayout) -> [SidebarPlace] {
        let keys = (layout.homes ?? [:]).keys.sorted()
        guard !keys.isEmpty else { return [] }
        let collections = Set(library.collections.map(\.id))
        let sources = keys.contains { $0.hasPrefix("source:") } ? Set(library.sourceCounts.map(\.code)) : []
        return keys.compactMap(SidebarPlace.init(key:)).filter { place in
            switch place {
            case .collection(let id): collections.contains(id)
            case .source(let code): sources.contains(code)
            case .item(let id): library.item(id).map { $0.state != .trashed } ?? false
            default: false
            }
        }
    }

    /// The places as the person ordered them. A section that holds only its default places keeps the sidebar's own
    /// blocks in order, whatever `order` says: the Library and the Feed, in that order, then the Library's pages,
    /// then what is pinned, each of those in the person's order within it. Once something has been put in the section by hand
    /// (`SidebarLayout.put`, or dragging its rows in place), the section is one list in the person's order.
    private static func ordered(_ places: [SidebarPlace], in group: String, layout: SidebarLayout) -> [SidebarPlace] {
        if places.contains(where: { layout.homes?[$0.key] == group }) { return layout.ordered(places) }
        // An earlier copy kept the Library and the Feed in two sections, so their order there says nothing here.
        return SidebarPlace.places.filter(places.contains)
            + [SidebarPlace.pages, places.filter(\.isPinnable)].flatMap { layout.ordered($0.filter(places.contains)) }
    }
}
