import Foundation
import Marfa
import Observation

/// A row the sidebar can show, named by a key that stays the same across launches, so what the person chose to hide
/// or move is found again. The Library and the Feed keep the keys earlier copies gave All Items and Inbox, and the
/// Collections and Sources pages keep theirs, so a layout arranged then reads as it was. Words this copy no longer
/// shows as rows (`favorites`, `recents`, and `views` and `types` in `hidden`) are left where they are stored.
nonisolated enum SidebarPlace: Hashable, Sendable {
    case library, feed
    /// Library › Types, Library › Collections and Library › Sources, which a person can add under the Library.
    case types, collections, sources
    /// A type's row, or a group of types by its stem (`TypeNode.id`).
    case type(String)
    /// One saved view's row, by its item ID, which opens the view at its home.
    case view(ItemID)
    /// One collection's row, by its item ID.
    case collection(ItemID)
    /// One source's row, by its code.
    case source(String)
    /// One pinned item's row, by its item ID, which opens the item.
    case item(ItemID)

    /// The Library and the Feed, in their default order: the zone under Search and New.
    static let places: [SidebarPlace] = [.library, .feed]
    /// The pages of the Library a person can add under it, in their default order.
    static let pages: [SidebarPlace] = [.types, .collections, .sources]

    var key: String {
        switch self {
        case .library: "all"
        case .feed: "inbox"
        case .types: "index:types"
        case .collections: "collections"
        case .sources: "sources"
        case .type(let id): "type:" + id
        case .view(let id): "view:" + id.rawValue
        case .collection(let id): "collection:" + id.rawValue
        case .source(let code): "source:" + code
        case .item(let id): "item:" + id.rawValue
        }
    }

    /// The place a key names, or nil for a key that names none.
    init?(key: String) {
        switch key {
        case "all": self = .library
        case "inbox": self = .feed
        case "index:types": self = .types
        case "collections": self = .collections
        case "sources": self = .sources
        default:
            guard let colon = key.firstIndex(of: ":") else { return nil }
            let value = String(key[key.index(after: colon)...])
            guard !value.isEmpty else { return nil }
            switch key[..<colon] {
            case "type": self = .type(value)
            case "view": self = .view(ItemID(value))
            case "collection": self = .collection(ItemID(value))
            case "source": self = .source(value)
            case "item": self = .item(ItemID(value))
            default: return nil
            }
        }
    }

    /// The gray symbol of a place that has one of its own; a view, a collection, a source, a type and an item take
    /// theirs from the library (`SidebarContent`).
    var symbol: String? {
        switch self {
        case .library: "square.grid.2x2"
        case .feed: "water.waves"
        case .types: "square.on.square"
        case .collections: "square.stack"
        case .sources: "antenna.radiowaves.left.and.right"
        case .type, .view, .collection, .source, .item: nil
        }
    }

    /// What the row opens, where it opens a place: a saved view opens at its home, which `Browser.show` finds. A
    /// pinned item opens the item, which is no place.
    var opens: PlaceView? {
        switch self {
        case .library: .library
        case .feed: .feed
        case .types: .types
        case .collections: .collections
        case .sources: .sources
        case .type(let id): .type(TypeID(id))
        case .view(let id): .saved(id)
        case .collection(let id): .collection(id)
        case .source(let code): .source(code)
        case .item: nil
        }
    }

    /// A saved view's mark: the symbol of the layout this Mac keeps for it, or a list's.
    static func symbol(ofView id: ItemID, in layouts: ViewLayouts) -> String {
        (layouts.settings(for: id)?.layout ?? .list).symbol
    }

    /// Whether the row is one a person pins: a view, a collection, a source or an item. What an earlier copy placed
    /// under its Library or Views sections is read under Pinned when it is one of these.
    var isPinnable: Bool {
        switch self {
        case .view, .collection, .source, .item: true
        default: false
        }
    }

    /// Whether the row is in the sidebar only where the person put it, and is no longer put anywhere when taken out.
    /// The rest are hidden where they stand, so showing them puts them back.
    var showsOnlyWherePut: Bool {
        switch self {
        case .collection, .source, .item, .types, .collections, .sources: true
        default: false
        }
    }
}

/// What one library's person chose for the sidebar: the places hidden, the types folded shut, the order of the rest,
/// and the tabs and sections they arranged (`SidebarTabs.swift`). A place the layout does not mention, such as a type the
/// catalogue has just gained, is shown, after the ones that have a position. Everything about tabs and sections is
/// optional, so a layout stored before they existed reads as one tab with the sections the sidebar starts with.
///
/// Any copy of the app may read the layout, so nothing this copy cannot read is dropped: a section of a kind it does not
/// know is written back where it was, a member it does not know is kept, and the keys of `hidden`, `shown`, `order`,
/// `collapsed`, `homes` and `colors` are kept whatever they name.
nonisolated struct SidebarLayout: Codable, Equatable, Sendable {
    private(set) var hidden: Set<String> = []
    /// The places the person showed where a wider word still hides them: a saved view while `views` is in `hidden`,
    /// or what an earlier copy's hidden Library or Views section held. A view this Mac does not know yet stays hidden.
    private(set) var shown: Set<String> = []
    /// The keys of the places the person has placed, in order. Places of different groups share the list, because a
    /// group only ever reads the keys of its own. Keys stay for a collection, a source or a view that is deleted or
    /// missing from a sync, so its row returns to its place with it.
    private(set) var order: [String] = []

    /// The keys of the type rows the person has folded shut.
    private(set) var collapsed: Set<String> = []

    /// The tabs in order; nil until the person adds one, which reads as the one tab, Home.
    var tabs: [SidebarTab]?
    /// Every section of every tab this copy can read, in order, hidden ones included; nil until the person changes
    /// one, which reads as the sections the sidebar starts with, in Home.
    var groups: [SidebarGroup]?
    /// Where a place sits when the person put it in a section, by the place's key and the section's identifier. A
    /// collection, a source or an item has no section of its own, so it shows only where it is put. Keys stay for a
    /// place that is deleted or missing from a sync, so its row returns with it; only removing the section they name
    /// drops them (`hideGroup`).
    var homes: [String: String]?
    /// The colors an earlier copy let a person give a view's mark, by the place's key. This copy draws every mark gray
    /// or in its type's own color, and keeps them for the copies that read them.
    private var colors: [String: String]?
    /// The sections this copy cannot read, such as a kind a later copy added, by their position among all the sections,
    /// written back there so that copy keeps them.
    private var laterGroups: [Int: JSONValue] = [:]
    /// The Library and Views sections an earlier copy made and the person had hidden, which this copy keeps as written:
    /// what they held stays hidden (`isHidden`).
    private var hiddenEarlierGroupIDs: Set<String> = []
    /// The earlier Views section, which held every saved view not put in another section.
    private var earlierViewsID: String?
    private var laterMembers = SidebarLaterMembers()

    init() {}

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case hidden, shown, order, collapsed, tabs, groups, homes, colors
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        laterMembers = try SidebarLaterMembers(from: decoder, known: CodingKeys.allCases.map(\.rawValue))
        hidden = try values.decodeIfPresent(Set<String>.self, forKey: .hidden) ?? []
        shown = (try values.decodeIfPresent(Set<String>.self, forKey: .shown) ?? []).subtracting(hidden)
        order = try values.decodeIfPresent([String].self, forKey: .order) ?? []
        collapsed = try values.decodeIfPresent(Set<String>.self, forKey: .collapsed) ?? []
        tabs = try values.decodeIfPresent([SidebarTab].self, forKey: .tabs)
        if let stored = try values.decodeIfPresent([JSONValue].self, forKey: .groups) {
            var known: [SidebarGroup] = []
            var earlier: [EarlierGroup.Kind: EarlierGroup.Found] = [:]
            for (index, raw) in stored.enumerated() {
                let data = try JSONEncoder().encode(raw)
                if let group = try? JSONDecoder().decode(SidebarGroup.self, from: data) {
                    known.append(group)
                } else {
                    laterGroups[index] = raw
                    if let group = try? JSONDecoder().decode(EarlierGroup.self, from: data) {
                        if group.isHidden { hiddenEarlierGroupIDs.insert(group.id) }
                        if earlier[group.kind] == nil { earlier[group.kind] = EarlierGroup.Found(group: group, at: known.count, stored: index) }
                    }
                }
            }
            earlierViewsID = earlier[.views]?.group.id
            groups = Self.reading(known, earlier: earlier, firstTab: tabs?.first?.id ?? SidebarTab.homeID)
        }
        homes = try values.decodeIfPresent([String: String].self, forKey: .homes)
        colors = try values.decodeIfPresent([String: String].self, forKey: .colors)
    }

    /// The sections an earlier copy arranged, read into this copy's: its Library section gives way to the Library and
    /// the Feed, without a heading, and its Views section to Pinned, each in the tab and at the place the earlier one
    /// had, Pinned with the person's name for it. Pinned is never hidden for it: what the hidden section held is hidden
    /// row by row (`isHidden`), so what the person showed elsewhere stays shown. A layout that has them already is
    /// read as it is.
    private static func reading(
        _ known: [SidebarGroup], earlier: [EarlierGroup.Kind: EarlierGroup.Found], firstTab: String
    ) -> [SidebarGroup] {
        let views = earlier[.views]
        let library = earlier[.library]
        var added: [(group: SidebarGroup, found: EarlierGroup.Found?)] = []
        if !known.contains(where: { $0.kind == .pinned }) {
            var pinned = SidebarGroup(id: SidebarGroup.pinnedID, kind: .pinned, tab: views?.group.tab ?? firstTab)
            pinned.title = views?.group.title
            added.append((pinned, views))
        }
        if !known.contains(where: { $0.kind == .places }) {
            let tab = library?.group.tab ?? views?.group.tab ?? firstTab
            added.append((SidebarGroup(id: SidebarGroup.placesID, kind: .places, tab: tab), library))
        }
        // Each goes where its earlier section stood among the sections this copy reads, in the order they were stored,
        // so a section stored between them stays between them.
        var groups = known
        var inserted = 0
        for (group, found) in added.sorted(by: { ($0.found?.at ?? .max, $0.found?.stored ?? .max) < ($1.found?.at ?? .max, $1.found?.stored ?? .max) }) {
            let at: Int
            if let found {
                at = min(found.at + inserted, groups.count)
            } else if group.kind == .places {
                at = groups.firstIndex { $0.kind == .shortcuts && $0.tab == group.tab }.map { $0 + 1 }
                    ?? groups.firstIndex { $0.tab == group.tab } ?? groups.count
            } else {
                at = groups.count
            }
            groups.insert(group, at: at)
            inserted += 1
        }
        return groups
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        // Sets are written sorted, so a change elsewhere rewrites none of them.
        try values.encode(hidden.sorted(), forKey: .hidden)
        let shown = shown.subtracting(hidden)
        if !shown.isEmpty { try values.encode(shown.sorted(), forKey: .shown) }
        try values.encode(order, forKey: .order)
        try values.encode(collapsed.sorted(), forKey: .collapsed)
        try values.encodeIfPresent(tabs, forKey: .tabs)
        if groups != nil || !laterGroups.isEmpty {
            var all = try (groups ?? []).map { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode($0)) }
            for (index, raw) in laterGroups.sorted(by: { $0.key < $1.key }) { all.insert(raw, at: min(index, all.count)) }
            try values.encode(all, forKey: .groups)
        }
        try values.encodeIfPresent(homes, forKey: .homes)
        try values.encodeIfPresent(colors, forKey: .colors)
        try laterMembers.encode(to: encoder)
    }

    func isHidden(_ place: SidebarPlace) -> Bool {
        if hidden.contains(place.key) { return true }
        guard !shown.contains(place.key) else { return false }
        if case .view = place, hidden.contains(Self.savedViewsKey) { return true }
        return cameFromHiddenSection(place)
    }

    /// Whether an earlier copy held the place in a Library or Views section the person had hidden: put there, or a
    /// saved view put nowhere, which its Views section held. A row put in a section that is gone is not held by it.
    private func cameFromHiddenSection(_ place: SidebarPlace) -> Bool {
        guard place.isPinnable || SidebarPlace.pages.contains(place), !hiddenEarlierGroupIDs.isEmpty else { return false }
        if let put = homes?[place.key] { return hiddenEarlierGroupIDs.contains(put) }
        guard case .view = place, let views = earlierViewsID else { return false }
        return hiddenEarlierGroupIDs.contains(views)
    }

    /// The word an earlier copy kept in `hidden` for Hide Views from Sidebar, which hid every saved view.
    static let savedViewsKey = "views"
    /// The word an earlier copy kept in `hidden` when Settings hid the Types section.
    static let typesSectionKey = "types"

    /// Forgets that an earlier copy hid the Types section, as showing it again does.
    mutating func showTypesSection() { hidden.remove(Self.typesSectionKey) }

    func isCollapsed(_ section: SidebarPlace) -> Bool { collapsed.contains(section.key) }

    mutating func setCollapsed(_ section: SidebarPlace, _ isCollapsed: Bool) {
        if isCollapsed { collapsed.insert(section.key) } else { collapsed.remove(section.key) }
    }

    /// Hides or shows one place. Showing one that a wider word hides (`shown`) keeps that word for the rest.
    mutating func setHidden(_ place: SidebarPlace, _ isHidden: Bool) {
        if isHidden {
            shown.remove(place.key)
            hidden.insert(place.key)
        } else {
            hidden.remove(place.key)
            if self.isHidden(place) { shown.insert(place.key) }
        }
    }

    /// Puts a place in a section, last, and shows it.
    mutating func put(_ place: SidebarPlace, in group: String) {
        guard allGroups.contains(where: { $0.id == group && $0.holds(place) }) else { return }
        tabs = allTabs
        groups = allGroups
        homes = (homes ?? [:]).merging([place.key: group]) { _, new in new }
        setHidden(place, false)
        order.removeAll { $0 == place.key }
        order.append(place.key)
    }

    /// Takes a place out of the sidebar. A place with a section of its own is hidden there, where it can be added
    /// again; a collection, a source, an item or a page of the Library, which has none, is no longer put anywhere.
    mutating func take(_ place: SidebarPlace) {
        if place.showsOnlyWherePut {
            homes?.removeValue(forKey: place.key)
            if homes?.isEmpty == true { homes = nil }
        } else {
            setHidden(place, true)
        }
    }

    /// A drag of a section's rows in place: moves as `move(_:shown:by:fromOffsets:toOffset:)` does, then records the
    /// rows dragged as put there, so the section reads as the one list the person arranged and a row can cross from
    /// one of its blocks to another (`SidebarGroupPlan`). Every other row keeps the home it has.
    mutating func moveInSection(
        _ group: String, places: [SidebarPlace], shown: [SidebarPlace], fromOffsets source: IndexSet, toOffset destination: Int
    ) {
        guard allGroups.contains(where: { $0.id == group && $0.holdsPlaces }),
              move(places, shown: shown, by: \.key, fromOffsets: source, toOffset: destination) else { return }
        tabs = allTabs
        groups = allGroups
        let dragged = source.filter(shown.indices.contains).map { (shown[$0].key, group) }
        homes = (homes ?? [:]).merging(dragged) { _, new in new }
    }

    /// `places`, in the order they are drawn, with the ones in `shown` moved as the list showing only those moves
    /// them: the offsets are of `shown` as given. The hidden ones keep their slots, so showing one again puts it back
    /// where it was. A move that leaves the shown order as it was changes nothing, and returns false.
    @discardableResult
    mutating func move<Place>(
        _ places: [Place], shown: [Place], by key: (Place) -> String, fromOffsets source: IndexSet, toOffset destination: Int
    ) -> Bool {
        let shownKeys = Set(shown.map(key))
        let before = shown.map(key)
        let source = source.filter(before.indices.contains)
        var visible = before
        let moved = source.map { visible[$0] }
        let target = destination - source.filter { $0 < destination }.count
        for index in source.reversed() { visible.remove(at: index) }
        visible.insert(contentsOf: moved, at: max(0, min(target, visible.count)))
        guard visible != before else { return false }
        var next = visible.makeIterator()
        let keys = places.map(key).map { shownKeys.contains($0) ? next.next()! : $0 }
        order = order.filter { !keys.contains($0) } + keys
        return true
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

/// A Library or Views section as an earlier copy stored it, read only for where it was and what it was called.
private nonisolated struct EarlierGroup: Decodable {
    enum Kind: String, Decodable { case library, views }

    /// Where it was found: `at` among the sections this copy reads, `stored` among all.
    struct Found {
        let group: EarlierGroup
        let at: Int
        let stored: Int
    }

    let id: String
    let kind: Kind
    let tab: String
    var title: String?
    var isHidden = false

    private enum CodingKeys: String, CodingKey { case id, kind, tab, title, isHidden }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        kind = try values.decode(Kind.self, forKey: .kind)
        tab = try values.decode(String.self, forKey: .tab)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        isHidden = try values.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }
}

/// What the sidebar shows for a library, from the library and the person's layout: one list for each part of the
/// sidebar, in order, hidden places included so Customize Sidebar can offer them back.
@MainActor
struct SidebarPlan {
    /// The types the Types section lists, nested. The person orders the top rows; the rows under one keep the order
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
        views = layout.ordered(library.views, by: { SidebarPlace.view($0.id).key })
        types = layout.ordered(library.typeTree, by: { SidebarPlace.type($0.id).key })
        tabs = layout.allTabs
        let showsTypes = types.contains { !layout.isHidden(.type($0.id)) }
        groups = SidebarGroupPlan.plans(in: library, layout: layout, views: views, showsTypes: showsTypes)
    }

    /// The sections of a tab that are shown, in order. A person's own or built-in section with nothing in it stays
    /// out unless `customizing`, which keeps every one so something can be put in it.
    func groups(in tab: String, customizing: Bool) -> [SidebarGroupPlan] {
        groups.filter { layout.tabID(of: $0.group) == tab && !layout.hides($0.group) && (customizing || !$0.isEmpty) }
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
        case select(PlaceView)
    }

    /// What the system's outline does with an arrow key, for the selected type row, or nil where it does nothing.
    /// Left folds a row that is open, and otherwise selects the row's parent. Right opens a row that is folded, and
    /// otherwise selects the first row under it that opens a list. A group has no list to select, so a parent that
    /// is one is passed over for the nearest above it that has.
    func outcome(of arrow: Arrow, selected: PlaceView?) -> ArrowOutcome? {
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
    func selectionAfterFolding(_ id: String, selected: PlaceView?) -> PlaceView? {
        let path = path(to: selected)
        guard let index = path.firstIndex(where: { $0.id == id }), index < path.count - 1 else { return nil }
        return path[...index].last(where: \.opens).flatMap(Self.item)
    }

    private static func item(_ node: TypeNode) -> PlaceView? {
        node.type.map { .type($0) }
    }

    /// The shown rows from the top of the tree down to the one `selected` names, or none where it names no shown row.
    private func path(to selected: PlaceView?) -> [TypeNode] {
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

    /// The Types section shows this many types, with their kinds, until its "N More" row.
    static let shownTypeCount = 5

    /// The first `limit` types of `rows`, each with the kind rows folded open under it, and how many types follow.
    /// With `showsAll` every row stays. A type's kinds are never cut off from it, and do not count. The type `open`
    /// is, or is under, stays too, after the others, so the open place always has its row.
    static func limited(
        _ rows: [TypeRow], showsAll: Bool, limit: Int = shownTypeCount, open: TypeID? = nil
    ) -> (rows: [TypeRow], more: Int) {
        let topLevel = rows.filter { $0.depth == 0 }.count
        guard topLevel > limit else { return (rows, 0) }
        guard !showsAll else { return (rows, topLevel - limit) }
        var seen = 0
        let kept = Array(rows.prefix { row in
            if row.depth == 0 { seen += 1 }
            return seen <= limit
        })
        guard let open, let index = rows.firstIndex(where: { $0.node.type == open }), index >= kept.count,
              let start = rows[...index].lastIndex(where: { $0.depth == 0 }) else { return (kept, topLevel - limit) }
        let end = rows[(start + 1)...].firstIndex { $0.depth == 0 } ?? rows.endIndex
        return (kept + rows[start..<end], topLevel - limit - 1)
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
/// library's sidebar starts from the default, and changes are saved as before. A change to one library's layout writes
/// only its entry: every other entry is written back in the bytes it was stored in.
@Observable @MainActor
final class SidebarLayouts {
    static let defaultsKey = "sidebarLayouts"
    /// Each entry is stored data that could not be read, in the order it was found.
    static let setAsideKey = "sidebarLayoutsSetAside"

    @ObservationIgnored private let defaults: UserDefaults
    private var layouts: [String: SidebarLayout]
    /// Each library's entry as stored, in order: its key and its value, as JSON text.
    @ObservationIgnored private var entries: [StoredEntry] = []

    @ObservationIgnored private let reporting: Reporting

    private struct StoredEntry {
        let library: String
        let key: Data
        var value: Data
    }

    init(defaults: UserDefaults = .standard, reporting: Reporting = .shared) {
        self.defaults = defaults
        self.reporting = reporting
        layouts = [:]
        reload()
    }

    /// Reads the stored value again, as when another Mac's change has reached the defaults (`PreferencesSync`).
    func reload() {
        guard let saved = defaults.data(forKey: Self.defaultsKey) else {
            layouts = [:]
            entries = []
            return
        }
        var readable: [String: SidebarLayout] = [:]
        var kept: [StoredEntry] = []
        var unreadable: Data?
        if let all = Self.entries(of: saved) {
            var setAside: [StoredEntry] = []
            for entry in all {
                kept.removeAll { $0.library == entry.library }
                if let layout = try? JSONDecoder().decode(SidebarLayout.self, from: entry.value) {
                    readable[entry.library] = layout
                    kept.append(entry)
                } else {
                    readable[entry.library] = nil
                    setAside.append(entry)
                }
            }
            if !setAside.isEmpty { unreadable = Self.object(setAside) }
        } else {
            unreadable = saved
        }
        layouts = readable
        entries = kept
        guard let unreadable else { return }
        defaults.set((defaults.array(forKey: Self.setAsideKey) as? [Data] ?? []) + [unreadable], forKey: Self.setAsideKey)
        save()
        Telemetry.sidebarLayoutsUnreadable(reporting: reporting)
    }

    /// The entries of a stored JSON object, each as the text it was stored in, or nil where the data is no object.
    private static func entries(of data: Data) -> [StoredEntry]? {
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { return nil }
        let bytes = [UInt8](data)
        var index = 0
        func skipSpace() { while index < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[index]) { index += 1 } }
        func skipString() {
            index += 1
            while index < bytes.count, bytes[index] != 0x22 { index += bytes[index] == 0x5C ? 2 : 1 }
            index += 1
        }
        /// Moves past one value, which the check above has found valid.
        func skipValue() {
            var depth = 0
            while index < bytes.count {
                switch bytes[index] {
                case 0x22:
                    skipString()
                    if depth == 0 { return }
                    continue
                case 0x7B, 0x5B: depth += 1
                case 0x7D, 0x5D:
                    if depth == 0 { return }
                    depth -= 1
                    if depth == 0 { index += 1; return }
                case 0x2C: if depth == 0 { return }
                case 0x20, 0x0A, 0x0D, 0x09: if depth == 0 { return }
                default: break
                }
                index += 1
            }
        }
        var found: [StoredEntry] = []
        skipSpace()
        index += 1
        while true {
            skipSpace()
            guard index < bytes.count, bytes[index] == 0x22 else { break }
            let keyStart = index
            skipString()
            let key = Data(bytes[keyStart..<index])
            skipSpace()
            index += 1
            skipSpace()
            let valueStart = index
            skipValue()
            let value = Data(bytes[valueStart..<index])
            guard let library = try? JSONDecoder().decode(String.self, from: key) else { return nil }
            found.append(StoredEntry(library: library, key: key, value: value))
            skipSpace()
            guard index < bytes.count, bytes[index] == 0x2C else { break }
            index += 1
        }
        return found
    }

    private static func object(_ entries: [StoredEntry]) -> Data {
        var data = Data("{".utf8)
        for (position, entry) in entries.enumerated() {
            if position > 0 { data.append(contentsOf: Array(",".utf8)) }
            data.append(entry.key)
            data.append(contentsOf: Array(":".utf8))
            data.append(entry.value)
        }
        data.append(contentsOf: Array("}".utf8))
        return data
    }

    func layout(for library: String) -> SidebarLayout { layouts[library] ?? SidebarLayout() }

    func update(_ library: String, _ change: (inout SidebarLayout) -> Void) {
        var layout = layout(for: library)
        change(&layout)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard layout != self.layout(for: library), let value = try? encoder.encode(layout),
              let key = try? JSONEncoder().encode(library) else { return }
        layouts[library] = layout
        if let index = entries.firstIndex(where: { $0.library == library }) {
            entries[index].value = value
        } else {
            entries.append(StoredEntry(library: library, key: key, value: value))
        }
        save()
    }

    private func save() {
        defaults.set(Self.object(entries), forKey: Self.defaultsKey)
    }
}
