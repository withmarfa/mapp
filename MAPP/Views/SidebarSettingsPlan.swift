import Foundation

/// What Settings > Sidebar draws, worked out once from the library and the person's layout (`SidebarPlan`, the plan the
/// sidebar reads too): the tabs, each tab's sections with what they hold and which are shown, and the views with their
/// colors. It decides what the page says and draws nothing. A section hidden from the sidebar stays in its tab, switched
/// off, so it can come back; a view the library no longer has, or has not synced yet, has no row.
struct SidebarSettingsPlan: Equatable {
    struct Tab: Identifiable, Equatable {
        let tab: SidebarTab
        let sections: [Section]

        var id: String { tab.id }
    }

    struct Section: Identifiable, Equatable {
        let id: String
        let kind: SidebarGroup.Kind
        let title: String
        let symbol: String
        /// What the section holds, on one line.
        let detail: String
        let isShown: Bool
        /// What its Show list offers, shown or not; empty for a section with nothing to choose.
        let choices: [SidebarShowChoice]

        /// How many of the section's rows are shown. The saved views as a whole are a choice, but not a row.
        var shownCount: Int { choices.filter { $0.place != .views && $0.isShown }.count }
        /// Whether the section can be hidden and shown again. A section of the person's own is removed instead.
        var canHide: Bool { kind != .custom }
        var canRename: Bool { kind != .shortcuts }
    }

    struct ViewRow: Identifiable, Equatable {
        let place: SidebarPlace
        let title: String
        let symbol: String
        let tone: TypeTone
        let isShown: Bool
        /// False while the saved views as a whole are hidden: the switch then has nothing to show.
        let isEnabled: Bool
        /// Where it sits in the list of views, for Move Up and Move Down.
        let position: Int
        let count: Int

        var id: String { place.key }
    }

    let tabs: [Tab]
    /// Inbox, Recents, Favorites and the saved views, in the sidebar's order.
    let views: [ViewRow]
    /// Whether the library has types, which the Types section lists.
    let hasTypes: Bool
    /// The collections and sources with no row yet, which a new section can hold.
    let unplacedCollections: [SidebarPick]
    let unplacedSources: [SidebarPick]

    init(_ library: any ItemLibrary, layout: SidebarLayout) {
        let plan = SidebarPlan(library, layout: layout)
        let creatable = Set(QuickAdd.types(in: library).map(\.id.rawValue))

        func section(_ group: SidebarGroupPlan) -> Section {
            let kind = group.group.kind
            let choices = SidebarContent.showChoices(of: group, in: library, plan: plan)
            let rows = choices.filter { $0.place != .views }
            let detail: String = switch kind {
            case .shortcuts:
                group.group.shortcuts.compactMap { SidebarContent.shortcutRow($0, in: library, creatable: creatable)?.title }
                    .joined(separator: ", ")
            case .library, .custom:
                rows.filter(\.isShown).map(\.title).joined(separator: ", ")
            case .views: String(localized: "\(rows.count) views")
            case .types: String(localized: "\(rows.count) types")
            }
            return Section(
                id: group.id, kind: kind, title: group.group.name, symbol: Self.symbol(of: kind),
                detail: detail.isEmpty ? String(localized: "Empty") : detail, isShown: !group.group.isHidden, choices: choices)
        }
        tabs = plan.tabs.map { tab in
            Tab(tab: tab, sections: plan.groups.filter { layout.tabID(of: $0.group) == tab.id }.map(section))
        }

        var seen = Set<String>()
        var places: [SidebarPlace] = []
        for place in plan.groups.flatMap(\.members) where place.defaultTone != nil && seen.insert(place.key).inserted {
            places.append(place)
        }
        // With the saved views hidden as a whole no section holds them, yet Settings offers them back.
        for view in plan.views where seen.insert(SidebarPlace.view(view.id).key).inserted {
            places.append(.view(view.id))
        }
        let savedViewsHidden = layout.isHidden(.views)
        let rows = places.compactMap { place -> (SidebarPlace, SidebarItem, String)? in
            guard let item = place.item, let symbol = place.symbol else { return nil }
            return (place, item, symbol)
        }
        views = rows.enumerated().map { position, row in
            let isSaved = if case .view = row.0 { true } else { false }
            return ViewRow(
                place: row.0, title: library.name(of: row.1), symbol: row.2, tone: layout.color(of: row.0),
                isShown: !layout.isHidden(row.0), isEnabled: !(isSaved && savedViewsHidden), position: position, count: rows.count)
        }
        hasTypes = !plan.types.isEmpty
        let choices = SidebarContent.choices(in: library, plan: plan, layout: layout)
        unplacedCollections = choices.unplacedCollections
        unplacedSources = choices.unplacedSources
    }

    private static func symbol(of kind: SidebarGroup.Kind) -> String {
        switch kind {
        case .shortcuts: "square.and.pencil"
        case .library: "books.vertical"
        case .views: "tray.2"
        case .types: SidebarPlace.types.symbol ?? "rectangle.3.group"
        case .custom: "list.bullet"
        }
    }
}
