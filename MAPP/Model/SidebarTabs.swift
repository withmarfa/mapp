import Foundation

/// A tab of the sidebar: a name and a symbol. With one tab the sidebar shows no tab bar.
nonisolated struct SidebarTab: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var symbol: String

    static let homeID = "home"
    /// The tab every sidebar starts with, and where a section goes when its own tab is removed.
    static var home: SidebarTab { SidebarTab(id: homeID, name: String(localized: "Home"), symbol: "house") }
    /// The symbol a tab the person adds starts with.
    static let addedSymbol = "rectangle.stack"
}

/// A shortcut: a row of the sidebar that does something or goes somewhere, instead of being a place.
nonisolated enum SidebarShortcut: Hashable, Sendable {
    /// Opens New Item, in the kind used last.
    case new
    case search
    case settings
    /// Opens New Item in the type with this identifier.
    case create(String)
    /// Opens the place with this key (`SidebarPlace.key`): a view, a type or a collection.
    case go(String)

    /// What a new library's first shortcuts are: none makes an item of a type the person made.
    static let defaults: [SidebarShortcut] = [.new, .search]

    var key: String {
        switch self {
        case .new: "new"
        case .search: "search"
        case .settings: "settings"
        case .create(let type): "create:" + type
        case .go(let place): "go:" + place
        }
    }

    init?(key: String) {
        switch key {
        case "new": self = .new
        case "search": self = .search
        case "settings": self = .settings
        default:
            if key.hasPrefix("create:"), key.count > 7 { self = .create(String(key.dropFirst(7))) }
            else if key.hasPrefix("go:"), key.count > 3 { self = .go(String(key.dropFirst(3))) }
            else { return nil }
        }
    }
}

extension SidebarShortcut: Codable {
    init(from decoder: any Decoder) throws {
        let key = try decoder.singleValueContainer().decode(String.self)
        guard let shortcut = SidebarShortcut(key: key) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown shortcut \(key)"))
        }
        self = shortcut
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
}

/// A section of a tab: a heading over rows. Library, Views and Types are the sections every sidebar starts with,
/// Shortcuts is the block of rows that act, and a person's own sections (`custom`) hold views, collections and
/// sources. A section is never lost: hiding a built-in one keeps it, so Add Section can bring it back.
nonisolated struct SidebarGroup: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case shortcuts, library, views, types, custom }

    var id: String
    var kind: Kind
    /// The name the person gave it; nil keeps the kind's own.
    var title: String?
    /// The identifier of the tab it sits in.
    var tab: String
    var isHidden = false
    /// What a shortcuts block holds, in order.
    var shortcuts: [SidebarShortcut] = []

    /// The sections of a sidebar nobody has arranged, in order: what it showed before tabs and sections existed.
    static func defaults(tab: String) -> [SidebarGroup] {
        [
            SidebarGroup(id: "shortcuts", kind: .shortcuts, tab: tab, shortcuts: SidebarShortcut.defaults),
            SidebarGroup(id: "library", kind: .library, tab: tab),
            SidebarGroup(id: "views", kind: .views, tab: tab),
            SidebarGroup(id: "types", kind: .types, tab: tab),
        ]
    }

    /// What the heading says when the person has not renamed the section. The shortcuts block has no heading.
    var name: String {
        if let title, !title.isEmpty { return title }
        return switch kind {
        case .shortcuts: String(localized: "Shortcuts")
        case .library: String(localized: "Library")
        case .views: String(localized: "Views")
        case .types: String(localized: "Types")
        case .custom: String(localized: "Section")
        }
    }

    /// Whether the person can hold views, collections and sources in it by hand. The types section lists types only.
    var holdsPlaces: Bool { kind != .types && kind != .shortcuts }
}

// MARK: Tabs and sections

nonisolated extension SidebarLayout {
    /// The tabs in order: the person's, or Home alone.
    var allTabs: [SidebarTab] {
        guard let tabs, !tabs.isEmpty else { return [.home] }
        return tabs
    }

    /// Every section in order, across the tabs, hidden ones included.
    var allGroups: [SidebarGroup] { groups ?? SidebarGroup.defaults(tab: allTabs[0].id) }

    /// The tab the person has open when they have chosen none, or the one they chose that no longer exists.
    func tab(_ id: String?) -> SidebarTab { allTabs.first { $0.id == id } ?? allTabs[0] }

    /// The tab a section sits in, where its own is gone: the first.
    func tabID(of group: SidebarGroup) -> String { tab(group.tab).id }

    /// The sections of a tab, in order, hidden ones included.
    func groups(in tab: String) -> [SidebarGroup] { allGroups.filter { tabID(of: $0) == tab } }

    private mutating func materialize() {
        tabs = allTabs
        groups = allGroups
    }

    /// Adds a tab, returning its identifier.
    @discardableResult
    mutating func addTab(named name: String, id: String = UUID().uuidString) -> String {
        materialize()
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        tabs?.append(SidebarTab(id: id, name: name.isEmpty ? String(localized: "Tab") : name, symbol: SidebarTab.addedSymbol))
        return id
    }

    mutating func renameTab(_ id: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = allTabs.firstIndex(where: { $0.id == id }) else { return }
        materialize()
        tabs?[index].name = name
    }

    /// Removes a tab. Its sections join the first tab after that tab's own, so none is lost. False where there is no
    /// such tab or it is the only one.
    @discardableResult
    mutating func removeTab(_ id: String) -> Bool {
        guard allTabs.count > 1, allTabs.contains(where: { $0.id == id }) else { return false }
        materialize()
        tabs?.removeAll { $0.id == id }
        guard let first = tabs?.first?.id, let all = groups else { return true }
        let moved = all.filter { $0.tab == id }.map { group -> SidebarGroup in
            var group = group
            group.tab = first
            return group
        }
        var rest = all.filter { $0.tab != id }
        let end = rest.lastIndex { tabID(of: $0) == first }.map { $0 + 1 } ?? rest.endIndex
        rest.insert(contentsOf: moved, at: end)
        groups = rest
        return true
    }

    /// Moves a section up (-1) or down (1) among the sections of its tab that are shown. Nothing happens at either end.
    mutating func moveGroup(_ id: String, by offset: Int) {
        guard let group = allGroups.first(where: { $0.id == id }) else { return }
        let tab = tabID(of: group)
        let slots = allGroups.indices.filter { tabID(of: allGroups[$0]) == tab && !allGroups[$0].isHidden }
        guard let position = slots.firstIndex(where: { allGroups[$0].id == id }), slots.indices.contains(position + offset) else { return }
        materialize()
        groups?.swapAt(slots[position], slots[position + offset])
    }

    /// Moves a section to where another section of its tab is, as a drag onto it does. Nothing happens for sections of
    /// two tabs or the same section.
    mutating func moveGroup(_ id: String, onto target: String) {
        let all = allGroups
        guard id != target, let moved = all.first(where: { $0.id == id }), let other = all.first(where: { $0.id == target }),
              tabID(of: moved) == tabID(of: other) else { return }
        let slots = all.indices.filter { tabID(of: all[$0]) == tabID(of: moved) }
        var inTab = slots.map { all[$0] }
        guard let from = inTab.firstIndex(where: { $0.id == id }), let to = inTab.firstIndex(where: { $0.id == target }) else { return }
        inTab.insert(inTab.remove(at: from), at: to)
        materialize()
        for (slot, group) in zip(slots, inTab) { groups?[slot] = group }
    }

    /// Moves a section to the end of another tab. Nothing happens for a tab that does not exist.
    mutating func moveGroup(_ id: String, toTab tab: String) {
        guard allTabs.contains(where: { $0.id == tab }), let group = allGroups.first(where: { $0.id == id }), tabID(of: group) != tab else { return }
        materialize()
        guard var moved = groups?.first(where: { $0.id == id }) else { return }
        moved.tab = tab
        groups?.removeAll { $0.id == id }
        groups?.append(moved)
    }

    /// Names a section; an empty name returns it to the kind's own.
    mutating func renameGroup(_ id: String, to name: String) {
        guard let index = allGroups.firstIndex(where: { $0.id == id }), allGroups[index].kind != .shortcuts else { return }
        materialize()
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        groups?[index].title = name.isEmpty ? nil : name
    }

    /// Hides a built-in section, which Add Section brings back, or takes a person's own away.
    mutating func hideGroup(_ id: String) {
        guard let index = allGroups.firstIndex(where: { $0.id == id }) else { return }
        materialize()
        if groups?[index].kind == .custom {
            groups?.remove(at: index)
        } else {
            groups?[index].isHidden = true
        }
    }

    /// Adds a section to the end of a tab. A built-in section the layout already holds is shown again, moved here;
    /// a person's own is made empty. Returns its identifier.
    @discardableResult
    mutating func addGroup(_ kind: SidebarGroup.Kind, toTab tab: String, id: String = UUID().uuidString) -> String {
        materialize()
        let tab = self.tab(tab).id
        let builtIn = kind != .custom && kind != .shortcuts
        var group = (builtIn ? groups?.first { $0.kind == kind } : nil)
            ?? SidebarGroup(id: builtIn ? kind.rawValue : id, kind: kind, tab: tab)
        groups?.removeAll { $0.id == group.id }
        group.tab = tab
        group.isHidden = false
        groups?.append(group)
        return group.id
    }

    // MARK: Shortcuts

    /// Adds a shortcut to the shortcuts block of a tab, which it makes first in the tab where there is none. A
    /// shortcut already there stays where it is.
    mutating func addShortcut(_ shortcut: SidebarShortcut, toTab tab: String) {
        materialize()
        let tab = self.tab(tab).id
        if let index = groups?.firstIndex(where: { $0.kind == .shortcuts && tabID(of: $0) == tab }) {
            guard groups?[index].shortcuts.contains(shortcut) == false else { return }
            groups?[index].shortcuts.append(shortcut)
        } else {
            let at = groups?.firstIndex { tabID(of: $0) == tab } ?? groups?.endIndex ?? 0
            groups?.insert(SidebarGroup(id: "shortcuts-" + UUID().uuidString, kind: .shortcuts, tab: tab, shortcuts: [shortcut]), at: at)
        }
    }

    mutating func removeShortcut(_ shortcut: SidebarShortcut, from group: String) {
        guard let index = allGroups.firstIndex(where: { $0.id == group }) else { return }
        materialize()
        groups?[index].shortcuts.removeAll { $0 == shortcut }
    }

    mutating func moveShortcuts(in group: String, fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let index = allGroups.firstIndex(where: { $0.id == group }) else { return }
        materialize()
        guard var list = groups?[index].shortcuts else { return }
        let moved = source.sorted().filter { list.indices.contains($0) }.map { list[$0] }
        let target = destination - source.filter { $0 < destination }.count
        for position in source.sorted().reversed() where list.indices.contains(position) { list.remove(at: position) }
        list.insert(contentsOf: moved, at: max(0, min(target, list.count)))
        groups?[index].shortcuts = list
    }

    // MARK: Places

    /// The section a place sits in: where the person put it, if that section is still there, otherwise its own. A
    /// collection or a source has no section of its own.
    func home(of place: SidebarPlace) -> String? {
        if let put = homes?[place.key], allGroups.contains(where: { $0.id == put && $0.holdsPlaces }) { return put }
        let kind: SidebarGroup.Kind
        switch place {
        case .all, .sources, .collections: kind = .library
        case .inbox, .recents, .favorites, .view: kind = .views
        default: return nil
        }
        return allGroups.first { $0.kind == kind }?.id
    }

    // MARK: View colors

    /// The color of a view's mark: the person's choice, or the view's own.
    func color(of place: SidebarPlace) -> TypeTone {
        colors?[place.key].flatMap(TypeTone.init(rawValue:)) ?? place.defaultTone ?? .gray
    }

    /// Keeps the color chosen for a view; nil returns it to the view's own.
    mutating func setColor(_ tone: TypeTone?, of place: SidebarPlace) {
        var all = colors ?? [:]
        all[place.key] = tone?.rawValue
        colors = all.isEmpty ? nil : all
    }
}
