import SwiftUI

/// The sidebar's rows as the title's menu offers them with the sidebar closed: Search and New, then the Library and the
/// Feed, Pinned, and Types. It reads them through `GoMenu`, which is the one place that knows what the sidebar draws,
/// so the sidebar's own model changes `GoMenu` and nothing here.
@MainActor
struct PlacesMenu {
    struct Row: Identifiable {
        let entry: GoMenu.Entry
        let count: Int?
        var id: String { entry.id }
    }

    /// The Library and the Feed.
    let places: [Row]
    /// What the sidebar pins: views, collections and items.
    let pinned: [Row]
    /// The sidebar's types, then every other type.
    let types: [Row]
    let moreTypes: [Row]
    let menu: GoMenu

    static func make(library: any ItemLibrary, layout: SidebarLayout) -> PlacesMenu {
        let menu = GoMenu(library: library, layout: layout)
        func rows(_ entries: [GoMenu.Entry]) -> [Row] {
            entries.map { entry in
                // The Feed's row has no count, as the sidebar's has none.
                let counts = entry.item.place == .feed ? nil : library.count(in: entry.item, favoritesScope: .library)
                return Row(entry: entry, count: counts)
            }
        }
        let places = menu.places.filter { $0.item == .library || $0.item == .feed }
        return PlacesMenu(places: rows(places), pinned: rows(menu.views), types: rows(menu.types), moreTypes: rows(menu.moreTypes), menu: menu)
    }
}

/// The menu's rows. Choosing one shows its place, as a row of the sidebar does.
struct PlacesMenuView: View {
    @CurrentLibrary private var library
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    let menu: PlacesMenu
    let browser: Browser
    let order: ItemOrder

    var body: some View {
        Button("Search", systemImage: "magnifyingglass") { browser.palette = .search }
        Button("New", systemImage: "square.and.pencil") { browser.openQuickAdd(remembered: lastType, in: library) }
        Divider()
        rows(menu.places)
        if !menu.pinned.isEmpty {
            Divider()
            Section("Pinned") { rows(menu.pinned) }
        }
        Divider()
        Section("Types") {
            rows(menu.types)
            if !menu.moreTypes.isEmpty {
                Menu("\(menu.moreTypes.count) More") { rows(menu.moreTypes) }
            }
        }
    }

    private func rows(_ rows: [PlacesMenu.Row]) -> some View {
        ForEach(rows) { row in
            Toggle(isOn: Binding { row.entry.item.isSame(browser.shown) } set: { _ in
                browser.show(menu.menu.destination(of: row.entry, in: library), in: library, order: order)
            }) {
                label(row)
            }
        }
    }

    @ViewBuilder private func label(_ row: PlacesMenu.Row) -> some View {
        let title = row.count.map { "\(row.entry.title)  \($0.formatted())" } ?? row.entry.title
        switch row.entry.icon {
        case .symbol(let name): Label(title, systemImage: name)
        case .type(let icon): Label(title, typeIcon: icon)
        }
    }
}
