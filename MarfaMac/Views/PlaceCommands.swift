import SwiftUI

/// The Go menu: the places, the saved views and the types the sidebar lists (`GoMenu`), so a window with the sidebar
/// hidden reaches them too, and every other type, hidden ones included, under All Types. New and Search are File and Edit menu commands
/// already. The menu has no keys.
struct PlaceCommands: Commands {
    /// Nil while no library is open: before a server is set, or while a server's copy opens.
    let library: (any ItemLibrary)?
    let libraries: Libraries
    @FocusedValue(\.browser) private var browser
    @StoredOrder private var order

    var body: some Commands {
        CommandMenu("Go") {
            if let library {
                let menu = GoMenu(library: library, layout: libraries.sidebarLayout)
                group(menu.places.filter { !SidebarPlace.builtInViews.contains($0.place) }, menu: menu, in: library)
                Divider()
                group(menu.places.filter { SidebarPlace.builtInViews.contains($0.place) }, menu: menu, in: library)
                Section("Views") {
                    group(menu.views, menu: menu, in: library)
                }
                Section("Types") {
                    group(menu.types, menu: menu, in: library)
                    if !menu.moreTypes.isEmpty {
                        Menu("All Types") { group(menu.moreTypes, menu: menu, in: library) }
                    }
                }
            }
        }
    }

    private func group(_ entries: [GoMenu.Entry], menu: GoMenu, in library: any ItemLibrary) -> some View {
        ForEach(entries) { entry in
            // A toggle, for the check mark the menu puts beside the place the window shows.
            Toggle(isOn: Binding { browser?.shown == entry.item } set: { _ in go(entry, menu: menu, in: library) }) {
                label(entry)
            }
            .disabled(browser == nil || !library.isLoaded)
        }
    }

    @ViewBuilder private func label(_ entry: GoMenu.Entry) -> some View {
        switch entry.icon {
        case .symbol(let name): Label(entry.title, systemImage: name)
        case .type(let icon): Label(entry.title, typeIcon: icon)
        }
    }

    private func go(_ entry: GoMenu.Entry, menu: GoMenu, in library: any ItemLibrary) {
        browser?.show(menu.destination(of: entry, in: library), in: library, order: order)
    }
}
