import SwiftUI

/// List, Gallery or Table, each with its shortcut, as View as List, Gallery and Table in the View menu, which keeps
/// them whatever the window in front is.
struct ItemViewOptions: View {
    /// Nil while no window is in front, which leaves the choices in the menu, dimmed.
    let browser: Browser?

    var body: some View {
        Group {
            choice("View as List", systemImage: "list.bullet", .list, key: "1")
            choice("View as Gallery", systemImage: "square.grid.2x2", .gallery, key: "2")
            choice("View as Table", systemImage: "tablecells", .table, key: "3")
        }
        .disabled(browser == nil)
    }

    private func identifier(_ mode: ItemViewMode) -> String {
        switch mode {
        case .list: "ViewAsList"
        case .gallery: "ViewAsGallery"
        case .table: "ViewAsTable"
        }
    }

    private func choice(_ title: LocalizedStringKey, systemImage: String, _ mode: ItemViewMode, key: KeyEquivalent) -> some View {
        Toggle(title, systemImage: systemImage, isOn: Binding { browser?.viewMode == mode } set: { _ in browser?.viewMode = mode })
            .keyboardShortcut(key)
            .accessibilityIdentifier(identifier(mode))
    }
}

/// List, Gallery or Table, as a control of its own at the start of the items' toolbar.
struct ViewModePicker: View {
    @Bindable var browser: Browser

    var body: some View {
        Picker("View As", selection: $browser.viewMode) {
            Label("List", systemImage: "list.bullet").tag(ItemViewMode.list)
            Label("Gallery", systemImage: "square.grid.2x2").tag(ItemViewMode.gallery)
            Label("Table", systemImage: "tablecells").tag(ItemViewMode.table)
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .help("View As")
        .accessibilityIdentifier("ViewModePicker")
    }
}

/// How the list and the gallery are ordered and grouped, in one menu on their toolbar. The table has its own
/// (`ItemTableControls`), which adds its columns.
struct ViewOptionsMenu: View {
    var body: some View {
        Menu("View Options", systemImage: "slider.horizontal.3") {
            OrderOptions(style: .sections)
        }
        .menuIndicator(.hidden)
        .help("View Options")
        .accessibilityIdentifier("ViewOptionsToolbar")
    }
}
