import SwiftUI

/// List, Gallery or Table, each with its shortcut: under a View As header in the list's View Options menu, or as
/// View as List, Gallery and Table in the View menu, which keeps them whatever the window in front is.
struct ItemViewOptions: View {
    enum Style { case sections, menuBar }

    /// Nil while no window is in front, which leaves the choices in the menu, dimmed.
    let browser: Browser?
    var style = Style.sections

    var body: some View {
        Group {
            switch style {
            case .sections:
                Section("View As") {
                    choice("List", systemImage: "list.bullet", .list, key: "1")
                    choice("Gallery", systemImage: "square.grid.2x2", .gallery, key: "2")
                    choice("Table", systemImage: "tablecells", .table, key: "3")
                }
            case .menuBar:
                choice("View as List", systemImage: "list.bullet", .list, key: "1")
                choice("View as Gallery", systemImage: "square.grid.2x2", .gallery, key: "2")
                choice("View as Table", systemImage: "tablecells", .table, key: "3")
            }
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

/// How the list looks: its view, its order and its grouping, in one menu on the list's toolbar.
struct ViewOptionsMenu: View {
    @Bindable var browser: Browser

    var body: some View {
        Menu("View Options", systemImage: "line.3.horizontal.decrease") {
            ItemViewOptions(browser: browser)
            // The table sorts and groups from its own bar and headers.
            if browser.viewMode != .table {
                Divider()
                OrderOptions(style: .sections)
            }
        }
        .menuIndicator(.hidden)
        .help("View Options")
        .accessibilityIdentifier("ViewOptionsToolbar")
    }
}
