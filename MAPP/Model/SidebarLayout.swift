import Foundation
import Observation

/// A place the sidebar can show, named by a key that stays the same across launches, so what the person chose to hide
/// or move is found again.
nonisolated enum SidebarPlace: Hashable, Sendable {
    case inbox, recents, all, favorites, sources
    /// The index of items other items are filed under.
    case collections
    /// The block that holds the library's types.
    case types
    /// The saved views in the Views block; hiding it hides every saved view and leaves Inbox, Recents and Favorites.
    case views
    /// A type's row, or a group of types by its stem (`TypeNode.id`).
    case type(String)
    /// One saved view's row, by its item ID.
    case view(ItemID)
    /// One collection's row, by its item ID, which a section the person made holds.
    case collection(ItemID)
    /// One source's row, by its code, which a section the person made holds.
    case source(String)

    /// The places in the Library group, under New and Search, in their default order.
    static let destinations: [SidebarPlace] = [.all, .sources, .collections]
    /// The built-in views at the top of the Views block, in their default order.
    static let builtInViews: [SidebarPlace] = [.inbox, .recents, .favorites]

    /// Every saved view's symbol: a view is a filtered list, whatever it lists.
    static let viewSymbol = "square.stack.3d.up"

    var key: String {
        switch self {
        case .inbox: "inbox"
        case .recents: "recents"
        case .all: "all"
        case .favorites: "favorites"
        case .sources: "sources"
        case .collections: "collections"
        case .types: "types"
        case .views: "views"
        case .type(let id): "type:" + id
        case .view(let id): "view:" + id.rawValue
        case .collection(let id): "collection:" + id.rawValue
        case .source(let code): "source:" + code
        }
    }

    /// The place a key names, or nil for a key that names none.
    init?(key: String) {
        switch key {
        case "inbox": self = .inbox
        case "recents": self = .recents
        case "all": self = .all
        case "favorites": self = .favorites
        case "sources": self = .sources
        case "collections": self = .collections
        case "types": self = .types
        case "views": self = .views
        default:
            guard let colon = key.firstIndex(of: ":") else { return nil }
            let value = String(key[key.index(after: colon)...])
            guard !value.isEmpty else { return nil }
            switch key[..<colon] {
            case "type": self = .type(value)
            case "view": self = .view(ItemID(value))
            case "collection": self = .collection(ItemID(value))
            case "source": self = .source(value)
            default: return nil
            }
        }
    }

    /// The mark of a place that is drawn by symbol; a type draws its own, from the catalogue.
    var symbol: String? {
        switch self {
        case .inbox: "tray"
        case .recents: "clock"
        case .all: "square.grid.2x2"
        case .favorites: "heart"
        case .sources: "antenna.radiowaves.left.and.right"
        case .collections, .collection: "square.stack"
        case .source: "antenna.radiowaves.left.and.right"
        case .types: "rectangle.3.group"
        case .views, .view: Self.viewSymbol
        case .type: nil
        }
    }

    /// What the place opens, where it opens something of its own: the six places and a saved view.
    var item: SidebarItem? {
        switch self {
        case .inbox: .inbox
        case .recents: .recents
        case .all: .allItems
        case .favorites: .favorites
        case .sources: .sources
        case .collections: .collections
        case .view(let id): .view(id)
        case .collection(let id): .collection(id)
        case .source(let code): .source(code)
        case .types, .views, .type: nil
        }
    }

    /// A view's mark takes the color the person chose for it, or this one: the built-in views have their own, and a
    /// saved view is gray. Nil for a place that is not a view.
    var defaultTone: TypeTone? {
        switch self {
        case .inbox: .blue
        case .recents: .gray
        case .favorites: .pink
        case .view: .gray
        default: nil
        }
    }

    /// Whether the row carries a count. Recents always holds the same number, so it says nothing, and the indexes and
    /// a saved view list what the copy holds on their own.
    var showsCount: Bool {
        switch self {
        case .all, .inbox, .favorites, .collection, .source: true
        default: false
        }
    }
}

/// What one library's person chose for the sidebar: the places hidden, the types folded shut, the order of the rest,
/// and the tabs and sections they arranged (`SidebarTabs.swift`). A place the layout does not mention, such as a type the
/// catalogue has just gained, is shown, after the ones that have a position. Everything about tabs, sections and colors
/// is optional, so a layout stored before they existed reads as one tab with the sections the sidebar always had.
nonisolated struct SidebarLayout: Codable, Equatable, Sendable {
    private(set) var hidden: Set<String> = []
    /// The keys of the places the person has placed, in order. Places of different groups share the list, because a
    /// group only ever reads the keys of its own. Keys stay for a collection, a source or a view that is deleted or
    /// missing from a sync, so its row returns to its place with it.
    private(set) var order: [String] = []

    /// The keys of the type rows the person has folded shut.
    private(set) var collapsed: Set<String> = []

    /// The tabs in order; nil until the person adds one, which reads as the one tab, Home.
    var tabs: [SidebarTab]?
    /// Every section of every tab, in order, hidden ones included; nil until the person changes one, which reads as
    /// the sections the sidebar always had, in Home.
    var groups: [SidebarGroup]?
    /// Where a place sits when the person put it in a section, by the place's key and the section's identifier. A
    /// collection or a source has no section of its own, so it shows only where it is put. Keys stay for a collection,
    /// a source or a view that is deleted or missing from a sync, so its row returns with it; only removing the section
    /// they name drops them (`hideGroup`).
    var homes: [String: String]?
    /// The color the person chose for a view's mark, by the place's key and the tone's name.
    var colors: [String: String]?

    init() {}

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hidden = try values.decodeIfPresent(Set<String>.self, forKey: .hidden) ?? []
        order = try values.decodeIfPresent([String].self, forKey: .order) ?? []
        collapsed = try values.decodeIfPresent(Set<String>.self, forKey: .collapsed) ?? []
        tabs = try values.decodeIfPresent([SidebarTab].self, forKey: .tabs)
        groups = try values.decodeIfPresent([SidebarGroup].self, forKey: .groups)
        homes = try values.decodeIfPresent([String: String].self, forKey: .homes)
        colors = try values.decodeIfPresent([String: String].self, forKey: .colors)
    }

    func isHidden(_ place: SidebarPlace) -> Bool { hidden.contains(place.key) }

    func isCollapsed(_ section: SidebarPlace) -> Bool { collapsed.contains(section.key) }

    mutating func setCollapsed(_ section: SidebarPlace, _ isCollapsed: Bool) {
        if isCollapsed { collapsed.insert(section.key) } else { collapsed.remove(section.key) }
    }

    mutating func setHidden(_ place: SidebarPlace, _ isHidden: Bool) {
        if isHidden { hidden.insert(place.key) } else { hidden.remove(place.key) }
    }

    /// Puts a place in a section, last, and shows it.
    mutating func put(_ place: SidebarPlace, in group: String) {
        guard allGroups.contains(where: { $0.id == group && $0.holdsPlaces }) else { return }
        tabs = allTabs
        groups = allGroups
        homes = (homes ?? [:]).merging([place.key: group]) { _, new in new }
        hidden.remove(place.key)
        order.removeAll { $0 == place.key }
        order.append(place.key)
    }

    /// Takes a place out of the sidebar. A place with a section of its own is hidden there, where Show brings it back;
    /// a collection or a source, which has none, is no longer put anywhere.
    mutating func take(_ place: SidebarPlace) {
        switch place {
        case .collection, .source: homes?.removeValue(forKey: place.key)
        default: setHidden(place, true)
        }
    }

    /// A drag of a section's rows in place: moves as `move(_:shown:by:fromOffsets:toOffset:)` does, then records every
    /// place of the section as put there, so the section reads as the one list the person arranged and a row can cross
    /// from one of its blocks to another (`SidebarGroupPlan`).
    mutating func moveInSection(
        _ group: String, places: [SidebarPlace], shown: [SidebarPlace], fromOffsets source: IndexSet, toOffset destination: Int
    ) {
        guard allGroups.contains(where: { $0.id == group && $0.holdsPlaces }) else { return }
        move(places, shown: shown, by: \.key, fromOffsets: source, toOffset: destination)
        tabs = allTabs
        groups = allGroups
        homes = (homes ?? [:]).merging(places.map { ($0.key, group) }) { _, new in new }
    }

    /// `places` with the ones in `shown` moved as a list showing only those would move them. The hidden ones keep
    /// their slots, so showing one again puts it back where it was.
    mutating func move<Place>(
        _ places: [Place], shown: [Place], by key: (Place) -> String, fromOffsets source: IndexSet, toOffset destination: Int
    ) {
        let shownKeys = Set(shown.map(key))
        var visible = ordered(shown, by: key).map(key)
        let moved = source.sorted().map { visible[$0] }
        let target = destination - source.filter { $0 < destination }.count
        for index in source.sorted().reversed() { visible.remove(at: index) }
        visible.insert(contentsOf: moved, at: min(target, visible.count))
        var next = visible.makeIterator()
        let keys = ordered(places, by: key).map(key).map { shownKeys.contains($0) ? next.next()! : $0 }
        order = order.filter { !keys.contains($0) } + keys
    }

    /// Keeps `places` in the order given as the person's own, whatever order was stored for them.
    mutating func record(_ places: [SidebarPlace]) {
        let keys = places.map(\.key)
        let moving = Set(keys)
        order = order.filter { !moving.contains($0) } + keys
    }

    /// `places` as the person ordered them; the ones never placed follow, in the order given.
    func ordered<Place>(_ places: [Place], by key: (Place) -> String) -> [Place] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let placed = places.filter { rank[key($0)] != nil }.sorted { rank[key($0)]! < rank[key($1)]! }
        return placed + places.filter { rank[key($0)] == nil }
    }

    func ordered(_ places: [SidebarPlace]) -> [SidebarPlace] { ordered(places, by: \.key) }

    /// Moves the places at `source` to `destination` within `places`, as a list's drag does, and keeps the result.
    mutating func move(_ places: [SidebarPlace], fromOffsets source: IndexSet, toOffset destination: Int) {
        move(places, by: \.key, fromOffsets: source, toOffset: destination)
    }

    mutating func move<Place>(_ places: [Place], by key: (Place) -> String, fromOffsets source: IndexSet, toOffset destination: Int) {
        move(places, shown: places, by: key, fromOffsets: source, toOffset: destination)
    }
}

/// What the sidebar shows for a library, from the library and the person's layout: one list for each part of the
/// sidebar, in order, hidden places included so Settings can offer them back.
@MainActor
struct SidebarPlan {
    /// The places in the Library group: every item, the sources they came from, and the collections they are filed
    /// under. Files are included in Items.
    let destinations: [SidebarPlace]
    /// The built-in views at the top of the Views block: Inbox, Recents and Favorites. They are places, not saved
    /// views, and no data model sits behind the grouping.
    let builtInViews: [SidebarPlace]
    /// The saved views in the Views block, where the server has saved any views the library can read, then the Types
    /// block, where the library holds any types.
    let library: [SidebarPlace]
    /// The types the Types block lists, nested. The person orders the top rows; the rows under one keep the order
    /// of their items.
    let types: [TypeNode]
    /// The saved views, in the person's order, hidden ones included. Views the person never placed follow by title.
    let views: [LibraryView]
    let layout: SidebarLayout
    /// The tabs, in order.
    let tabs: [SidebarTab]
    /// Every section of every tab, in order, hidden ones included, with the places each holds.
    let groups: [SidebarGroupPlan]

    init(_ library: any ItemLibrary, layout: SidebarLayout) {
        let started = ContinuousClock.now
        defer { Cost.record(.sidebarPlan, since: started) }
        self.layout = layout
        destinations = layout.ordered(SidebarPlace.destinations)
        builtInViews = layout.ordered(SidebarPlace.builtInViews)
        views = layout.ordered(library.views, by: { SidebarPlace.view($0.id).key })
        types = layout.ordered(library.typeTree, by: { SidebarPlace.type($0.id).key })
        self.library = (library.views.isEmpty ? [] : [.views]) + (types.isEmpty ? [] : [.types])
        tabs = layout.allTabs
        let showsTypes = !layout.isHidden(.types) && types.contains { !layout.isHidden(.type($0.id)) }
        groups = SidebarGroupPlan.plans(in: library, layout: layout, views: views, showsTypes: showsTypes)
    }

    /// The sections of a tab that are shown, in order. A person's own or built-in section with nothing in it stays
    /// out unless `customizing`, which keeps every one so something can be put in it.
    func groups(in tab: String, customizing: Bool) -> [SidebarGroupPlan] {
        groups.filter { layout.tabID(of: $0.group) == tab && !$0.group.isHidden && (customizing || !$0.isEmpty) }
    }

    func isShown(_ place: SidebarPlace) -> Bool { !layout.isHidden(place) }

    /// The type rows not hidden, at every level; hiding a row hides what is under it.
    var shownTypes: [TypeNode] { Self.shown(types, by: self) }

    /// A shown type row as the list draws it: one line, with how deep it sits and whether it is folded open.
    nonisolated struct TypeRow: Identifiable, Equatable {
        let node: TypeNode
        let depth: Int
        let isExpanded: Bool

        var id: String { node.id }
        var isExpandable: Bool { !node.children.isEmpty }
    }

    /// The shown types as the rows the list draws, in order: a row, then, where it is folded open, the rows under
    /// it, one level deeper. Rows folded shut leave their subtypes out.
    var typeRows: [TypeRow] { Self.rows(shownTypes, depth: 0, layout: layout) }

    /// An arrow key on the selected type row.
    enum Arrow { case left, right }

    /// What an arrow key does.
    enum ArrowOutcome: Equatable {
        /// Fold the row of this identifier shut (`collapsed`) or open.
        case fold(String, collapsed: Bool)
        /// Select this row.
        case select(SidebarItem)
    }

    /// What the system's outline does with an arrow key, for the selected type row, or nil where it does nothing.
    /// Left folds a row that is open, and otherwise selects the row's parent. Right opens a row that is folded, and
    /// otherwise selects the first row under it that opens a list. A group has no list to select, so a parent that
    /// is one is passed over for the nearest above it that has.
    func outcome(of arrow: Arrow, selected: SidebarItem?) -> ArrowOutcome? {
        let path = path(to: selected)
        guard let node = path.last else { return nil }
        let isExpanded = !layout.isCollapsed(.type(node.id))
        switch arrow {
        case .left:
            if !node.children.isEmpty, isExpanded { return .fold(node.id, collapsed: true) }
            return path.dropLast().last(where: \.opens).flatMap(Self.item).map { .select($0) }
        case .right:
            guard !node.children.isEmpty else { return nil }
            if !isExpanded { return .fold(node.id, collapsed: false) }
            return node.children.first(where: \.opens).flatMap(Self.item).map { .select($0) }
        }
    }

    /// The row to select as `id` folds shut, when the selected type is somewhere under it: the nearest row that
    /// opens a list, from that row upward. Nil where the selection stays as it is.
    func selectionAfterFolding(_ id: String, selected: SidebarItem?) -> SidebarItem? {
        let path = path(to: selected)
        guard let index = path.firstIndex(where: { $0.id == id }), index < path.count - 1 else { return nil }
        return path[...index].last(where: \.opens).flatMap(Self.item)
    }

    private static func item(_ node: TypeNode) -> SidebarItem? {
        node.type.map { .itemType($0.rawValue) }
    }

    /// The shown rows from the top of the tree down to the one `selected` names, or none where it names no shown row.
    private func path(to selected: SidebarItem?) -> [TypeNode] {
        guard let selected else { return [] }
        func search(_ nodes: [TypeNode]) -> [TypeNode]? {
            for node in nodes {
                if Self.item(node) == selected { return [node] }
                if let found = search(node.children) { return [node] + found }
            }
            return nil
        }
        return search(shownTypes) ?? []
    }

    private static func rows(_ nodes: [TypeNode], depth: Int, layout: SidebarLayout) -> [TypeRow] {
        nodes.flatMap { node in
            let isExpanded = !layout.isCollapsed(.type(node.id))
            return [TypeRow(node: node, depth: depth, isExpanded: isExpanded)]
                + (isExpanded ? rows(node.children, depth: depth + 1, layout: layout) : [])
        }
    }

    /// The Types block shows this many types, with their subtypes, until Show More.
    static let shownTypeCount = 6

    /// The first `limit` types of `rows`, each with the subtype rows folded open under it, and whether more types
    /// follow. With `showsAll` every row stays. A type's subtypes are never cut off from it, and do not count.
    static func limited(
        _ rows: [TypeRow], showsAll: Bool, limit: Int = shownTypeCount
    ) -> (rows: [TypeRow], hasMore: Bool) {
        let topLevel = rows.filter { $0.depth == 0 }.count
        guard topLevel > limit else { return (rows, false) }
        guard !showsAll else { return (rows, true) }
        var seen = 0
        let kept = rows.prefix { row in
            if row.depth == 0 { seen += 1 }
            return seen <= limit
        }
        return (Array(kept), true)
    }

    private static func shown(_ nodes: [TypeNode], by plan: SidebarPlan) -> [TypeNode] {
        nodes.filter { plan.isShown(.type($0.id)) }.map { node in
            TypeNode(id: node.id, type: node.type, label: node.label, icon: node.icon, count: node.count, total: node.total,
                     children: shown(node.children, by: plan))
        }
    }
}

/// The layouts a person has made, one for each library, kept in the defaults. A library is named by its server's
/// address, so each keeps its own. A saved layout that cannot be read, such as one a later version of the app wrote,
/// is moved aside under a key of its own, kept and never removed, and reported; the other libraries keep theirs, that
/// library's sidebar starts from the default, and changes are saved as before.
@Observable @MainActor
final class SidebarLayouts {
    private static let defaultsKey = "sidebarLayouts"
    /// Each entry is stored data that could not be read, in the order it was found.
    static let setAsideKey = "sidebarLayoutsSetAside"

    @ObservationIgnored private let defaults: UserDefaults
    private var layouts: [String: SidebarLayout]

    init(defaults: UserDefaults = .standard, reporting: Reporting = .shared) {
        self.defaults = defaults
        guard let saved = defaults.data(forKey: Self.defaultsKey) else {
            layouts = [:]
            return
        }
        let (readable, unreadable) = Self.read(saved)
        layouts = readable
        guard let unreadable else { return }
        defaults.set((defaults.array(forKey: Self.setAsideKey) as? [Data] ?? []) + [unreadable], forKey: Self.setAsideKey)
        save()
        Telemetry.sidebarLayoutsUnreadable(reporting: reporting)
    }

    /// The layouts that can be read, and the stored data of those that cannot: the whole of it where it is not an
    /// object of layouts at all, otherwise an object of the unreadable entries alone.
    private static func read(_ saved: Data) -> (readable: [String: SidebarLayout], unreadable: Data?) {
        if let layouts = try? JSONDecoder().decode([String: SidebarLayout].self, from: saved) { return (layouts, nil) }
        guard let entries = (try? JSONSerialization.jsonObject(with: saved)) as? [String: Any] else { return ([:], saved) }
        var readable: [String: SidebarLayout] = [:]
        var unreadable: [String: Any] = [:]
        for (library, entry) in entries {
            if let data = try? JSONSerialization.data(withJSONObject: entry, options: .fragmentsAllowed),
               let layout = try? JSONDecoder().decode(SidebarLayout.self, from: data) {
                readable[library] = layout
            } else {
                unreadable[library] = entry
            }
        }
        let kept = (try? JSONSerialization.data(withJSONObject: unreadable, options: .sortedKeys)) ?? saved
        return (readable, kept)
    }

    func layout(for library: String) -> SidebarLayout { layouts[library] ?? SidebarLayout() }

    func update(_ library: String, _ change: (inout SidebarLayout) -> Void) {
        var layout = layout(for: library)
        change(&layout)
        guard layout != self.layout(for: library) else { return }
        layouts[library] = layout
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(layouts) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
