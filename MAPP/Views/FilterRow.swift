import SwiftUI

/// The filters of the open place as the row above its list shows them: a chip for each filtered column, a locked chip for
/// each condition a saved view holds that the window has no filter for, and the +. It works the place's table out only
/// while it shows, so a place nobody filtered never builds one for a layout that does not need it.
struct FilterRow: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    @State private var anchors = FilterChipAnchors()
    /// The column whose panel is open, which keeps its chip in the row while it has no value yet.
    @State private var openColumn: String?

    var body: some View {
        if browser.showsFilterRow {
            let content = browser.tableContent(in: library)
            let options = browser.tableOptions[browser.item] ?? ItemTableOptions()
            FilterChipsBar(
                chips: chips(content: content, options: options),
                leadingInset: browser.viewMode == .table ? ItemTable.leadingEdge : 12,
                anchors: anchors,
                open: { openValues(of: $0) },
                remove: { remove($0) },
                add: { openFields() }
            )
            .onChange(of: browser.isAddFilterRequested, initial: true) {
                guard browser.isAddFilterRequested else { return }
                browser.isAddFilterRequested = false
                // The row is laid out first, so the + has a view to open under.
                DispatchQueue.main.async { openFields() }
            }
            .onChange(of: browser.item) { FilterPanelPresenter.shared.dismiss(restoringFocus: false) }
        }
    }

    // MARK: Chips

    private func chips(content: ItemTableContent, options: ItemTableOptions) -> [FilterChipItem] {
        var items: [FilterChipItem] = content.columns.compactMap { column in
            let isOpen = openColumn == column.id
            guard options.filters[column.id]?.isEmpty == false || isOpen else { return nil }
            let kept = options.filters[column.id] ?? []
            let titles = ItemTableLayout.offered(in: content.allRows, by: column, keeping: kept).filter { kept.contains($0.id) }.map(\.title)
            return FilterChipItem(
                id: column.id, field: name(of: column),
                relation: options.isNegated(column.id) ? String(localized: "is not") : String(localized: "is"),
                values: titles.joined(separator: ", "))
        }
        items += lockedChips()
        return items
    }

    /// What a saved view's query holds that this row cannot change. It is kept whenever the view is written.
    private func lockedChips() -> [FilterChipItem] {
        guard case .view(let id) = browser.item, let view = library.views.first(where: { $0.id == id }) else { return [] }
        return ViewDraft.unshownConditions(of: view.query, catalogue: library.catalogue).enumerated().map { index, text in
            FilterChipItem(
                id: "locked.\(index)", field: text, relation: "", values: "", isLocked: true,
                lockedReason: String(localized: "This view's filter holds a condition that cannot be changed here. It is kept."))
        }
    }

    private func name(of column: ItemTableColumn) -> String {
        column.label.isEmpty ? String(localized: "Parent") : column.label
    }

    private func remove(_ id: String) {
        if openColumn == id { FilterPanelPresenter.shared.dismiss(restoringFocus: false) }
        browser.removeFilter(id)
    }

    // MARK: Panels

    private func openValues(of id: String) {
        openColumn = id
        FilterPanelPresenter.shared.present(
            key: id, anchor: anchors.view(for: id), width: 280,
            onClose: { openColumn = nil }
        ) {
            FilterValuePanelHost(browser: browser, columnID: id)
                .environment(\.library, library)
        }
        // The click that closed this panel asked to open it again: it stays closed.
        if !FilterPanelPresenter.shared.isOpen(for: id) { openColumn = nil }
    }

    /// Opens a column's panel once its chip has a view in the window to open under, which the row makes on a later turn of
    /// the run loop: the view exists before it has a window, and a panel asked for then does not open.
    private func openValuesWhenShown(_ id: String, attempts: Int = 20) {
        if anchors.view(for: id)?.window != nil || attempts == 0 {
            openValues(of: id)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) { openValuesWhenShown(id, attempts: attempts - 1) }
    }

    private func openFields() {
        let content = browser.tableContent(in: library)
        let fields = content.categoricalColumns.filter(ViewDraft.canFilter).map {
            FilterFieldOption(id: $0.id, title: name(of: $0), symbol: Self.symbol(of: $0, library: library))
        }
        FilterPanelPresenter.shared.present(key: FilterChipAnchors.addKey, anchor: anchors.view(for: FilterChipAnchors.addKey), width: 240, onClose: {}) {
            FilterFieldPanel(fields: fields) { id in
                FilterPanelPresenter.shared.dismiss(restoringFocus: false)
                // The new chip is in the row, and has a view, before its panel opens under it.
                openColumn = id
                openValuesWhenShown(id)
            }
        }
    }

    static func symbol(of column: ItemTableColumn, library: any ItemLibrary) -> String {
        switch column.content {
        case .type: "square.grid.2x2"
        case .parent: "link"
        case .field(let field): PageLayout.symbol(of: field)
        default: "line.3.horizontal.decrease"
        }
    }
}

/// A value panel's content, read from the window as it is now, so a pick shows in it at once.
private struct FilterValuePanelHost: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    let columnID: String

    var body: some View {
        let content = browser.tableContent(in: library)
        if let column = content.columns.first(where: { $0.id == columnID }) {
            let options = browser.tableOptions[browser.item] ?? ItemTableOptions()
            let kept = options.filters[columnID] ?? []
            let offered = ItemTableLayout.offered(in: content.allRows, by: column, keeping: kept)
            FilterValuePanel(
                field: column.label.isEmpty ? String(localized: "Parent") : column.label,
                isNegated: options.isNegated(columnID),
                chosen: offered.filter { kept.contains($0.id) }.map { ValueChip(id: $0.id, title: $0.title, mark: mark(of: $0, in: column)) },
                options: offered.filter { !kept.contains($0.id) }.map {
                    FilterValueOption(id: $0.id, title: $0.title, mark: mark(of: $0, in: column))
                },
                setNegated: { browser.setFilter(columnID, values: kept, negated: $0) },
                add: { browser.setFilter(columnID, values: kept.union([$0]), negated: options.negated.contains(columnID)) },
                remove: { browser.setFilter(columnID, values: kept.subtracting([$0])) }
            )
        }
    }

    private func mark(of group: ItemTableGroup, in column: ItemTableColumn) -> ValueListRow.Mark {
        switch column.style {
        case .status: .status(group.value.flatMap { column.field?.statusGroup(of: $0) })
        case .priority, .choice:
            if let value = group.value, let field = column.field {
                .dot(OptionTone.tone(of: value, in: field, isPriority: library.catalogue.isPriority(field, of: field.declaredBy)))
            } else if let value = group.value {
                .dot(OptionTone.tone(for: ItemTypeInfo.Field.label(ofOption: value)))
            } else {
                .none
            }
        default:
            if column.content == .type, let value = group.value { .type(icon: library.catalogue.icon(for: TypeID(value))) } else { .none }
        }
    }
}

/// The answer to filters that hide every item, in the layouts that have no empty state of their own for it.
struct FilteredEmptyState: View {
    @CurrentLibrary private var library
    let browser: Browser

    var body: some View {
        if browser.filtersHideEverything(in: library) {
            EmptyState(title: Text("No Matching Items"), detail: Text("No items match the filters.")) {
                Button("Clear Filters") { browser.clearFilters() }
            }
            .background(.background)
            .accessibilityIdentifier("FilteredEmptyState")
        }
    }
}

extension View {
    /// The place's filter row above the content, while the window shows it.
    func filterChips(_ browser: Browser) -> some View {
        safeAreaBar(edge: .top, spacing: 0) {
            FilterRow(browser: browser)
        }
    }

    /// Says so, with Clear Filters, where the place's filters hide every item.
    func filteredEmptyState(_ browser: Browser) -> some View {
        overlay { FilteredEmptyState(browser: browser) }
    }
}
