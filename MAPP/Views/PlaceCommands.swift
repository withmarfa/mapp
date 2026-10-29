import SwiftUI

/// The Go menu: each place the sidebar opens from its top block and its Views block, so a window with the sidebar
/// hidden reaches them too. New and Search are File and Edit menu commands already.
struct PlaceCommands: Commands {
    /// Nil while no library is open: before a server is set, or while a server's copy opens.
    let library: (any ItemLibrary)?
    @FocusedValue(\.browser) private var browser
    @StoredOrder private var order

    var body: some Commands {
        CommandMenu("Go") {
            if let library {
                group(SidebarPlace.destinations, in: library)
                Divider()
                group(SidebarPlace.builtInViews, in: library)
            }
        }
    }

    private func group(_ places: [SidebarPlace], in library: any ItemLibrary) -> some View {
        ForEach(places, id: \.key) { place in
            if let item = place.item, let symbol = place.symbol {
                Button(library.name(of: item), systemImage: symbol) {
                    browser?.choose(item, in: library, order: order)
                }
                .disabled(browser == nil || !library.isLoaded)
            }
        }
    }
}
