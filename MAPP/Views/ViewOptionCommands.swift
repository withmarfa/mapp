import SwiftUI

/// The View Options of the table, the board, the timeline and the index pages as the command palette lists them: each
/// choice not already made. The list's and the gallery's order are the palette's own Sort and Group entries.
struct ViewOptionCommand {
    let title: String
    let systemImage: String
    /// The menu group ⌘K lists it under: the View menu's, unless it sorts or groups.
    var group = PaletteSections.CommandGroup.view
    /// The key the View menu binds to it, as the palette prints it.
    var shortcut: String?
    let action: () -> Void

    /// - Parameter storedColumns: Each place's table columns as kept (`ItemTableColumnLayouts`).
    static func commands(for browser: Browser, in library: any ItemLibrary, storedColumns: Binding<Data>) -> [ViewOptionCommand] {
        if let place = browser.indexPlace { return indexCommands(for: place) }
        guard !browser.showsSettings, browser.offersViewOptions else { return [] }
        switch browser.viewMode {
        case .table: return table(browser, library, storedColumns)
        case .board: return board(browser, library)
        case .timeline: return timeline(browser, library)
        case .calendar: return calendar(browser, library)
        case .gallery: return gallery(browser)
        case .list: return []
        }
    }

    private static func table(_ browser: Browser, _ library: any ItemLibrary, _ storedColumns: Binding<Data>) -> [ViewOptionCommand] {
        let place = browser.item
        let content = browser.tableContent(in: library)
        let first = content.sort.first
        var commands: [ViewOptionCommand] = []
        if browser.isSearching, !browser.ordersByRelevance {
            commands.append(.init(title: String(localized: "Sort by Relevance"), systemImage: "arrow.up.arrow.down", group: .sortAndGroup) {
                browser.orderSearch(byRelevance: true)
            })
        }
        for column in content.columns where browser.showsColumn(column, stored: storedColumns.wrappedValue) && column.id != first?.column.id {
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
        for column in content.categoricalColumns where column.id != content.grouping?.id {
            commands.append(.init(title: String(localized: "Group by \(column.label)"), systemImage: "rectangle.grid.1x2", group: .sortAndGroup) {
                browser.tableOptions[place, default: .init()].grouping = .column(column.id)
                browser.tableOptions[place, default: .init()].collapsed = nil
            })
        }
        if content.grouping != nil {
            commands.append(.init(title: String(localized: "Ungroup"), systemImage: "rectangle.grid.1x2", group: .sortAndGroup) {
                browser.tableOptions[place, default: .init()].grouping = .none
                browser.tableOptions[place, default: .init()].collapsed = nil
            })
        }
        for column in content.columns where column.content != .title {
            let shown = browser.showsColumn(column, stored: storedColumns.wrappedValue)
            commands.append(.init(
                title: shown ? String(localized: "Hide \(column.label) Column") : String(localized: "Show \(column.label) Column"),
                systemImage: "tablecells"
            ) {
                browser.setColumn(column, shown: !shown, stored: storedColumns)
            })
        }
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

    private static func board(_ browser: Browser, _ library: any ItemLibrary) -> [ViewOptionCommand] {
        let place = browser.item
        let fields = browser.boardFieldChoices(in: library)
        let field = ItemBoardLayout.selectedField(browser.boardFieldKey(in: place), available: fields)
        var commands = fields.filter { $0.key != field?.key }.map { field in
            ViewOptionCommand(title: String(localized: "Group by \(field.label)"), systemImage: "rectangle.split.3x1", group: .sortAndGroup) {
                browser.setBoardField(field.key, in: place)
            }
        }
        let compact = browser.compactBoards[place, default: false]
        commands.append(.init(
            title: compact ? String(localized: "Comfortable Cards") : String(localized: "Compact Cards"),
            systemImage: "rectangle.compress.vertical"
        ) {
            browser.compactBoards[place] = !compact
        })
        return commands
    }

    private static func calendar(_ browser: Browser, _ library: any ItemLibrary) -> [ViewOptionCommand] {
        let scale = browser.calendarScale
        let unit = scale == .week ? String(localized: "Week") : String(localized: "Month")
        var commands = [
            ViewOptionCommand(title: String(localized: "Go to Today"), systemImage: "calendar", shortcut: "⌘T") {
                browser.moveCalendar(by: nil, now: library.now())
            },
            ViewOptionCommand(title: String(localized: "Previous \(unit)"), systemImage: "chevron.left", shortcut: "⌥⌘←") {
                browser.moveCalendar(by: -1, now: library.now())
            },
            ViewOptionCommand(title: String(localized: "Next \(unit)"), systemImage: "chevron.right", shortcut: "⌥⌘→") {
                browser.moveCalendar(by: 1, now: library.now())
            },
        ]
        if scale == .week {
            commands.append(ViewOptionCommand(title: String(localized: "Calendar by Month"), systemImage: "calendar", shortcut: "⌥⌘2") {
                browser.changeCalendarScale(.month)
            })
        } else {
            commands.append(ViewOptionCommand(title: String(localized: "Calendar by Week"), systemImage: "calendar", shortcut: "⌥⌘1") {
                browser.changeCalendarScale(.week)
            })
        }
        commands.append(ViewOptionCommand(
            title: browser.showsCalendarMonth ? String(localized: "Hide Month") : String(localized: "Show Month"),
            systemImage: "calendar.day.timeline.left", shortcut: "⇧⌘D"
        ) { browser.toggleCalendarMonth() })
        return commands
    }

    private static func gallery(_ browser: Browser) -> [ViewOptionCommand] {
        ViewCards.Size.allCases.filter { $0 != browser.cards.size }.map { size in
            ViewOptionCommand(title: String(localized: size.cardsTitle), systemImage: "square.grid.2x2") { browser.setCardSize(size) }
        }
    }

    private static func timeline(_ browser: Browser, _ library: any ItemLibrary) -> [ViewOptionCommand] {
        let place = browser.item
        let fields = browser.timelineFieldChoices(in: library)
        let field = ItemTimelineLayout.selectedField(browser.timelineFields[place], fields: fields)
        var commands = [ViewOptionCommand(title: String(localized: "Go to Today"), systemImage: "calendar", shortcut: "⌘T") {
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
