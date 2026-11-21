import SwiftUI

/// View choices remain in the menu when no document window is in front.
struct ItemViewOptions: View {
    /// Nil while no window is in front, which leaves the choices in the menu, dimmed.
    let browser: Browser?
    /// The layouts the window's place can show; all of them while no window is in front.
    var modes = ItemViewMode.allCases
    /// The keys the menu binds to each choice; the toolbar's copy of the choices has none and leaves them to the menu.
    var shortcuts: ShortcutBindings?

    var body: some View {
        Group {
            choice("as List", systemImage: ItemViewMode.list.symbol, .list, command: .viewAsList)
            choice("as Gallery", systemImage: ItemViewMode.gallery.symbol, .gallery, command: .viewAsGallery)
            choice("as Table", systemImage: ItemViewMode.table.symbol, .table, command: .viewAsTable)
            choice("as Board", systemImage: ItemViewMode.board.symbol, .board, command: .viewAsBoard)
            choice("as Timeline", systemImage: ItemViewMode.timeline.symbol, .timeline, command: .viewAsTimeline)
            choice("as Calendar", systemImage: ItemViewMode.calendar.symbol, .calendar, command: .viewAsCalendar)
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
        case .calendar: "ViewAsCalendar"
        }
    }

    @ViewBuilder
    private func choice(_ title: LocalizedStringKey, systemImage: String, _ mode: ItemViewMode, command: ShortcutCommand) -> some View {
        if modes.contains(mode) {
            Toggle(title, systemImage: systemImage, isOn: Binding { browser?.viewMode == mode } set: { _ in browser?.viewMode = mode })
                .shortcut(command, shortcuts)
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

/// The options of the view a window shows, in one menu at the same place on every view's toolbar: after Search,
/// before View As. It opens with Show Filters or Hide Filters, and is tinted and counts the filters where the place has
/// any, so a saved view that opens with its row hidden still says filters apply. The View menu holds the same options
/// (`CurrentViewOptions`), since a toolbar can be hidden or customized.
struct ViewOptionsMenu: View {
    @CurrentLibrary private var library
    @Environment(\.controlActiveState) private var activeState
    // Read by `offersResetView`, so a change of the default view draws the menu again.
    @AppStorage(PlaceDefaults.key) private var storedDefaults = Data()
    @AppStorage(PlaceDensities.key) private var storedDensities = Data()
    @AppStorage(ItemTableColumnLayouts.key) private var storedColumns = Data()
    let browser: Browser

    var body: some View {
        let _ = (storedDefaults, storedDensities, storedColumns)
        let count = browser.filterCount
        // Only an active window tints the button. In any other state it sets no style of its own, so it dims as its
        // neighbours do.
        let tinted = count > 0 && activeState != .inactive
        Menu {
            if browser.offersViewOptions {
                Button(browser.toggleFiltersTitle) { browser.toggleFilterRow() }
                    .accessibilityIdentifier("ToggleFiltersMenuItem")
                Divider()
            }
            CurrentViewOptions(browser: browser)
            if SavedViews.canEdit(browser, in: library), browser.offersViewOptions {
                Divider()
                Button("Edit View") { browser.openViewPanel(in: library) }
                    .accessibilityIdentifier("EditViewMenuItem")
            }
            DefaultViewOptions(browser: browser, resets: browser.offersResetView)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "slider.horizontal.3")
                if count > 0 { Text("\(count)").font(.caption.monospacedDigit()) }
            }
            .tintedWhen(tinted)
            .accessibilityLabel(count > 0 ? Text("View Options, \(count) filters applied") : Text("View Options"))
        }
        .menuIndicator(.hidden)
        .help("View Options")
        .accessibilityIdentifier("ViewOptionsToolbar")
    }
}

/// The last items of View Options in a place that is not a saved view: Reset View, once its default view is changed, and
/// Save as View… under it, while there is something to keep. The View menu and the palette hold the same commands.
struct DefaultViewOptions: View {
    @CurrentLibrary private var library
    let browser: Browser
    /// Whether Reset View shows. The caller works it out, since it watches the stored choices this reads and an unchanged
    /// menu does not run this body again when they change.
    let resets: Bool

    var body: some View {
        let saves = browser.offersViewOptions && SavedViews.hasChoicesToKeep(browser, in: library)
        if resets || saves {
            Divider()
        }
        if resets {
            Button("Reset View") { browser.resetView(in: library) }
                .accessibilityIdentifier("ResetViewMenuItem")
        }
        if saves {
            let canSave = SavedViews.canSave(browser, in: library)
            Button("Save as View…") { browser.openNewViewPanel(in: library) }
                .disabled(!canSave)
                .help(canSave ? "Make a view of what this window shows" : "Saving a view needs your Marfa server")
                .accessibilityIdentifier("SaveAsViewMenuItem")
        }
    }
}

/// What can be set about the view a window shows: the order of the list and the gallery, the table's sort,
/// grouping and columns, the board's lanes and cards, and the timeline's dates. Each choice belongs to the place
/// and is kept in its default view on this Mac, except the list's order, which is the app's.
struct CurrentViewOptions: View {
    /// Nil while no window is in front, when the list's order is still the app's to change.
    let browser: Browser?
    var shortcuts: ShortcutBindings?

    var body: some View {
        switch browser?.viewMode {
        case .table: if let browser { ItemTableViewOptions(browser: browser) }
        case .board: if let browser { ItemBoardOptions(browser: browser) }
        case .timeline: if let browser { ItemTimelineOptions(browser: browser, shortcuts: shortcuts) }
        case .calendar:
            if let browser {
                ItemCalendarOptions(browser: browser, shortcuts: shortcuts)
                Divider()
                IncludeSubtypesOption(browser: browser)
            }
        // A collection keeps the order Marfa gives its members, so the app's order does not apply there.
        case .list, .gallery, nil:
            if let browser, browser.viewMode == .gallery {
                GalleryCardSizeOptions(browser: browser)
                Divider()
            }
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
        } set: { browser.setCompactBoard($0, in: browser.item) }) {
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
    var shortcuts: ShortcutBindings?

    var body: some View {
        let fields = browser.timelineFieldChoices(in: library)
        let field = ItemTimelineLayout.selectedField(browser.timelineFields[browser.item], fields: fields)
        Button("Today", systemImage: "calendar.circle") { browser.requestTimelineToday() }
            .shortcut(.today, shortcuts)
        Divider()
        Picker("Date Field", systemImage: "calendar", selection: Binding { field ?? "" } set: {
            browser.setTimelineField($0.isEmpty ? nil : $0, in: library)
        }) {
            Text("Date of Each Type").tag("")
            Divider()
            ForEach(fields) { Text(verbatim: $0.label).tag($0.key) }
        }
        .pickerStyle(.menu)
        .disabled(fields.isEmpty)
        .accessibilityIdentifier("TimelineDateField")
    }
}

private extension View {
    /// The accent color when `tinted`, and no style of its own otherwise, which a toolbar dims with its window.
    @ViewBuilder func tintedWhen(_ tinted: Bool) -> some View {
        if tinted { foregroundStyle(Color.accentColor) } else { self }
    }
}
