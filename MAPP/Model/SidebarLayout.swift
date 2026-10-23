import Foundation
import Observation

/// A place the sidebar can show, named by a key that stays the same across launches, so what the person chose to hide
/// or move is found again.
nonisolated enum SidebarPlace: Hashable, Sendable {
    case inbox, all, favorites, projects
    /// The section that holds a Marfa library's types.
    case types
    /// The section that holds a notes folder's folders.
    case folders
    case files
    case type(TypeID)

    var key: String {
        switch self {
        case .inbox: "inbox"
        case .all: "all"
        case .favorites: "favorites"
        case .projects: "projects"
        case .types: "types"
        case .folders: "folders"
        case .files: "files"
        case .type(let id): "type:" + id.rawValue
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
        var list = ordered(places, by: key)
        let moved = source.sorted().map { list[$0] }
        let target = destination - source.filter { $0 < destination }.count
        for index in source.sorted().reversed() { list.remove(at: index) }
        list.insert(contentsOf: moved, at: min(target, list.count))
        let keys = list.map(key)
        order = order.filter { !keys.contains($0) } + keys
    }
}

/// What the sidebar shows for a library, from the library and the person's layout: one list for each part of the
/// sidebar, in order, hidden places included so Settings can offer them back.
@MainActor
struct SidebarPlan {
    /// Above Favorites: Inbox and All Items.
    let top: [SidebarPlace]
    /// What follows Favorites: the Projects section, then the Types or Folders section.
    let library: [SidebarPlace]
    /// The types the Types section lists, which only a library without folders has.
    let types: [ItemTypeCount]
    let layout: SidebarLayout

    init(_ library: any ItemLibrary, layout: SidebarLayout) {
        self.layout = layout
        top = layout.ordered([.inbox, .all])
        var rows: [SidebarPlace] = []
        if library.hasProjectType { rows.append(.projects) }
        if library.capabilities.contains(.folders) {
            rows.append(.folders)
            if library.count(in: .files) > 0 { rows.append(.files) }
            types = []
        } else {
            // Projects have their own section; `itemTypeCounts` leaves out the project type and the file types.
            types = layout.ordered(library.itemTypeCounts, by: { SidebarPlace.type($0.id).key })
            if !types.isEmpty { rows.append(.types) }
        }
        self.library = layout.ordered(rows)
    }

    func isShown(_ place: SidebarPlace) -> Bool { !layout.isHidden(place) }

    var shownTop: [SidebarPlace] { top.filter(isShown) }
    var shownLibrary: [SidebarPlace] { library.filter(isShown) }
    var shownTypes: [ItemTypeCount] { types.filter { isShown(.type($0.id)) } }
}

/// The layouts a person has made, one for each library, kept in the defaults. A library is named by its server's
/// address or its notes folder's path, so each keeps its own.
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
