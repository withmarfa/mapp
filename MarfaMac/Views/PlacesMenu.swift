import SwiftUI

/// The sidebar's rows as the title's menu offers them with the sidebar closed: Search and New, then the Library and the
/// Feed, Pinned, and Types. The places and types come from `GoMenu` and Pinned from the sidebar's own plan, so the menu
/// lists what the sidebar draws.
@MainActor
struct PlacesMenu {
    struct Row: Identifiable {
        let entry: GoMenu.Entry
        let count: Int?
        var id: String { entry.id }
    }

    /// The Library and the Feed.
    let places: [Row]
    /// What the sidebar pins: views, collections, sources and items, in the person's order.
    let pinned: [SidebarPlaceRowData]
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
        let places = (menu.places + menu.builtInViews).filter { $0.item == .library || $0.item == .feed }
        let plan = SidebarPlan(library, layout: layout)
        let pinned = plan.groups.filter { $0.group.kind == .pinned && !layout.hides($0.group) }.flatMap(\.shown)
            .compactMap { SidebarContent.row($0, in: library, creatable: []) }
        return PlacesMenu(places: rows(places), pinned: pinned, types: rows(menu.types), moreTypes: rows(menu.moreTypes), menu: menu)
    }
}

/// The menu's rows. Choosing one shows its place, as a row of the sidebar does.
struct PlacesMenuView: View {
    @CurrentLibrary private var library
    @Environment(ShortcutBindings.self) private var shortcuts: ShortcutBindings?
    let menu: PlacesMenu
    let browser: Browser
    let order: ItemOrder

    var body: some View {
        // The keys are drawn beside the commands the menu bar binds them to; a menu's own items bind none.
        Group {
            // As the sidebar's Search row does.
            Button("Search", systemImage: "magnifyingglass") { browser.palette = .commands }
                .shortcut(.commandPalette, shortcuts)
            Button("New", systemImage: "square.and.pencil") { browser.openNewItem(in: library) }
                .shortcut(.newItem, shortcuts)
            Divider()
            places
        }
        // On macOS a menu item draws its symbol only when the menu asks for it.
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder private var places: some View {
        rows(menu.places)
        if !menu.pinned.isEmpty {
            Divider()
            Section("Pinned") { ForEach(menu.pinned, id: \.place) { pinned($0) } }
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
                label(row.entry.title, row.entry.icon)
            }
            // The count at the row's end, as the sidebar draws it; none hides it.
            .badge(row.count ?? 0)
        }
    }

    /// A pinned place shows as a row of the sidebar does; a pinned item opens the item.
    @ViewBuilder private func pinned(_ row: SidebarPlaceRowData) -> some View {
        if let opens = row.opens {
            Toggle(isOn: Binding { opens.isSame(browser.shown) } set: { _ in
                browser.show(opens, in: library, order: order)
            }) {
                label(row.title, row.menuIcon)
            }
        } else if case .item(let id) = row.place {
            Button {
                if let item = library.item(id) { browser.open(itemLink: item, in: library, order: order) }
            } label: {
                label(row.title, row.menuIcon)
            }
        }
    }

    @ViewBuilder private func label(_ title: String, _ icon: RowIcon) -> some View {
        switch icon {
        case .symbol(let name): Label(title, systemImage: name)
        case .type(let icon): Label(title, typeIcon: icon)
        }
    }
}
