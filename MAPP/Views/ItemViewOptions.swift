import SwiftUI

/// List or Gallery, as View As in the View menu and the list's View Options menu offer them, each with its shortcut.
struct ItemViewOptions: View {
    @Bindable var browser: Browser

    var body: some View {
        Section("View As") {
            choice("List", systemImage: "list.bullet", .list, key: "1")
            choice("Gallery", systemImage: "square.grid.2x2", .gallery, key: "2")
        }
        .disabled(browser.showsTypes)
    }

    private func choice(_ title: LocalizedStringKey, systemImage: String, _ mode: ItemViewMode, key: KeyEquivalent) -> some View {
        Toggle(title, systemImage: systemImage, isOn: Binding { browser.viewMode == mode } set: { _ in browser.viewMode = mode })
            .keyboardShortcut(key)
            .accessibilityIdentifier(mode == .list ? "ViewAsList" : "ViewAsGallery")
    }
}

/// How the list looks: its view, its order and its grouping, in one menu on the list's toolbar.
struct ViewOptionsMenu: View {
    @Bindable var browser: Browser

    var body: some View {
        Menu("View Options", systemImage: "line.3.horizontal.decrease") {
            ItemViewOptions(browser: browser)
            Divider()
            OrderOptions(style: .sections)
        }
        .menuIndicator(.hidden)
        .help("View Options")
        .accessibilityIdentifier("ViewOptionsToolbar")
    }
}
