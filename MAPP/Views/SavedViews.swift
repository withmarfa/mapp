import SwiftUI

/// What the window shows as a view would hold, and what a view's panel and commands read of the window. Making,
/// duplicating and deleting a view need the server, so they are offered only while the library can reach it
/// (`ItemLibrary.reachesServer`); editing one in the panel is not, nor is a change of its layout, columns or cards.
enum SavedViews {
    /// Whether the window's place can be saved as a view: Recents, the indexes, a single favorite
    /// and a collection cannot.
    static func canSave(_ browser: Browser, in library: any ItemLibrary) -> Bool {
        library.isLoaded && library.reachesServer && !browser.showsSidebarIndex
            && ViewDraft.query(for: browser.item, catalogue: library.catalogue, views: library.views) != nil
    }

    /// Whether Edit View has a panel for the window's place: a saved view, or a place that could become one.
    static func canEdit(_ browser: Browser, in library: any ItemLibrary) -> Bool {
        library.isLoaded && !browser.showsSidebarIndex
            && (shown(browser, in: library) != nil
                || ViewDraft.query(for: browser.item, catalogue: library.catalogue, views: library.views) != nil)
    }

    /// The view the window shows, while the library holds it.
    static func shown(_ browser: Browser, in library: any ItemLibrary) -> LibraryView? {
        guard case .view(let id) = browser.item else { return nil }
        return library.views.first { $0.id == id }
    }

    /// What the window shows, as the table works it out. Every layout applies the place's filters.
    static func window(_ browser: Browser, in library: any ItemLibrary) -> ViewDraft.Window {
        let content = browser.tableContent(in: library)
        let options = browser.tableOptions[browser.item] ?? ItemTableOptions()
        let search = browser.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        // The order and grouping come from what the layout shows (`arrangement`), which is what the panel shows too.
        let layoutShows = arrangement(browser, content: content, order: browser.storedOrder)
        // The grouping the layout shows: a board's lanes, the place's grouping, or the starting order's dates by day.
        var grouping: ItemTableColumn?
        var groupMode = GroupMode.value
        if case .column(let id, let mode) = browser.shownGrouping(in: library), let column = content.columns.first(where: { $0.id == id }) {
            grouping = column
            groupMode = mode
        }
        var seededTypes: [String]?
        if case .view(let id) = browser.item { seededTypes = browser.viewSeeds[id]?.types }
        return ViewDraft.Window(
            place: browser.item, columns: content.columns, sort: layoutShows.sort, grouping: grouping, groupMode: groupMode,
            groupOrder: options.groupOrder, hiddenGroups: options.hiddenGroups,
            filter: options.filter, targets: content.filterOffer.targets, search: search.isEmpty ? nil : search,
            layout: layout(of: browser, in: library, order: nil), timelineDate: browser.timelineFields[browser.item],
            seededTypes: seededTypes, dated: layoutShows.isDated ? ViewDraft.Dated(sort: layoutShows.sort, hasSections: layoutShows.hasDateSections) : nil,
            includesSubtypes: browser.stacksSubtypes(in: library))
    }

    /// What the window shows in the layout it shows it in, with that layout's own order and grouping, so a new
    /// view keeps what the person sees.
    static func window(_ browser: Browser, in library: any ItemLibrary, order: ItemOrder) -> ViewDraft.Window {
        var window = window(browser, in: library)
        window.layout = layout(of: browser, in: library, order: order)
        return window
    }

    /// The layout the window shows. Without the list's order, which only a new view takes, a list or a gallery is
    /// read as the table is.
    private static func layout(of browser: Browser, in library: any ItemLibrary, order: ItemOrder?) -> ViewDraft.Layout {
        switch browser.viewMode {
        case .table:
            return .table
        case .list, .gallery:
            // The sort and group the person set, or the view's, are what the list and the gallery show.
            guard let order, browser.listShape?.arranged != true else { return .table }
            return .list(order)
        case .board:
            return .board
        case .calendar:
            return .calendar
        case .timeline:
            let fields = browser.timelineFieldChoices(in: library)
            let key = ItemTimelineLayout.selectedField(browser.timelineFields[browser.item], fields: fields)
            return .timeline(key: key, label: fields.first { $0.key == key }?.label ?? "")
        }
    }

    /// This Mac's settings for a view made of what the window shows: its layout, the columns it shows, its cards and its density.
    static func newViewSettings(_ browser: Browser, in library: any ItemLibrary) -> ViewMacSettings {
        var settings = ViewMacSettings(layout: browser.viewMode)
        settings.cards = browser.cards
        settings.density = browser.density
        if browser.viewMode == .calendar { settings.calendarScale = browser.calendarScale }
        settings.hidesEmptyGroups = browser.hidesEmptyGroups
        if case .view(let id) = browser.item {
            let held = browser.macSettings(for: id)
            settings.columns = held.columns
            settings.calendarScale = held.calendarScale
        } else {
            let stored = browser.defaults.data(forKey: ItemTableColumnLayouts.key) ?? Data()
            let layout = ItemTableColumnLayouts.layout(for: browser.item, in: stored)
            for column in browser.tableContent(in: library).columns where column.content != .title {
                settings.columns.setShown(column, layout.shows(column))
            }
        }
        return settings
    }

    /// Whether a place that is not a view shows something a view could keep, which Save as View offers to.
    static func hasChoicesToKeep(_ browser: Browser, in library: any ItemLibrary) -> Bool {
        shown(browser, in: library) == nil && canEdit(browser, in: library)
            && (browser.tableOptions[browser.item]?.isFiltering == true || browser.listShape?.arranged == true)
    }

    // MARK: What the layout uses

    /// The order the layout beside the panel really uses, which the panel shows and the window's choices become a
    /// view's from. The list and the gallery take the starting order Settings > Lists gives (`ItemOrder`) unless the
    /// person or the view arranged them; the table, the board and the timeline use the place's own sort. How each
    /// groups is `Browser.shownGrouping`.
    struct Arrangement {
        var sort: [ItemTableComparator]
        /// Whether the starting order shows its sections by date.
        var hasDateSections = false
        /// Whether the list's own date order applies, so a choice made here arranges the list.
        var isDated: Bool
    }

    /// Whether the table's sort and grouping order the layout: always, except in a list or gallery that is neither
    /// sorted nor grouped by a column.
    static func isArranged(_ browser: Browser) -> Bool {
        guard browser.viewMode == .list || browser.viewMode == .gallery else { return true }
        return browser.listShape?.arranged == true
    }

    static func arrangement(_ browser: Browser, content: ItemTableContent, order: ItemOrder) -> Arrangement {
        guard !isArranged(browser) else {
            // The board sorts its cards by title where nothing sorts them, which is what it then shows and keeps.
            if browser.viewMode == .board, browser.tableOptions[browser.item]?.sort?.isEmpty != false {
                return Arrangement(sort: [ItemTableComparator(column: .title)], isDated: false)
            }
            return Arrangement(sort: content.sort, isDated: false)
        }
        return datedArrangement(order)
    }

    /// What the list shows while nothing arranges it: its own order, in sections by date where it has them.
    static func datedArrangement(_ order: ItemOrder) -> Arrangement {
        let column: ItemTableColumn = switch order.sort {
        case .dateEdited: .edited
        case .dateCreated: .created
        case .title: .title
        }
        let sort = ItemTableComparator(column: column, order: order.sort == .title ? .forward : .reverse)
        return Arrangement(sort: [sort], hasDateSections: order.groupsByDate && order.sort != .title, isDated: true)
    }

    static func describe(_ unkept: ViewDraft.Unkept) -> String {
        switch unkept {
        case .search(let text): String(localized: "The search for “\(text)”")
        case .filter(let column): String(localized: "The filter on \(column)")
        case .mixedFilters: String(localized: "Filters that would join conditions with both “and” and “or”")
        case .tooManyFilters: String(localized: "More than \(ViewDraft.maxConditions) filter conditions")
        case .refused(let message): String(localized: "A filter Marfa refuses: \(message)")
        case .relativeFilter(let sentence): sentence
        case .sort(let column): String(localized: "Sorting by \(column)")
        case .group(let column): String(localized: "Grouping by \(column)")
        case .groupMode(let column, let mode): String(localized: "Group by \(column): \(mode)")
        }
    }
}


extension Text {
    /// A window subtitle that says the view it counts has changes nothing has saved.
    func editedSubtitle(_ isEdited: Bool) -> Text {
        isEdited ? Text("\(self), edited") : self
    }
}
