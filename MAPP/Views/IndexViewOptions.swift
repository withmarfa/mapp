import SwiftUI

/// What an index page can be set to: the column its table is ordered by and the direction. The toolbar's View Options
/// menu and the View menu offer the same choices.
struct IndexViewOptions: View {
    let place: IndexPlace
    @AppStorage private var sort: IndexSort

    init(place: IndexPlace) {
        self.place = place
        _sort = AppStorage(wrappedValue: place.defaultSort, place.sortKey)
    }

    var body: some View {
        Group {
            Section("Sort By") {
                ForEach(IndexColumn.allCases, id: \.self) { column in
                    Toggle(column.title(in: place), isOn: Binding { sort.column == column } set: { _ in sort.column = column })
                        .accessibilityIdentifier("IndexSortBy\(column.rawValue.capitalized)")
                }
            }
            Section("Order") {
                Toggle("Ascending", isOn: Binding { sort.ascending } set: { _ in sort.ascending = true })
                    .accessibilityIdentifier("IndexSortAscending")
                Toggle("Descending", isOn: Binding { !sort.ascending } set: { _ in sort.ascending = false })
                    .accessibilityIdentifier("IndexSortDescending")
            }
        }
    }
}

/// The toolbar's one menu of an index page's options, where the other pages keep View Options.
struct IndexViewOptionsMenu: View {
    let place: IndexPlace

    var body: some View {
        Menu("View Options", systemImage: "slider.horizontal.3") {
            IndexViewOptions(place: place)
        }
        .menuIndicator(.hidden)
        .help("View Options")
        .accessibilityIdentifier("ViewOptionsToolbar")
    }
}

extension ViewOptionCommand {
    /// The index page's sorts not already chosen, for the command palette.
    static func indexCommands(for place: IndexPlace) -> [ViewOptionCommand] {
        let current = IndexPreferences.sort(for: place)
        return IndexColumn.allCases.filter { $0 != current.column }.map { column in
            ViewOptionCommand(title: String(localized: "Sort by \(column.plainTitle(in: place))"), systemImage: "arrow.up.arrow.down") {
                IndexPreferences.set(IndexSort(column: column, ascending: current.ascending), for: place)
            }
        }
    }
}

private extension IndexColumn {
    /// The column's name as a plain string, for a command's title.
    func plainTitle(in place: IndexPlace) -> String {
        switch self {
        case .name: place == .sources ? String(localized: "Source") : String(localized: "Name")
        case .types: place == .sources ? String(localized: "Writes") : String(localized: "Contains")
        case .count: String(localized: "Items")
        case .latest: String(localized: "Latest Item")
        }
    }
}
