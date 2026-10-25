import SwiftUI

/// View choices remain in the menu when no document window is in front.
struct ItemViewOptions: View {
    /// Nil while no window is in front, which leaves the choices in the menu, dimmed.
    let browser: Browser?
    /// The layouts the window's place can show; all of them while no window is in front.
    var modes = ItemViewMode.allCases

    var body: some View {
        Group {
            choice("as List", systemImage: ItemViewMode.list.symbol, .list, key: "1")
            choice("as Gallery", systemImage: ItemViewMode.gallery.symbol, .gallery, key: "2")
            choice("as Table", systemImage: ItemViewMode.table.symbol, .table, key: "3")
            choice("as Board", systemImage: ItemViewMode.board.symbol, .board, key: "4")
            choice("as Agenda", systemImage: ItemViewMode.agenda.symbol, .agenda, key: "5")
        }
        .disabled(browser == nil)
    }

    private func identifier(_ mode: ItemViewMode) -> String {
        switch mode {
        case .list: "ViewAsList"
        case .gallery: "ViewAsGallery"
        case .table: "ViewAsTable"
        case .board: "ViewAsBoard"
        case .agenda: "ViewAsAgenda"
        }
    }

    @ViewBuilder
    private func choice(_ title: LocalizedStringKey, systemImage: String, _ mode: ItemViewMode, key: KeyEquivalent) -> some View {
        if modes.contains(mode) {
            Toggle(title, systemImage: systemImage, isOn: Binding { browser?.viewMode == mode } set: { _ in browser?.viewMode = mode })
                .keyboardShortcut(key)
                .accessibilityIdentifier(identifier(mode))
        }
    }
}

/// One pop-up button stays at the window's trailing side whichever view is shown.
struct ViewModeMenu: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser

    var body: some View {
        let modes = browser.availableViewModes(in: library)
        Picker("View As", selection: $browser.viewMode) {
            if modes.contains(.list) { Text("as List").tag(ItemViewMode.list) }
            if modes.contains(.gallery) { Text("as Gallery").tag(ItemViewMode.gallery) }
            if modes.contains(.table) { Text("as Table").tag(ItemViewMode.table) }
            if modes.contains(.board) { Text("as Board").tag(ItemViewMode.board) }
            if modes.contains(.agenda) { Text("as Agenda").tag(ItemViewMode.agenda) }
        } currentValueLabel: {
            Image(systemName: browser.viewMode.symbol)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        // The menu's text choices otherwise set the width of the icon-only control.
        .frame(width: 48)
        .help("View As")
        .accessibilityLabel("View As")
        .accessibilityIdentifier("ViewModeMenu")
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
