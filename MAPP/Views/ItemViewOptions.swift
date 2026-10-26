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

/// The options of the view a window shows, in one menu at the same place on every view's toolbar: after Search
/// (and the table's Filter), before View As. The View menu holds the same options (`CurrentViewOptions`), since a
/// toolbar can be hidden or customized.
struct ViewOptionsMenu: View {
    let browser: Browser

    var body: some View {
        Menu("View Options", systemImage: "slider.horizontal.3") {
            CurrentViewOptions(browser: browser)
        }
        .menuIndicator(.hidden)
        .help("View Options")
        .accessibilityIdentifier("ViewOptionsToolbar")
    }
}

/// What can be set about the view a window shows: the order of the list and the gallery, the table's sort,
/// grouping and columns, the board's lanes and cards, and the agenda's dates. Each choice belongs to the place
/// and is kept for the window, except the list's order, which is the app's.
struct CurrentViewOptions: View {
    /// Nil while no window is in front, when the list's order is still the app's to change.
    let browser: Browser?

    var body: some View {
        switch browser?.viewMode {
        case .table: if let browser { ItemTableViewOptions(browser: browser) }
        case .board: if let browser { ItemBoardOptions(browser: browser) }
        case .agenda: if let browser { ItemAgendaOptions(browser: browser) }
        // A collection keeps the order Marfa gives its members, so the app's order does not apply there.
        case .list, .gallery, nil: OrderOptions().disabled(browser?.keepsPlaceOrder == true)
        }
    }
}

/// The lanes a board sorts its cards into, and how much each card shows.
struct ItemBoardOptions: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser

    var body: some View {
        let fields = ItemBoardLayout.availableFields(items: browser.items(in: library), catalogue: library.catalogue)
        let field = ItemBoardLayout.selectedField(browser.boardFields[browser.item], available: fields)
        Picker("Group By", systemImage: "rectangle.split.3x1", selection: Binding { field?.key ?? "" } set: {
            browser.boardFields[browser.item] = $0
        }) {
            ForEach(fields) { Text(verbatim: $0.label).tag($0.key) }
        }
        .pickerStyle(.menu)
        .disabled(fields.isEmpty)
        .accessibilityIdentifier("BoardGroupBy")
        Picker("Card Density", systemImage: "rectangle.compress.vertical", selection: Binding {
            browser.compactBoards[browser.item, default: false]
        } set: { browser.compactBoards[browser.item] = $0 }) {
            Text("Comfortable").tag(false)
            Text("Compact").tag(true)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("BoardCardDensity")
    }
}

/// The date an agenda places each item on.
struct ItemAgendaOptions: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser

    var body: some View {
        let fields = ItemAgendaLayout.fields(for: browser.items(in: library), catalogue: library.catalogue)
        let field = ItemAgendaLayout.selectedField(browser.agendaFields[browser.item], fields: fields)
        Picker("Date Field", systemImage: "calendar", selection: Binding { field ?? "" } set: {
            browser.agendaFields[browser.item] = $0
        }) {
            ForEach(fields) { Text(verbatim: $0.displayLabel).tag($0.key) }
        }
        .pickerStyle(.menu)
        .disabled(fields.isEmpty)
        .accessibilityIdentifier("AgendaDateField")
    }
}
