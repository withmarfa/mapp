import SwiftUI

/// The layout's own section of the View panel: what only that layout has. A list has its properties and density, a
/// table its columns and how many rows it shows at a time, a board its properties and cards, a gallery its cards and
/// properties, a calendar its span and a timeline its date and properties.
struct ViewPanelLayoutRows: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    let panel: ViewPanel
    /// Only watched: another window may change a place's density, which `browser.density` reads from the defaults.
    @AppStorage(PlaceDensities.key) private var placeDensities: Data?

    var body: some View {
        switch browser.viewMode {
        case .list:
            ViewPanelPropertiesRow(browser: browser, panel: panel)
            density
        case .table:
            ViewPanelPropertiesRow(browser: browser, panel: panel)
            tableRows
        case .board:
            ViewPanelPropertiesRow(browser: browser, panel: panel)
            boardCards
        case .gallery:
            ViewPanelGalleryRows(browser: browser)
            ViewPanelPropertiesRow(browser: browser, panel: panel)
        case .calendar:
            calendarSpan
        case .timeline:
            timelineDate
            ViewPanelPropertiesRow(browser: browser, panel: panel)
        }
    }

    private var density: some View {
        let _ = placeDensities
        return ViewPanelChoiceRow(
            symbol: "rectangle.compress.vertical", label: String(localized: "Density"),
            choices: [Density?.none] + Density.allCases.map(Optional.some),
            title: { $0?.title ?? String(localized: "As in Settings") },
            selection: browser.density, choose: { browser.changeDensity($0) })
            .accessibilityIdentifier("ViewPanelDensity")
    }

    private var tableRows: some View {
        ViewPanelChoiceRow(
            symbol: "list.number", label: String(localized: "Rows at a Time"), choices: TablePageSize.allCases,
            title: { $0.rawValue.formatted() }, selection: browser.tablePageSize,
            choose: { browser.tableOptions[browser.shown, default: .init()].pageSize = $0 })
            .accessibilityIdentifier("ViewPanelTableRows")
    }

    private var boardCards: some View {
        ViewPanelChoiceRow(
            symbol: "rectangle.compress.vertical", label: String(localized: "Card Size"), choices: [false, true],
            title: { $0 ? String(localized: "Compact") : String(localized: "Comfortable") },
            selection: browser.compactBoards[browser.shown, default: false],
            choose: { browser.setCompactBoard($0, in: browser.shown) })
            .accessibilityIdentifier("BoardCardDensity")
    }

    private var calendarSpan: some View {
        ViewPanelChoiceRow(
            symbol: "calendar", label: String(localized: "Show"), choices: CalendarScale.allCases,
            title: { String(localized: $0.title) }, selection: browser.calendarScale,
            choose: { browser.changeCalendarScale($0) })
            .accessibilityIdentifier("CalendarScale")
    }

    private var timelineDate: some View {
        let fields = browser.timelineFieldChoices(in: library)
        let field = ItemTimelineLayout.selectedField(browser.timelineFields[browser.shown], fields: fields)
        let labels = Dictionary(fields.map { ($0.key, $0.label) }, uniquingKeysWith: { first, _ in first })
        return ViewPanelChoiceRow(
            symbol: "calendar", label: String(localized: "Date"), choices: [String?.none] + fields.map { Optional($0.key) },
            title: { $0.flatMap { labels[$0] } ?? String(localized: "Date of Each Type") }, selection: field,
            choose: { browser.setTimelineField($0, in: library) })
            .disabled(fields.isEmpty)
            .accessibilityIdentifier("TimelineDateField")
    }
}

/// The row that opens Properties, or a table's Columns, with what they show.
private struct ViewPanelPropertiesRow: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    let panel: ViewPanel

    var body: some View {
        let isTable = browser.viewMode == .table
        ViewPanelOpenRow(
            symbol: "list.bullet.rectangle", label: isTable ? String(localized: "Columns") : String(localized: "Properties"), value: value
        ) { panel.page = .properties }
        .accessibilityIdentifier("ViewPanelPropertiesRow")
    }

    private var value: String {
        let properties = browser.properties
        guard properties.isChanged else { return String(localized: "As in Layouts") }
        let shown = browser.offeredProperties(in: library).filter { $0.content != .title && properties.isShown($0) }
        return shown.isEmpty ? String(localized: "None") : shown.map(\.label).formatted(.list(type: .and, width: .narrow))
    }
}

/// A gallery's cards: what fills each card's picture area, how large a card is, its shape, and whether a picture fits
/// whole. What a card says under its picture is its type's look until the view's Properties change it.
private struct ViewPanelGalleryRows: View {
    @Bindable var browser: Browser

    var body: some View {
        let cards = browser.cards
        ViewPanelChoiceRow(
            symbol: "photo", label: String(localized: "Preview"), choices: ViewCards.Preview.allCases, title: \.title,
            selection: cards.preview, choose: { value in browser.changeCards { $0.preview = value } })
            .accessibilityIdentifier("ViewPanelCardPreview")
        ViewPanelChoiceRow(
            symbol: "square.resize", label: String(localized: "Card Size"), choices: ViewCards.Size.allCases, title: \.title,
            selection: cards.size, choose: { browser.setCardSize($0) })
            .accessibilityIdentifier("ViewPanelCardSize")
        ViewPanelChoiceRow(
            symbol: "rectangle.portrait", label: String(localized: "Shape"), choices: ViewCards.Shape.allCases, title: \.title,
            selection: cards.shape, choose: { value in browser.changeCards { $0.shape = value } })
            .disabled(cards.preview == .none)
            .accessibilityIdentifier("ViewPanelCardShape")
        ViewPanelSwitchRow(
            symbol: "arrow.down.right.and.arrow.up.left", label: String(localized: "Fit Picture"), isOn: cards.fitsPicture,
            set: { value in browser.changeCards { $0.fitsPicture = value } })
            .disabled(!cards.preview.showsPicture)
            .help(cards.preview.showsPicture ? "" : String(localized: "Only a card with a picture can fit it."))
            .accessibilityIdentifier("ViewPanelCardFitPicture")
    }
}

/// The layouts in the View menu, each with its key (⌘1 onwards), ticked for the one showing. They stay in the menu,
/// dimmed, while no window is in front.
struct ViewLayoutCommands: View {
    /// Nil while no window is in front.
    let browser: Browser?
    /// The layouts the window's place can show; all of them while no window is in front.
    var modes = ItemViewMode.allCases
    var shortcuts: ShortcutBindings?

    var body: some View {
        Group {
            choice("View as List", .list, command: .viewAsList)
            choice("View as Gallery", .gallery, command: .viewAsGallery)
            choice("View as Table", .table, command: .viewAsTable)
            choice("View as Board", .board, command: .viewAsBoard)
            choice("View as Timeline", .timeline, command: .viewAsTimeline)
            choice("View as Calendar", .calendar, command: .viewAsCalendar)
        }
        .disabled(browser == nil)
    }

    @ViewBuilder
    private func choice(_ title: LocalizedStringKey, _ mode: ItemViewMode, command: ShortcutCommand) -> some View {
        if modes.contains(mode) {
            Toggle(title, systemImage: mode.symbol, isOn: Binding { browser?.viewMode == mode } set: { _ in browser?.viewMode = mode })
                .shortcut(command, shortcuts)
                .accessibilityIdentifier("ViewAs\(mode.rawValue.capitalized)")
        }
    }
}

/// The View menu's commands for the layout in front, which the View panel does not hold: moving through a calendar or a
/// timeline, folding a list's or a table's groups, and Clear Filters.
struct CurrentLayoutCommands: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    var shortcuts: ShortcutBindings?

    var body: some View {
        switch browser.viewMode {
        case .calendar:
            ItemCalendarOptions(browser: browser, shortcuts: shortcuts)
        case .timeline:
            Button("Today", systemImage: "calendar.circle") { browser.requestTimelineToday() }
                .shortcut(.today, shortcuts)
        case .list, .table:
            let grouped = browser.shownGrouping(in: library) != .none && browser.datedList == nil
            Button("Collapse All Groups") { browser.collapseAllGroups(in: library) }
                .disabled(!grouped)
            Button("Expand All Groups") { browser.expandAllGroups() }
                .disabled(!grouped)
        case .board, .gallery:
            EmptyView()
        }
        Button("Clear Filters", systemImage: "line.3.horizontal.decrease") { browser.clearFilters() }
            .shortcut(.clearFilters, shortcuts)
            .disabled(browser.filterCount == 0)
    }
}

extension ViewCards.Preview {
    var title: String {
        switch self {
        case .pictureOrText: String(localized: "Picture or Text")
        case .picture: String(localized: "Picture")
        case .text: String(localized: "Text")
        case .none: String(localized: "None")
        }
    }
}

extension ViewCards.Size {
    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }
}

extension ViewCards.Shape {
    var title: String {
        switch self {
        case .standard: String(localized: "Standard")
        case .square: String(localized: "Square")
        case .cover: String(localized: "Cover")
        }
    }
}
