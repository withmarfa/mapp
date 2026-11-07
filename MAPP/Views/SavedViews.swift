import SwiftUI

/// What the window shows as a view would hold, and what a view's panel and commands read of the window. Making,
/// duplicating and deleting a view need the server, so they are offered only while the library can reach it
/// (`ItemLibrary.reachesServer`); editing one in the panel is not, nor is saving a change of its layout, columns or cards.
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
        // The table's own grouping by status is not one the list or the gallery shows.
        var grouping = content.grouping
        if (browser.viewMode == .list || browser.viewMode == .gallery), case .automatic = options.grouping { grouping = nil }
        var seededTypes: [String]?
        if case .view(let id) = browser.item { seededTypes = browser.viewSeeds[id]?.types }
        return ViewDraft.Window(
            place: browser.item, columns: content.columns, sort: content.sort, grouping: grouping,
            filters: options.filters, negated: options.negated, search: search.isEmpty ? nil : search,
            layout: layout(of: browser, in: library, order: nil), timelineDate: browser.timelineFields[browser.item],
            seededTypes: seededTypes)
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

    /// What the panel's Save would keep of the window, in the layout the window shows it.
    static func panelWindow(_ browser: Browser, in library: any ItemLibrary, order: NoteOrder) -> ViewDraft.Window {
        browser.viewPanel?.isNew == true ? window(browser, in: library, order: order) : window(browser, in: library)
    }

    /// Saves what the panel holds. With no panel open the save goes through a quiet one, which shows only if it has to
    /// ask the person something or say why the save failed.
    static func save(_ browser: Browser, in library: any ItemLibrary, order: NoteOrder, confirmed: Bool = false) {
        if browser.viewPanel == nil {
            browser.openViewPanel(in: library)
            browser.viewPanel?.isQuiet = true
        }
        guard browser.viewPanel != nil else { return }
        let window = panelWindow(browser, in: library, order: order)
        let settings = newViewSettings(browser, in: library)
        Task {
            await browser.saveViewPanel(window: window, newView: settings, confirmed: confirmed, in: library, order: order)
            if browser.viewPanel?.isQuiet == true { browser.closeViewPanel(in: library) }
        }
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
