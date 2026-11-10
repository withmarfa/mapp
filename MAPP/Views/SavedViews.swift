import SwiftUI

/// What the window shows as a view would hold, and what a view's panel and commands read of the window. Making,
/// duplicating and deleting a view need the server, so they are offered only while the library can reach it
/// (`ItemLibrary.reachesServer`); editing one in the panel is not, nor is a change of its layout, columns or cards.
enum SavedViews {
    /// Whether the window's place can be saved as a view: Recents, Recently Deleted, the indexes, a single favorite
    /// and a collection cannot.
    static func canSave(_ browser: Browser, in library: any ItemLibrary) -> Bool {
        library.isLoaded && library.reachesServer && !browser.showsSettings && !browser.showsSidebarIndex
            && ViewDraft.query(for: browser.item, catalogue: library.catalogue, views: library.views) != nil
    }

    /// Whether Edit View has a panel for the window's place: a saved view, or a place that could become one.
    static func canEdit(_ browser: Browser, in library: any ItemLibrary) -> Bool {
        library.isLoaded && !browser.showsSettings && !browser.showsSidebarIndex
            && (shown(browser, in: library) != nil
                || ViewDraft.query(for: browser.item, catalogue: library.catalogue, views: library.views) != nil)
    }

    /// The view the window shows, while the library holds it.
    static func shown(_ browser: Browser, in library: any ItemLibrary) -> LibraryView? {
        guard !browser.showsSettings, case .view(let id) = browser.item else { return nil }
        return library.views.first { $0.id == id }
    }

    /// What the window shows, as the table works it out. Every layout applies the place's filters.
    static func window(_ browser: Browser, in library: any ItemLibrary) -> ViewDraft.Window {
        let content = browser.tableContent(in: library)
        let options = browser.tableOptions[browser.item] ?? ItemTableOptions()
        let search = browser.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        // The order and grouping come from what the layout shows (`arrangement`), which is what the panel shows too.
        let layoutShows = arrangement(browser, content: content, order: browser.storedOrder)
        var grouping: ItemTableColumn?
        if case .column(let id) = layoutShows.grouping, content.grouping?.id == id { grouping = content.grouping }
        var seededTypes: [String]?
        if case .view(let id) = browser.item { seededTypes = browser.viewSeeds[id]?.types }
        return ViewDraft.Window(
            place: browser.item, columns: content.columns, sort: layoutShows.sort, grouping: grouping,
            filters: options.filters, negated: options.negated, search: search.isEmpty ? nil : search,
            layout: layout(of: browser, in: library, order: nil), timelineDate: browser.timelineFields[browser.item],
            seededTypes: seededTypes, dated: layoutShows.isDated ? ViewDraft.Dated(sort: layoutShows.sort, hasSections: layoutShows.grouping == .date) : nil)
    }

    /// What the window shows in the layout it shows it in, with that layout's own order and grouping, so a new
    /// view keeps what the person sees.
    static func window(_ browser: Browser, in library: any ItemLibrary, order: NoteOrder) -> ViewDraft.Window {
        var window = window(browser, in: library)
        window.layout = layout(of: browser, in: library, order: order)
        return window
    }

    /// The layout the window shows. Without the list's order, which only a new view takes, a list or a gallery is
    /// read as the table is.
    private static func layout(of browser: Browser, in library: any ItemLibrary, order: NoteOrder?) -> ViewDraft.Layout {
        switch browser.viewMode {
        case .table:
            return .table
        case .list, .gallery:
            // The sort and group the person set, or the view's, are what the list and the gallery show.
            guard let order, browser.listShape?.arranged != true else { return .table }
            return .list(order)
        case .board:
            let fields = browser.boardFieldChoices(in: library)
            let field = ItemBoardLayout.selectedField(browser.boardFieldKey(in: browser.item), available: fields)
            return .board(key: field?.key, label: field?.label ?? "")
        case .timeline:
            let fields = browser.timelineFieldChoices(in: library)
            let key = ItemTimelineLayout.selectedField(browser.timelineFields[browser.item], fields: fields)
            return .timeline(key: key, label: fields.first { $0.key == key }?.label ?? "")
        }
    }

    /// This Mac's settings for a view made of what the window shows: its layout, the columns it shows and its cards.
    static func newViewSettings(_ browser: Browser, in library: any ItemLibrary) -> ViewMacSettings {
        var settings = ViewMacSettings(layout: browser.viewMode)
        settings.cards = browser.cards
        settings.rows = browser.rows
        if case .view(let id) = browser.item {
            let held = browser.macSettings(for: id)
            settings.columns = held.columns
            settings.hidesEmptyGroups = held.hidesEmptyGroups
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

    /// How the layout beside the panel groups: by a column, by date, or not at all.
    enum ShownGrouping: Hashable {
        case none
        case date
        case column(String)
    }

    /// The order and grouping the layout beside the panel really uses, which the panel shows and the window's
    /// choices become a view's from. The list and the gallery order and group by date (`NoteOrder`) unless the
    /// person or the view arranged them; the table, the board and the timeline use the table's own sort and grouping.
    struct Arrangement {
        var sort: [ItemTableComparator]
        var grouping: ShownGrouping
        /// Whether the list's own date order applies, so a choice made here arranges the list.
        var isDated: Bool
    }

    /// Whether the table's sort and grouping order the layout: always, except in a list or gallery that is neither
    /// sorted nor grouped by a column.
    static func isArranged(_ browser: Browser) -> Bool {
        guard browser.viewMode == .list || browser.viewMode == .gallery else { return true }
        return browser.listShape?.arranged == true
    }

    static func arrangement(_ browser: Browser, content: ItemTableContent, order: NoteOrder) -> Arrangement {
        guard !isArranged(browser) else {
            var grouping: ShownGrouping = content.grouping.map { .column($0.id) } ?? .none
            // The table groups by status on its own; an arranged list or gallery groups only by a column asked for.
            if browser.viewMode == .list || browser.viewMode == .gallery {
                if case .column(let id) = browser.tableOptions[browser.item]?.grouping { grouping = .column(id) } else { grouping = .none }
            }
            return Arrangement(sort: content.sort, grouping: grouping, isDated: false)
        }
        return datedArrangement(order)
    }

    /// What the list shows while nothing arranges it: its own order, in sections by date where it has them.
    static func datedArrangement(_ order: NoteOrder) -> Arrangement {
        let column: ItemTableColumn = switch order.sort {
        case .dateEdited: .edited
        case .dateCreated: .created
        case .title: .title
        }
        let sort = ItemTableComparator(column: column, order: order.sort == .title ? .forward : .reverse)
        return Arrangement(sort: [sort], grouping: order.groupsByDate && order.sort != .title ? .date : .none, isDated: true)
    }

    static func describe(_ unkept: ViewDraft.Unkept) -> String {
        switch unkept {
        case .search(let text): String(localized: "The search for “\(text)”")
        case .filter(let column): String(localized: "The filter on \(column)")
        case .mixedFilters: String(localized: "Filters that would join conditions with both “and” and “or”")
        case .tooManyFilters: String(localized: "More than \(ViewDraft.maxConditions) filter conditions")
        case .refused(let message): String(localized: "A filter Marfa refuses: \(message)")
        case .sort(let column): String(localized: "Sorting by \(column)")
        case .group(let column): String(localized: "Grouping by \(column)")
        case .dateSections: String(localized: "The list’s sections by date")
        }
    }
}


extension Text {
    /// A window subtitle that says the view it counts has changes nothing has saved.
    func editedSubtitle(_ isEdited: Bool) -> Text {
        isEdited ? Text("\(self), edited") : self
    }
}
