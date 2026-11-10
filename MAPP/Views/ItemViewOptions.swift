import SwiftUI

/// View choices remain in the menu when no document window is in front.
struct ItemViewOptions: View {
    /// Nil while no window is in front, which leaves the choices in the menu, dimmed.
    let browser: Browser?
    /// The layouts the window's place can show; all of them while no window is in front.
    var modes = ItemViewMode.allCases
    /// Whether each choice binds its Command-number key; the toolbar's copy of the choices leaves them to the menu.
    var bindsKeys = false

    var body: some View {
        Group {
            choice("as List", systemImage: ItemViewMode.list.symbol, .list, key: "1")
            choice("as Gallery", systemImage: ItemViewMode.gallery.symbol, .gallery, key: "2")
            choice("as Table", systemImage: ItemViewMode.table.symbol, .table, key: "3")
            choice("as Board", systemImage: ItemViewMode.board.symbol, .board, key: "4")
            choice("as Timeline", systemImage: ItemViewMode.timeline.symbol, .timeline, key: "5")
        }
        .disabled(browser == nil)
    }

    private func identifier(_ mode: ItemViewMode) -> String {
        switch mode {
        case .list: "ViewAsList"
        case .gallery: "ViewAsGallery"
        case .table: "ViewAsTable"
        case .board: "ViewAsBoard"
        case .timeline: "ViewAsTimeline"
        }
    }

    @ViewBuilder
    private func choice(_ title: LocalizedStringKey, systemImage: String, _ mode: ItemViewMode, key: KeyEquivalent) -> some View {
        if modes.contains(mode) {
            Toggle(title, systemImage: systemImage, isOn: Binding { browser?.viewMode == mode } set: { _ in browser?.viewMode = mode })
                .keyboardShortcut(bindsKeys ? KeyboardShortcut(key) : nil)
                .accessibilityIdentifier(identifier(mode))
        }
    }
}

/// One pop-up button stays at the window's trailing side whichever view is shown.
struct ViewModeMenu: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser

    var body: some View {
        // A menu rather than a picker for the toolbar's sake: the tray and Icon and Text name an item by its label. Its
        // choices are the View menu's own, so one control makes the change however it is asked for.
        Menu("View As", systemImage: browser.viewMode.symbol) {
            ItemViewOptions(browser: browser, modes: browser.availableViewModes(in: library))
        }
        .help("View As")
        .accessibilityIdentifier("ViewModeMenu")
    }
}

/// The options of the view a window shows, in one menu at the same place on every view's toolbar: after Search
/// (and the table's Filter), before View As. The View menu holds the same options (`CurrentViewOptions`), since a
/// toolbar can be hidden or customized.
struct ViewOptionsMenu: View {
    @CurrentLibrary private var library
    let browser: Browser

    var body: some View {
        Menu("View Options", systemImage: "slider.horizontal.3") {
            CurrentViewOptions(browser: browser)
            if SavedViews.canEdit(browser, in: library), browser.offersViewOptions {
                Divider()
                Button("Edit View") { browser.openViewPanel(in: library) }
                    .accessibilityIdentifier("EditViewMenuItem")
            }
        }
        .menuIndicator(.hidden)
        .help("View Options")
        .accessibilityIdentifier("ViewOptionsToolbar")
    }
}

/// What can be set about the view a window shows: the order of the list and the gallery, the table's sort,
/// grouping and columns, the board's lanes and cards, and the timeline's dates. Each choice belongs to the place
/// and is kept for the window, except the list's order, which is the app's.
struct CurrentViewOptions: View {
    /// Nil while no window is in front, when the list's order is still the app's to change.
    let browser: Browser?

    var body: some View {
        switch browser?.viewMode {
        case .table: if let browser { ItemTableViewOptions(browser: browser) }
        case .board: if let browser { ItemBoardOptions(browser: browser) }
        case .timeline: if let browser { ItemTimelineOptions(browser: browser) }
        // A collection keeps the order Marfa gives its members, so the app's order does not apply there.
        case .list, .gallery, nil:
            // A saved view has its own sort and group, which the list and the gallery take as the table does.
            if let browser, browser.isViewPlace {
                ItemTableViewOptions(browser: browser, columns: false)
            } else {
                OrderOptions(browser: browser).disabled(browser?.keepsPlaceOrder == true)
            }
            if let browser {
                Divider()
                IncludeSubtypesOption(browser: browser)
            }
        }
    }
}

/// The lanes a board sorts its cards into, and how much each card shows.
struct ItemBoardOptions: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser

    var body: some View {
        let fields = browser.boardFieldChoices(in: library)
        let field = ItemBoardLayout.selectedField(browser.boardFieldKey(in: browser.item), available: fields)
        Picker("Group by", systemImage: "rectangle.split.3x1", selection: Binding { field?.key ?? "" } set: {
            browser.setBoardField($0, in: browser.item)
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
        Divider()
        IncludeSubtypesOption(browser: browser)
    }
}

/// The date a timeline places each item on.
struct ItemTimelineOptions: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser

    var body: some View {
        let fields = browser.timelineFieldChoices(in: library)
        let field = ItemTimelineLayout.selectedField(browser.timelineFields[browser.item], fields: fields)
        Picker("Date Field", systemImage: "calendar", selection: Binding { field ?? "" } set: {
            browser.setTimelineField($0, in: library)
        }) {
            ForEach(fields) { Text(verbatim: $0.label).tag($0.key) }
        }
        .pickerStyle(.menu)
        .disabled(fields.isEmpty)
        .accessibilityIdentifier("TimelineDateField")
    }
}
