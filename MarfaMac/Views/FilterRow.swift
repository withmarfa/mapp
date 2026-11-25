import SwiftUI

/// The Items page's filters, as the row under its tabs shows them: a chip for each clause and the +. A list's place
/// changes its filters in the View panel instead (`ViewPanelFilter`). Once the row holds two filters a pop-up leads
/// it (All or Any); a date relative to today is named at its trailing end, and what a view cannot keep under the chips. It
/// works the place's table out only while it shows, so a place nobody filtered never builds one for a layout that does not
/// need it.
struct FilterRow: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    /// Where the chips start, where the place's own layout does not say.
    var leadingInset: CGFloat?
    @State private var anchors = FilterChipAnchors()
    /// The clause whose panel is open, which keeps its chip in the row while it has no value yet.
    @State private var openIndex: Int?

    private static let chipPrefix = "clause."

    var body: some View {
        if browser.showsIndexFilterRow {
            let content = browser.tableContent(in: library)
            let state = (browser.tableOptions[browser.shown] ?? ItemTableOptions()).filter
            let offer = content.filterOffer
            let held = holdingNote(of: state, offer: offer)
            FilterChipsBar(
                chips: chips(of: state, content: content),
                leadingInset: leadingInset ?? (browser.viewMode == .table ? ItemTable.leadingEdge : 12),
                matchPicker: state.clauses.count >= 2
                    ? FilterMatchPicker(isAny: state.matchesAny, choose: { browser.setFiltersMatchAny($0) }) : nil,
                trailingNote: relativeNote(of: state, offer: offer),
                note: held,
                anchors: anchors,
                open: { openValues(of: $0) },
                remove: { remove($0) },
                add: { openFields() }
            )
            .onChange(of: browser.shown.memoryKey) { FilterPanelPresenter.shared.dismiss(restoringFocus: false) }
        }
    }

    // MARK: Chips

    private func chips(of state: FilterState, content: ItemTableContent) -> [FilterChipItem] {
        let targets = content.filterOffer.targets
        // Only a parent, a collection or a type is held by an identifier that needs naming.
        let needsTitles = state.clauses.contains { [FilterTarget.parent.id, FilterTarget.collection.id, FilterTarget.type.id].contains($0.field) }
        let titles = needsTitles ? FilterTitles(content: content) : nil
        var items: [FilterChipItem] = []
        for (index, clause) in state.clauses.enumerated() {
            guard clause.isComplete || openIndex == index else { continue }
            let id = Self.chipPrefix + "\(index)"
            guard let target = targets[clause.field] else {
                // A field no type of the place declares any more: shown so it can be taken off.
                let name = clause.field.hasPrefix(Browser.fieldColumnPrefix) ? String(clause.field.dropFirst(Browser.fieldColumnPrefix.count)) : clause.field
                items.append(FilterChipItem(id: id, field: name, relation: "", values: clause.values.joined(separator: ", ")))
                continue
            }
            let parts = FilterWording.parts(of: clause, target: target, calendar: .current, titles: { titles?.title(of: $0) })
            items.append(FilterChipItem(id: id, field: parts.field, relation: parts.relation, values: parts.values, needsValue: clause.op.takesValue))
        }
        items += lockedChips()
        return items
    }

    /// What a saved view's query holds that this row cannot change. It is kept whenever the view is written.
    private func lockedChips() -> [FilterChipItem] {
        guard let id = browser.shown.savedView, let view = library.views.first(where: { $0.id == id }) else { return [] }
        return ViewDraft.unshownConditions(of: view.query, catalogue: library.catalogue).enumerated().map { index, text in
            FilterChipItem(
                id: "locked.\(index)", field: text, relation: "", values: "", needsValue: false, isLocked: true,
                lockedReason: String(localized: "This view's filter holds a condition that cannot be changed here. It is kept."))
        }
    }

    /// The row's trailing words where a filter is relative to the day: a saved view cannot keep it.
    private func relativeNote(of state: FilterState, offer: FilterOffer) -> String? {
        let phrases = state.relative.filter { offer.targets[$0.field] != nil }
            .map { FilterWording.relativePhrase(of: $0, calendar: .current) }
        guard !phrases.isEmpty else { return nil }
        let quoted = phrases.map { "“\($0)”" }.joined(separator: ", ")
        return String(localized: "A saved view can’t keep \(quoted)")
    }

    /// What the filters cannot be saved as, said before the person tries: a place that could be a view only.
    private func holdingNote(of state: FilterState, offer: FilterOffer) -> String? {
        guard ViewDraft.query(for: browser.shown, catalogue: library.catalogue, views: library.views) != nil else { return nil }
        let held = ViewDraft.holdability(of: state, targets: offer.targets, catalogue: library.catalogue)
        for unkept in held.unkept {
            switch unkept {
            case .mixedFilters:
                return String(localized: "A view can save only filters that all apply, or all of which any one may apply.")
            case .tooManyFilters:
                return String(localized: "A view keeps up to \(ViewDraft.maxConditions) conditions; this one has \(held.count).")
            case .filter(let column):
                return String(localized: "A view can’t keep the filter on \(column).")
            default:
                continue
            }
        }
        return nil
    }

    private func remove(_ id: String) {
        guard let index = clauseIndex(of: id) else { return }
        FilterPanelPresenter.shared.dismiss(restoringFocus: false)
        browser.removeFilter(at: index)
    }

    private func clauseIndex(of id: String) -> Int? {
        id.hasPrefix(Self.chipPrefix) ? Int(id.dropFirst(Self.chipPrefix.count)) : nil
    }

    // MARK: Panels

    private func openValues(of id: String) {
        guard let index = clauseIndex(of: id) else { return }
        // Closing the panel open drops a filter left without a value, which moves the ones after it.
        let state = (browser.tableOptions[browser.shown] ?? ItemTableOptions()).filter
        guard state.clauses.indices.contains(index) else { return }
        let clause = state.clauses[index]
        if FilterPanelPresenter.shared.isOpen, !FilterPanelPresenter.shared.isOpen(for: id) {
            FilterPanelPresenter.shared.dismiss(restoringFocus: false)
        }
        let now = (browser.tableOptions[browser.shown] ?? ItemTableOptions()).filter.clauses
        let at = now.indices.contains(index) && now[index] == clause ? index : (now.firstIndex(of: clause) ?? index)
        let key = Self.chipPrefix + "\(at)"
        openIndex = at
        FilterPanelPresenter.shared.present(
            key: key, anchor: anchors.view(for: key), width: 280,
            onClose: {
                openIndex = nil
                browser.dropUnfinishedFilters()
            }
        ) {
            FilterConditionEditor(browser: browser, index: at)
                .environment(\.library, library)
        }
        // The click that closed this panel asked to open it again: it stays closed.
        if !FilterPanelPresenter.shared.isOpen(for: key) { openIndex = nil }
    }

    private func openFields() {
        let content = browser.tableContent(in: library)
        let offer = content.filterOffer
        let state = (browser.tableOptions[browser.shown] ?? ItemTableOptions()).filter
        func option(_ target: FilterTarget) -> FilterFieldOption {
            FilterFieldOption(id: target.id, title: target.label, symbol: target.symbol)
        }
        var sections: [FilterFieldSection] = []
        if !offer.placeFields.isEmpty {
            sections.append(FilterFieldSection(title: offer.placeTitle, fields: offer.placeFields.map(option)))
        }
        sections.append(FilterFieldSection(title: String(localized: "Every Item"), fields: offer.everyItem.map(option)))
        let held = ViewDraft.holdability(of: state, targets: offer.targets, catalogue: library.catalogue)
        let footer = held.count >= Self.footerFrom
            ? String(localized: "A view keeps up to \(ViewDraft.maxConditions) conditions; this one has \(held.count)") : nil
        FilterPanelPresenter.shared.present(key: FilterChipAnchors.addKey, anchor: anchors.view(for: FilterChipAnchors.addKey), width: 240, onClose: {}) {
            FilterFieldPanel(sections: sections, footer: footer) { id in
                guard let target = offer.targets[id] else { return }
                FilterPanelPresenter.shared.dismiss(restoringFocus: false)
                // The new chip is in the row, and has a view, before its panel opens under it.
                let index = browser.addFilter(on: target)
                openIndex = index
                let key = Self.chipPrefix + "\(index)"
                anchors.whenShown(key) { openValues(of: key) }
            }
        }
    }

    /// The count of conditions at which Filter By starts to say how many a view keeps.
    private static let footerFrom = 8
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
    /// Says so, with Clear Filters, where the place's filters hide every item.
    func filteredEmptyState(_ browser: Browser) -> some View {
        overlay { FilteredEmptyState(browser: browser) }
    }
}
