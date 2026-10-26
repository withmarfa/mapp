import Foundation
import Observation

/// A place the sidebar can show, named by a key that stays the same across launches, so what the person chose to hide
/// or move is found again.
nonisolated enum SidebarPlace: Hashable, Sendable {
    case inbox, recents, all, favorites, sources
    /// The index of items other items are filed under.
    case collections
    /// The section that holds the library's types.
    case types
    /// The section that lists the views saved on the server; hiding it hides every view.
    case views
    case files
    /// A type's row, or a group of types by its stem (`TypeNode.id`).
    case type(String)
    /// One saved view's row, by its item ID.
    case view(ItemID)

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
        case .files: "files"
        case .type(let id): "type:" + id
        case .view(let id): "view:" + id.rawValue
        }
    }
}

/// What one library's person chose for the sidebar: the places hidden, the sections collapsed, and the order of the rest. A place the layout
/// does not mention, such as a type the catalogue has just gained, is shown, after the ones that have a position.
nonisolated struct SidebarLayout: Codable, Equatable, Sendable {
    private(set) var hidden: Set<String> = []
    /// The keys of the places the person has placed, in order. Places of different groups share the list, because a
    /// group only ever reads the keys of its own.
    private(set) var order: [String] = []

    /// The keys of the sections the person has collapsed, which the sidebar shows with only their headers.
    private(set) var collapsed: Set<String> = []

    init() {}

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hidden = try values.decodeIfPresent(Set<String>.self, forKey: .hidden) ?? []
        order = try values.decodeIfPresent([String].self, forKey: .order) ?? []
        collapsed = try values.decodeIfPresent(Set<String>.self, forKey: .collapsed) ?? []
    }

    func isHidden(_ place: SidebarPlace) -> Bool { hidden.contains(place.key) }

    func isCollapsed(_ section: SidebarPlace) -> Bool { collapsed.contains(section.key) }

    mutating func setCollapsed(_ section: SidebarPlace, _ isCollapsed: Bool) {
        if isCollapsed { collapsed.insert(section.key) } else { collapsed.remove(section.key) }
    }

    mutating func setHidden(_ place: SidebarPlace, _ isHidden: Bool) {
        if isHidden { hidden.insert(place.key) } else { hidden.remove(place.key) }
    }

    /// Whether any type's row is hidden, at any level.
    var hidesTypes: Bool { hidden.contains { $0.hasPrefix(Self.typePrefix) } }

    /// Shows every type again, leaving the other places as they were.
    mutating func showAllTypes() {
        hidden = hidden.filter { !$0.hasPrefix(Self.typePrefix) }
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

    private static let typePrefix = SidebarPlace.type("").key

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
    /// The places above the first heading: Inbox, Recents and Favorites.
    let top: [SidebarPlace]
    /// The Browse section: every item, the sources they came from, and the collections they are filed under. Files
    /// are included in Items.
    let browse: [SidebarPlace]
    /// The Types section, where the library holds any types, then the Views section, where the server has saved any
    /// views the library can read.
    let library: [SidebarPlace]
    /// The types the Types section lists, nested. The person orders the top rows; the rows under one keep the order
    /// of their items.
    let types: [TypeNode]
    /// The saved views, in the person's order, hidden ones included. Views the person never placed follow by title.
    let views: [LibraryView]
    let layout: SidebarLayout

    init(_ library: any ItemLibrary, layout: SidebarLayout) {
        self.layout = layout
        top = layout.ordered([.inbox, .recents, .favorites])
        browse = layout.ordered([.all, .sources, .collections])
        views = layout.ordered(library.views, by: { SidebarPlace.view($0.id).key })
        types = layout.ordered(library.typeTree, by: { SidebarPlace.type($0.id).key })
        self.library = (types.isEmpty ? [] : [.types]) + (library.views.isEmpty ? [] : [.views])
    }

    func isShown(_ place: SidebarPlace) -> Bool { !layout.isHidden(place) }

    var shownTop: [SidebarPlace] { top.filter(isShown) }
    var shownBrowse: [SidebarPlace] { browse.filter(isShown) }
    /// The Views section is absent once every view in it is hidden, as it is when there are none.
    var shownLibrary: [SidebarPlace] { library.filter { isShown($0) && ($0 != .views || !shownViews.isEmpty) } }
    var shownViews: [LibraryView] { views.filter { isShown(.view($0.id)) } }

    /// The type rows not hidden, at every level; hiding a row hides what is under it.
    var shownTypes: [TypeNode] { Self.shown(types, by: self) }

    private static func shown(_ nodes: [TypeNode], by plan: SidebarPlan) -> [TypeNode] {
        nodes.filter { plan.isShown(.type($0.id)) }.map { node in
            TypeNode(id: node.id, type: node.type, label: node.label, symbol: node.symbol, count: node.count, total: node.total,
                     children: shown(node.children, by: plan))
        }
    }
}

/// The layouts a person has made, one for each library, kept in the defaults. A library is named by its server's
/// address, so each keeps its own.
@Observable @MainActor
final class SidebarLayouts {
    private static let defaultsKey = "sidebarLayouts"

    @ObservationIgnored private let defaults: UserDefaults
    private var layouts: [String: SidebarLayout]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        layouts = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([String: SidebarLayout].self, from: $0) } ?? [:]
    }

    func layout(for library: String) -> SidebarLayout { layouts[library] ?? SidebarLayout() }

    func update(_ library: String, _ change: (inout SidebarLayout) -> Void) {
        var layout = layout(for: library)
        change(&layout)
        guard layout != self.layout(for: library) else { return }
        layouts[library] = layout
        defaults.set(try? JSONEncoder().encode(layouts), forKey: Self.defaultsKey)
    }
}
