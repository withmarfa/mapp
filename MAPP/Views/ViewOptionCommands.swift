import SwiftUI

/// The View Options of the table, the board and the timeline as the command palette lists them: each choice not
/// already made. The list's and the gallery's order are the palette's own Sort and Group entries.
struct ViewOptionCommand {
    let title: String
    let systemImage: String
    let action: () -> Void

    /// - Parameter storedColumns: Each place's table columns as kept (`ItemTableColumnLayouts`).
    static func commands(for browser: Browser, in library: any ItemLibrary, storedColumns: Binding<Data>) -> [ViewOptionCommand] {
        guard !browser.showsSettings, !browser.showsSidebarIndex, browser.offersViewOptions else { return [] }
        switch browser.viewMode {
        case .table: return table(browser, library, storedColumns)
        case .board: return board(browser, library)
        case .timeline: return timeline(browser, library)
        case .list, .gallery: return []
        }
    }

    private static func table(_ browser: Browser, _ library: any ItemLibrary, _ storedColumns: Binding<Data>) -> [ViewOptionCommand] {
        let place = browser.item
        let content = ItemTableContent(browser: browser, library: library)
        let layout = ItemTableColumnLayouts.layout(for: place, in: storedColumns.wrappedValue)
        let first = content.sort.first
        var commands: [ViewOptionCommand] = []
        if browser.isSearching, !browser.ordersByRelevance {
            commands.append(.init(title: String(localized: "Sort by Relevance"), systemImage: "arrow.up.arrow.down") {
                browser.orderSearch(byRelevance: true)
            })
        }
        for column in content.columns where layout.shows(column) && column.id != first?.column.id {
            commands.append(.init(title: String(localized: "Sort by \(column.label)"), systemImage: "arrow.up.arrow.down") {
                browser.orderSearch(byRelevance: false)
                browser.tableOptions[place, default: .init()].sort = [ItemTableComparator(column: column, order: column.firstOrder)]
            })
        }
        if let first {
            let reversed: SortOrder = first.order == .forward ? .reverse : .forward
            let title = reversed == .forward ? first.column.ascendingTitle : first.column.descendingTitle
            commands.append(.init(title: String(localized: "Sort \(title)"), systemImage: "arrow.up.arrow.down") {
                browser.tableOptions[place, default: .init()].sort = [ItemTableComparator(column: first.column, order: reversed)]
                    + content.sort.dropFirst()
            })
        }
        for column in content.categoricalColumns where column.id != content.grouping?.id {
            commands.append(.init(title: String(localized: "Group by \(column.label)"), systemImage: "rectangle.grid.1x2") {
                browser.tableOptions[place, default: .init()].grouping = .column(column.id)
                browser.tableOptions[place, default: .init()].collapsed = nil
            })
        }
        if content.grouping != nil {
            commands.append(.init(title: String(localized: "Ungroup"), systemImage: "rectangle.grid.1x2") {
                browser.tableOptions[place, default: .init()].grouping = .none
                browser.tableOptions[place, default: .init()].collapsed = nil
            })
        }
        for column in content.columns where column.content != .title {
            let shown = layout.shows(column)
            commands.append(.init(
                title: shown ? String(localized: "Hide \(column.label) Column") : String(localized: "Show \(column.label) Column"),
                systemImage: "tablecells"
            ) {
                var changed = ItemTableColumnLayouts.layout(for: place, in: storedColumns.wrappedValue)
                changed[visibility: column.id] = shown ? .hidden : .visible
                storedColumns.wrappedValue = ItemTableColumnLayouts.storing(changed, for: place, in: storedColumns.wrappedValue)
            })
        }
        if browser.tableOptions[place]?.filters.isEmpty == false {
            commands.append(.init(title: String(localized: "Clear Filters"), systemImage: "line.3.horizontal.decrease") {
                browser.tableOptions[place, default: .init()].filters = [:]
            })
        }
        return commands
    }

    private static func board(_ browser: Browser, _ library: any ItemLibrary) -> [ViewOptionCommand] {
        let place = browser.item
        let fields = ItemBoardLayout.availableFields(items: browser.items(in: library), catalogue: library.catalogue)
        let field = ItemBoardLayout.selectedField(browser.boardFields[place], available: fields)
        var commands = fields.filter { $0.key != field?.key }.map { field in
            ViewOptionCommand(title: String(localized: "Group by \(field.label)"), systemImage: "rectangle.split.3x1") {
                browser.boardFields[place] = field.key
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

    private static func timeline(_ browser: Browser, _ library: any ItemLibrary) -> [ViewOptionCommand] {
        let place = browser.item
        let fields = ItemTimelineLayout.fields(for: browser.items(in: library), catalogue: library.catalogue)
        let field = ItemTimelineLayout.selectedField(browser.timelineFields[place], fields: fields)
        return fields.filter { $0.key != field }.map { field in
            ViewOptionCommand(title: String(localized: "Date Field: \(field.displayLabel)"), systemImage: "calendar") {
                browser.timelineFields[place] = field.key
            }
        }
    }
}
