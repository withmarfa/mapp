import SwiftUI

/// The View Options of every layout as the command palette lists them: each choice not already made.
struct ViewOptionCommand {
    let title: String
    let systemImage: String
    /// The menu group ⌘K lists it under: the View menu's, unless it sorts or groups.
    var group = PaletteSections.CommandGroup.view
    /// The menu command whose key the palette prints beside it.
    var key: ShortcutCommand?
    let action: () -> Void

    static func commands(for browser: Browser, in library: any ItemLibrary) -> [ViewOptionCommand] {
        guard browser.offersViewOptions, !browser.showsPlaceIndex else { return [] }
        switch browser.viewMode {
        case .table: return table(browser, library)
        case .board: return board(browser, library) + properties(browser, library)
        case .timeline: return timeline(browser, library) + properties(browser, library)
        case .calendar: return calendar(browser, library)
        case .gallery: return gallery(browser) + sorting(browser, library) + grouping(browser, library) + properties(browser, library)
        case .list: return sorting(browser, library) + grouping(browser, library) + properties(browser, library)
        }
    }

    /// The list's and the gallery's Sort by, as the place's own: each field it can sort by, then the other direction.
    private static func sorting(_ browser: Browser, _ library: any ItemLibrary) -> [ViewOptionCommand] {
        guard !browser.keepsPlaceOrder else { return [] }
        let content = browser.tableContent(in: library)
        let shown = SavedViews.arrangement(browser, content: content, order: browser.storedOrder).sort
        let first = browser.ordersByRelevance ? nil : shown.first
        var commands: [ViewOptionCommand] = []
        if browser.isSearching, !browser.ordersByRelevance {
            commands.append(.init(title: String(localized: "Sort by Relevance"), systemImage: "arrow.up.arrow.down", group: .sortAndGroup) {
                browser.orderSearch(byRelevance: true)
            })
        }
        for column in content.sortChoices where column.id != first?.column.id {
            commands.append(.init(title: String(localized: "Sort by \(column.label)"), systemImage: "arrow.up.arrow.down", group: .sortAndGroup) {
                browser.orderSearch(byRelevance: false)
                browser.chooseSort([ItemTableComparator(column: column, order: column.firstOrder)])
            })
        }
        if let first {
            let reversed: SortOrder = first.order == .forward ? .reverse : .forward
            let title = reversed == .forward ? first.column.ascendingTitle : first.column.descendingTitle
            commands.append(.init(title: String(localized: "Sort \(title)"), systemImage: "arrow.up.arrow.down", group: .sortAndGroup) {
                browser.chooseSort([ItemTableComparator(column: first.column, order: reversed)] + shown.dropFirst())
            })
        }
        return commands
    }

    private static func table(_ browser: Browser, _ library: any ItemLibrary) -> [ViewOptionCommand] {
        let place = browser.shown
        let content = browser.tableContent(in: library)
        let first = content.sort.first
        var commands: [ViewOptionCommand] = []
        if browser.isSearching, !browser.ordersByRelevance {
            commands.append(.init(title: String(localized: "Sort by Relevance"), systemImage: "arrow.up.arrow.down", group: .sortAndGroup) {
                browser.orderSearch(byRelevance: true)
            })
        }
        for column in content.columns where browser.showsColumn(column) && column.id != first?.column.id {
            commands.append(.init(title: String(localized: "Sort by \(column.label)"), systemImage: "arrow.up.arrow.down", group: .sortAndGroup) {
                browser.orderSearch(byRelevance: false)
                browser.tableOptions[place, default: .init()].sort = [ItemTableComparator(column: column, order: column.firstOrder)]
            })
        }
        if let first {
            let reversed: SortOrder = first.order == .forward ? .reverse : .forward
            let title = reversed == .forward ? first.column.ascendingTitle : first.column.descendingTitle
            commands.append(.init(title: String(localized: "Sort \(title)"), systemImage: "arrow.up.arrow.down", group: .sortAndGroup) {
                browser.tableOptions[place, default: .init()].sort = [ItemTableComparator(column: first.column, order: reversed)]
                    + content.sort.dropFirst()
            })
        }
        commands += grouping(browser, library)
        commands += properties(browser, library)
        if browser.tableRowsNotLoaded(in: content) > 0 {
            commands.append(.init(title: String(localized: "Load More Rows"), systemImage: "arrow.down.to.line") {
                browser.loadMoreTableRows(in: content)
            })
        }
        for size in TablePageSize.allCases where size != browser.tablePageSize {
            commands.append(.init(title: String(localized: "Show \(size.rawValue) Rows at a Time"), systemImage: "list.number") {
                browser.tableOptions[place, default: .init()].pageSize = size
            })
        }
        commands.append(.init(
            title: String(localized: browser.toggleFiltersTitle),
            systemImage: "line.3.horizontal.decrease"
        ) {
            browser.toggleFilterRow()
        })
        commands.append(.init(title: String(localized: "Add Filter…"), systemImage: "line.3.horizontal.decrease") {
            browser.requestAddFilter()
        })
        if browser.tableOptions[place]?.isFiltering == true {
            commands.append(.init(title: String(localized: "Clear Filters"), systemImage: "line.3.horizontal.decrease") {
                browser.clearFilters()
            })
        }
        return commands
    }

    /// Show or hide each property the layout lists, and Use Layouts once the list is changed.
    private static func properties(_ browser: Browser, _ library: any ItemLibrary) -> [ViewOptionCommand] {
        var commands = browser.offeredProperties(in: library).filter { $0.content != .title }.map { column in
            let shown = browser.showsColumn(column)
            return ViewOptionCommand(
                title: shown ? String(localized: "Hide \(column.label) Property") : String(localized: "Show \(column.label) Property"),
                systemImage: "list.bullet.rectangle"
            ) {
                browser.setColumn(column, shown: !shown)
            }
        }
        if browser.properties.isChanged {
            commands.append(.init(title: String(localized: "Use Layouts"), systemImage: "arrow.uturn.backward") { browser.useLayouts() })
        }
        return commands
    }

    private static func board(_ browser: Browser, _ library: any ItemLibrary) -> [ViewOptionCommand] {
        let place = browser.shown
        var commands = grouping(browser, library)
        let compact = browser.compactBoards[place, default: false]
        commands.append(.init(
            title: compact ? String(localized: "Comfortable Cards") : String(localized: "Compact Cards"),
            systemImage: "rectangle.compress.vertical"
        ) {
            browser.setCompactBoard(!compact, in: place)
        })
        return commands
    }

    private static func calendar(_ browser: Browser, _ library: any ItemLibrary) -> [ViewOptionCommand] {
        let scale = browser.calendarScale
        let unit = scale == .week ? String(localized: "Week") : String(localized: "Month")
        var commands = [
            ViewOptionCommand(title: String(localized: "Today"), systemImage: "calendar.circle", key: .today) {
                browser.moveCalendar(by: nil, now: library.now())
            },
            ViewOptionCommand(title: String(localized: "Previous \(unit)"), systemImage: "chevron.left", key: .previousPeriod) {
                browser.moveCalendar(by: -1, now: library.now())
            },
            ViewOptionCommand(title: String(localized: "Next \(unit)"), systemImage: "chevron.right", key: .nextPeriod) {
                browser.moveCalendar(by: 1, now: library.now())
            },
        ]
        if scale == .week {
            commands.append(ViewOptionCommand(title: String(localized: "Calendar by Month"), systemImage: "calendar", key: .showMonthScale) {
                browser.changeCalendarScale(.month)
            })
        } else {
            commands.append(ViewOptionCommand(title: String(localized: "Calendar by Week"), systemImage: "calendar", key: .showWeek) {
                browser.changeCalendarScale(.week)
            })
        }
        commands.append(ViewOptionCommand(
            title: browser.showsCalendarMonth ? String(localized: "Hide Month") : String(localized: "Show Month"),
            systemImage: "calendar", key: .toggleMonth
        ) { browser.toggleCalendarMonth() })
        return commands
    }

    private static func gallery(_ browser: Browser) -> [ViewOptionCommand] {
        ViewCards.Size.allCases.filter { $0 != browser.cards.size }.map { size in
            ViewOptionCommand(title: String(localized: size.cardsTitle), systemImage: "square.grid.2x2") { browser.setCardSize(size) }
        }
    }

    private static func timeline(_ browser: Browser, _ library: any ItemLibrary) -> [ViewOptionCommand] {
        let place = browser.shown
        let fields = browser.timelineFieldChoices(in: library)
        let field = ItemTimelineLayout.selectedField(browser.timelineFields[place], fields: fields)
        var commands = [ViewOptionCommand(title: String(localized: "Today"), systemImage: "calendar.circle", key: .today) {
            browser.requestTimelineToday()
        }]
        commands += fields.filter { $0.key != field }.map { field in
            ViewOptionCommand(title: String(localized: "Date Field: \(field.label)"), systemImage: "calendar") {
                browser.setTimelineField(field.key, in: library)
            }
        }
        if field != nil {
            commands.append(ViewOptionCommand(title: String(localized: "Date of Each Type"), systemImage: "calendar") {
                browser.setTimelineField(nil, in: library)
            })
        }
        return commands
    }
}
