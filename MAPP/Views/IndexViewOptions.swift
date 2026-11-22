import SwiftUI

/// What an index page can be set to: the column its table is ordered by and the direction. The toolbar's View Options
/// menu and the View menu offer the same choices.
struct IndexViewOptions: View {
    let place: IndexPlace
    /// The window, whose search on Items lists its results by relevance until a column is chosen.
    let browser: Browser?
    @AppStorage private var sort: IndexSort

    init(place: IndexPlace, browser: Browser? = nil) {
        self.place = place
        self.browser = browser
        _sort = AppStorage(wrappedValue: place.defaultSort, place.sortKey)
    }

    /// Whether the table is in the library's relevance order, which no column's arrow shows.
    private var byRelevance: Bool { place == .items && browser?.ordersByRelevance == true }

    var body: some View {
        Group {
            Section("Sort By") {
                if place == .items, browser?.isSearching == true {
                    Toggle("Relevance", isOn: Binding { byRelevance } set: { _ in browser?.orderSearch(byRelevance: true) })
                        .accessibilityIdentifier("IndexSortByRelevance")
                }
                ForEach(place.columns, id: \.self) { column in
                    Toggle(column.title(in: place), isOn: Binding { sort.column == column && !byRelevance } set: { _ in
                        sort.column = column
                        if place == .items { browser?.orderSearch(byRelevance: false) }
                    })
                    .accessibilityIdentifier("IndexSortBy\(column.rawValue.capitalized)")
                }
            }
            Section("Order") {
                Toggle("Ascending", isOn: Binding { sort.ascending } set: { _ in sort.ascending = true })
                    .accessibilityIdentifier("IndexSortAscending")
                    .disabled(byRelevance)
                Toggle("Descending", isOn: Binding { !sort.ascending } set: { _ in sort.ascending = false })
                    .accessibilityIdentifier("IndexSortDescending")
                    .disabled(byRelevance)
            }
        }
    }
}

/// The toolbar's one menu of an index page's options, where the other pages keep View Options.
struct IndexViewOptionsMenu: View {
    let place: IndexPlace
    let browser: Browser

    var body: some View {
        Menu("View Options", systemImage: "slider.horizontal.3") {
            IndexViewOptions(place: place, browser: browser)
        }
        .menuIndicator(.hidden)
        .help("View Options")
        .accessibilityIdentifier("ViewOptionsToolbar")
    }
}

extension ViewOptionCommand {
    /// The index page's sorts not already chosen, for the command palette. Items' search starts on relevance, which
    /// stands until a column is chosen and comes back by Sort by Relevance.
    static func indexCommands(for place: IndexPlace, browser: Browser) -> [ViewOptionCommand] {
        let current = IndexPreferences.sort(for: place, in: browser.defaults)
        let byRelevance = place == .items && browser.ordersByRelevance
        var commands: [ViewOptionCommand] = []
        if place == .items, browser.isSearching, !byRelevance {
            commands.append(ViewOptionCommand(title: String(localized: "Sort by Relevance"), systemImage: "arrow.up.arrow.down", group: .sortAndGroup) {
                browser.orderSearch(byRelevance: true)
            })
        }
        for column in place.columns where column != current.column || byRelevance {
            commands.append(ViewOptionCommand(
                title: String(localized: "Sort by \(column.plainTitle(in: place))"), systemImage: "arrow.up.arrow.down", group: .sortAndGroup
            ) {
                IndexPreferences.set(IndexSort(column: column, ascending: current.ascending), for: place, in: browser.defaults)
                if place == .items { browser.orderSearch(byRelevance: false) }
            })
        }
        if browser.indexPlaceHasTools {
            commands.append(ViewOptionCommand(
                title: String(localized: browser.toggleFiltersTitle), systemImage: "line.3.horizontal.decrease", key: .toggleFilters
            ) {
                browser.toggleIndexFilter()
            })
            if browser.indexIsFiltered {
                commands.append(ViewOptionCommand(title: String(localized: "Clear Filters"), systemImage: "line.3.horizontal.decrease") {
                    browser.clearIndexFilters()
                })
            }
        }
        if place == .items {
            commands.append(ViewOptionCommand(title: String(localized: "Edit New Row…"), systemImage: "square.grid.2x2") {
                browser.isEditingNewRow = true
            })
        }
        return commands
    }
}

private extension IndexColumn {
    /// The column's name as a plain string, for a command's title.
    func plainTitle(in place: IndexPlace) -> String {
        switch self {
        case .name: place == .sources ? String(localized: "Source") : String(localized: "Name")
        case .types: place == .items ? String(localized: "Type") : String(localized: "Writes")
        case .source: String(localized: "Source")
        case .count: String(localized: "Items")
        case .latest: place == .sources ? String(localized: "Latest") : String(localized: "Updated")
        }
    }
}
