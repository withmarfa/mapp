import SwiftUI

// The View panel's parts that open one level in, each with a back arrow to the first page.

// MARK: Types

/// Types: the types the place lists, each with a tick, which narrow it to those ticked (the Type filter, which a saved
/// view keeps as its listed types), and Include Kinds for a type that has kinds.
struct ViewPanelTypes: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    @Bindable var panel: ViewPanel
    @State private var search = ""

    var body: some View {
        let content = browser.tableContent(in: library)
        let chosen = Set(Self.chosen(in: browser))
        let types = Self.types(content: content, catalogue: library.catalogue)
        let shown = search.isEmpty ? types : types.filter { $0.title.localizedStandardContains(search) }
        ViewPanelHead(title: String(localized: "Types"), back: { panel.page = .main })
        if content.filterOffer.targets[ViewDraft.typeFieldID] != nil {
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, ViewPanelMetrics.inset)
                .padding(.vertical, 4)
                .accessibilityIdentifier("ViewPanelTypesSearch")
            ForEach(shown, id: \.id) { type in
                Toggle(isOn: Binding { chosen.contains(type.id) } set: { set(type.id, chosen: $0) }) {
                    Label(type.title, typeIcon: type.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.checkbox)
                .interfaceFont(.body)
                .frame(minHeight: ViewPanelMetrics.rowHeight)
                .padding(.horizontal, ViewPanelMetrics.inset)
                .accessibilityIdentifier("ViewPanelType.\(type.id)")
            }
            if shown.isEmpty {
                Text("No Types")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, ViewPanelMetrics.inset)
                    .frame(minHeight: ViewPanelMetrics.rowHeight)
            }
        }
        if browser.kindsType(in: library) != nil {
            ViewPanelSection {
                ViewPanelSwitchRow(
                    symbol: IncludeKinds.symbol, label: String(localized: "Include Kinds"), isOn: browser.listing.includesKinds,
                    set: { browser.setIncludesKinds($0) })
                    .help(browser.listing.includesKinds ? Text("Show only this type’s own items") : Text("Include the items of its kinds in this list"))
                    .accessibilityIdentifier("IncludeKinds")
            }
        }
        ViewPanelFoot(text: ViewPanelKeeping.foot(of: panel))
    }

    /// Whether the place has a Types part: a choice of the types it lists, or its kinds to include.
    static func offersTypes(_ browser: Browser, content: ItemTableContent, library: any ItemLibrary) -> Bool {
        content.filterOffer.targets[ViewDraft.typeFieldID] != nil || browser.kindsType(in: library) != nil
    }

    /// The types the Type filter holds.
    static func chosen(in browser: Browser) -> [String] {
        let clauses = browser.tableOptions[browser.shown]?.filter.clauses ?? []
        return clauses.first(where: isTypesClause)?.values.filter { !$0.isEmpty } ?? []
    }

    /// The clause Types owns: the first Type filter that is one of some types.
    static func isTypesClause(_ clause: FilterClause) -> Bool {
        clause.field == ViewDraft.typeFieldID && clause.op == .is
    }

    static func typesClauseIndex(in browser: Browser) -> Int? {
        browser.tableOptions[browser.shown]?.filter.clauses.firstIndex(where: isTypesClause)
    }

    private struct TypeChoice {
        let id: String
        let title: String
        let icon: String?
    }

    /// The types the place lists and those its items have, by name.
    private static func types(content: ItemTableContent, catalogue: Catalogue) -> [TypeChoice] {
        let ids = Set(content.allRows.map(\.item.type)).union(content.filterOffer.typeIDs)
        return ids.map { id in
            TypeChoice(id: id.rawValue, title: catalogue.itemTypes[id]?.plural ?? id.rawValue, icon: catalogue.icon(for: id))
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func set(_ type: String, chosen isChosen: Bool) {
        let content = browser.tableContent(in: library)
        guard let target = content.filterOffer.targets[ViewDraft.typeFieldID] else { return }
        if let index = Self.typesClauseIndex(in: browser) {
            let clause = browser.tableOptions[browser.shown]!.filter.clauses[index]
            let next = isChosen ? clause.adding(type) : clause.removing(type)
            // The last type taken off leaves no filter, rather than one asking for a value.
            if next.values.filter({ !$0.isEmpty }).isEmpty { return browser.removeFilter(at: index) }
            browser.changeFilter(at: index) { $0 = next }
        } else if isChosen {
            browser.addFilter(on: target, values: [type])
        }
    }
}

// MARK: Filter

/// Filter: Match All or Any at the title, a row for each condition, and Add Condition, which lists the place's types'
/// properties first and then every item's. A saved view keeps at most `ViewDraft.maxConditions`, all joined one way, and
/// no condition relative to today, so the panel offers none; a condition the window already holds that a view cannot keep
/// stays, with a line that says why.
struct ViewPanelFilter: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    @Bindable var panel: ViewPanel
    /// The condition whose editor is open.
    @State private var editing: Int?

    var body: some View {
        let content = browser.tableContent(in: library)
        let offer = content.filterOffer
        let state = (browser.tableOptions[browser.shown] ?? ItemTableOptions()).filter
        let conditions = Self.conditions(in: browser)
        let titles = FilterTitles(content: content)
        let locked = lockedConditions()
        let saved = SavedViews.shown(browser, in: library)?.query
        // A saved view's own conditions the panel cannot show count too, since every write keeps them.
        let held = saved.map { ViewDraft.holdability(of: state, beside: $0, targets: offer.targets, catalogue: library.catalogue) }
            ?? ViewDraft.holdability(of: state, targets: offer.targets, catalogue: library.catalogue)
        let isView = ViewDraft.query(for: browser.shown, catalogue: library.catalogue, views: library.views) != nil
        let isFull = isView && held.count >= ViewDraft.maxConditions
        let offersAny = saved == nil || state.matchesAny
            || ViewDraft.canMatchAny(state, beside: saved, targets: offer.targets, catalogue: library.catalogue)
        ViewPanelHead(title: String(localized: "Filter"), back: { panel.page = .main }) {
            if state.clauses.count >= 2 {
                matchMenu(isAny: state.matchesAny, offersAny: offersAny, locked: !locked.isEmpty)
            }
        }
        ForEach(conditions.filter { !$0.clause.isRelative }, id: \.index) { condition in
            row(condition, offer: offer, titles: titles)
        }
        let relative = conditions.filter { $0.clause.isRelative }
        if !relative.isEmpty {
            ViewPanelSection(title: String(localized: "Relative to Today")) {
                ForEach(relative, id: \.index) { condition in
                    row(condition, offer: offer, titles: titles)
                }
            }
        }
        ForEach(Array(locked.enumerated()), id: \.offset) { _, text in
            ViewPanelRowLabel(symbol: "lock", label: text)
                .foregroundStyle(.secondary)
                .help("This view’s filter holds a condition that can’t be changed here. It is kept.")
                .accessibilityIdentifier("ViewPanelLockedCondition")
        }
        addCondition(offer: offer)
            .disabled(isFull)
        if let note = holdingNote(held: held, isView: isView, relative: relative.map(\.clause), offer: offer) {
            Text(verbatim: note)
                .interfaceFont(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, ViewPanelMetrics.inset)
                .padding(.vertical, 4)
                .accessibilityIdentifier("ViewPanelFilterNote")
        }
        ViewPanelFoot(text: ViewPanelKeeping.foot(of: panel))
    }

    /// The place's conditions that this page shows, each with its place among the window's: every one but the types
    /// Types holds.
    static func conditions(in browser: Browser) -> [(index: Int, clause: FilterClause)] {
        let clauses = browser.tableOptions[browser.shown]?.filter.clauses ?? []
        let types = ViewPanelTypes.typesClauseIndex(in: browser)
        return clauses.enumerated().filter { $0.offset != types }.map { ($0.offset, $0.element) }
    }

    /// Match All or Any. A saved view takes Match Any only where every condition is one test, and no condition of its
    /// own the panel cannot show stands beside them, so the menu says why it offers none.
    private func matchMenu(isAny: Bool, offersAny: Bool, locked: Bool) -> some View {
        Menu {
            Toggle("Match All", isOn: Binding { !isAny } set: { _ in browser.setFiltersMatchAny(false) })
            Toggle("Match Any", isOn: Binding { isAny } set: { _ in browser.setFiltersMatchAny(true) })
                .disabled(!offersAny)
            if !offersAny {
                Section {
                    Text(locked
                        ? "Match Any isn’t available because this view holds a condition that can’t be changed here."
                        : "Match Any isn’t available because a condition, such as a date range, needs all of its parts to apply.")
                }
            }
        } label: {
            Text(isAny ? "Match Any" : "Match All")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Whether an item must meet every condition, or any one of them")
        .accessibilityIdentifier("ViewPanelFilterMatch")
    }

    private func row(_ condition: (index: Int, clause: FilterClause), offer: FilterOffer, titles: FilterTitles) -> some View {
        let index = condition.index
        let clause = condition.clause
        let target = offer.targets[clause.field]
        let parts = target.map { FilterWording.parts(of: clause, target: $0, calendar: .current, titles: { titles.title(of: $0) }) }
        // A field no type of the place declares any more is shown so it can be taken off.
        let field = parts?.field ?? (clause.field.hasPrefix(Browser.fieldColumnPrefix)
            ? String(clause.field.dropFirst(Browser.fieldColumnPrefix.count)) : clause.field)
        let words = parts.map { [$0.relation, $0.values].filter { !$0.isEmpty }.joined(separator: " ") }
        return HStack(spacing: 0) {
            Button {
                if target != nil { editing = index }
            } label: {
                ViewPanelRowLabel(
                    symbol: target?.symbol ?? "line.3.horizontal.decrease", label: field,
                    value: clause.isComplete ? words : String(localized: "Choose…"))
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding { editing == index } set: { if !$0, editing == index { close() } }, arrowEdge: .trailing) {
                FilterConditionEditor(browser: browser, index: index, offersRelative: false)
                    .environment(\.library, library)
                    .frame(width: 280)
            }
            Button("Remove Condition", systemImage: "xmark.circle") {
                editing = nil
                browser.removeFilter(at: index)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .padding(.trailing, ViewPanelMetrics.inset)
            .help("Remove Condition")
            .accessibilityIdentifier("ViewPanelFilterRemove")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewPanelCondition.\(index)")
    }

    private func close() {
        editing = nil
        browser.dropUnfinishedFilters()
    }

    private func addCondition(offer: FilterOffer) -> some View {
        Menu {
            let place = offer.placeFields.filter { $0.id != ViewDraft.typeFieldID }
            if !place.isEmpty {
                Section(offer.placeTitle) {
                    ForEach(place, id: \.id) { target in option(target) }
                }
            }
            Section("Every Item") {
                ForEach(offer.everyItem.filter { $0.id != ViewDraft.typeFieldID }, id: \.id) { target in option(target) }
            }
        } label: {
            ViewPanelRowLabel(symbol: "plus", label: String(localized: "Add Condition"))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityIdentifier("ViewPanelAddCondition")
    }

    private func option(_ target: FilterTarget) -> some View {
        Button {
            editing = browser.addFilter(on: target)
        } label: {
            Label(target.label, systemImage: target.symbol)
        }
    }

    /// What a saved view's query holds that the panel cannot change. It is kept whenever the view is written.
    private func lockedConditions() -> [String] {
        guard let id = browser.shown.savedView, let view = library.views.first(where: { $0.id == id }) else { return [] }
        return ViewDraft.unshownConditions(of: view.query, catalogue: library.catalogue)
    }

    /// What the conditions cannot be saved as, said before the person tries, in a place that is a view or could be one.
    private func holdingNote(held: ViewDraft.Combination, isView: Bool, relative: [FilterClause], offer: FilterOffer) -> String? {
        guard isView else { return nil }
        for unkept in held.unkept {
            switch unkept {
            case .mixedFilters:
                return String(localized: "A view can save only conditions that all apply, or all of which any one may apply.")
            case .tooManyFilters:
                return String(localized: "A view keeps up to \(ViewDraft.maxConditions) conditions; this one has \(held.count).")
            case .filter(let column):
                return String(localized: "A view can’t keep the condition on \(column).")
            default:
                continue
            }
        }
        if held.count >= ViewDraft.maxConditions {
            return String(localized: "A view keeps up to \(ViewDraft.maxConditions) conditions.")
        }
        let phrases = relative.filter { offer.targets[$0.field] != nil }.map { FilterWording.relativePhrase(of: $0, calendar: .current) }
        guard !phrases.isEmpty else { return nil }
        let quoted = phrases.map { "“\($0)”" }.joined(separator: ", ")
        return String(localized: "A saved view can’t keep \(quoted).")
    }
}

// MARK: Sort

/// Sort: up to `ViewDraft.maxSortKeys` keys, each a property chosen with Add Sort and its direction in its own words
/// (Newest First for a date). A key is dragged to a new place, or moved with its menu, and the first sorts first. The
/// keys are those the layout uses (`SavedViews.arrangement`).
struct ViewPanelSort: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    @Bindable var browser: Browser
    @Bindable var panel: ViewPanel

    var body: some View {
        let content = browser.tableContent(in: library)
        let sort = SavedViews.arrangement(browser, content: content, order: order).sort
        let unused = content.sortChoices.filter { column in !sort.contains { $0.column.id == column.id } }
        ViewPanelHead(title: String(localized: "Sort"), back: { panel.page = .main })
        if browser.isSearching {
            ViewPanelSwitchRow(
                symbol: "magnifyingglass", label: String(localized: "Sort Search by Relevance"), isOn: browser.ordersByRelevance,
                set: { browser.orderSearch(byRelevance: $0) })
                .accessibilityIdentifier("ViewPanelSortRelevance")
        }
        ForEach(sort, id: \.column.id) { key in
            ViewPanelSortRow(browser: browser, key: key, sort: sort)
        }
        if sort.count < ViewDraft.maxSortKeys, !unused.isEmpty {
            Menu {
                ForEach(unused) { column in
                    Button(column.label) { browser.setSort(sort + [ItemTableComparator(column: column, order: column.firstOrder)]) }
                }
            } label: {
                ViewPanelRowLabel(symbol: "plus", label: String(localized: "Add Sort"))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityIdentifier("ViewPanelAddSort")
        }
        ViewPanelFoot(text: ViewPanelKeeping.foot(of: panel))
    }
}

private struct ViewPanelSortRow: View {
    let browser: Browser
    let key: ItemTableComparator
    let sort: [ItemTableComparator]

    private static let prefix = "sort:"

    var body: some View {
        HStack(spacing: 8) {
            ViewPanelGrabber()
            // The property is fixed once added, as a condition's is: Add Sort chooses it, and the row only turns it round.
            Text(verbatim: key.column.label)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("ViewPanelSortColumn")
            Picker("Direction", selection: Binding { key.order } set: { order in
                browser.setSort(sort.map { $0.column.id == key.column.id ? ItemTableComparator(column: key.column, order: order) : $0 })
            }) {
                Text(verbatim: key.column.ascendingTitle).tag(SortOrder.forward)
                Text(verbatim: key.column.descendingTitle).tag(SortOrder.reverse)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier("ViewPanelSortDirection")
            Button("Remove Sort", systemImage: "xmark.circle") { remove() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .disabled(sort.count <= 1)
                .help("Remove Sort")
                .accessibilityIdentifier("ViewPanelSortRemove")
        }
        .interfaceFont(.body)
        .frame(minHeight: ViewPanelMetrics.rowHeight)
        .padding(.horizontal, ViewPanelMetrics.inset)
        .contentShape(.rect)
        .modifier(Arrangeable(isOn: true, id: Self.prefix + key.column.id, move: move))
        .contextMenu {
            Button("Move Up") { browser.setSort(Reordering.moving(key, by: -1, in: sort)) }
                .disabled(sort.first == key)
            Button("Move Down") { browser.setSort(Reordering.moving(key, by: 1, in: sort)) }
                .disabled(sort.last == key)
            Button("Remove Sort") { remove() }
                .disabled(sort.count <= 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewPanelSortRow.\(key.column.id)")
    }

    private func remove() {
        browser.setSort(sort.filter { $0.column.id != key.column.id })
    }

    private func move(_ dragged: String) -> Bool {
        guard dragged.hasPrefix(Self.prefix) else { return false }
        let moved = String(dragged.dropFirst(Self.prefix.count))
        guard moved != key.column.id else { return false }
        browser.setSort(Reordering.moving(moved, onto: key.column.id, in: sort.map(\.column.id)).compactMap { id in
            sort.first { $0.column.id == id }
        })
        return true
    }
}

extension Browser {
    /// Sorts the open place by `sort`, and no longer by a search's relevance.
    func setSort(_ sort: [ItemTableComparator]) {
        orderSearch(byRelevance: false)
        tableOptions[shown, default: .init()].sort = sort
    }
}

// MARK: Group

/// Group: Group by, with By for a field grouped more than one way (a date's spans and Set or Not Set, a status's words
/// and groups), then the groups in order, each with a handle to drag and a switch, then Hide Empty Groups, which this
/// Mac keeps. The grouping, the order and the hidden groups are Marfa's in a saved view, and the place's own in its
/// default view.
struct ViewPanelGroup: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    @Bindable var panel: ViewPanel

    var body: some View {
        let offer = browser.groupOffer(in: library)
        let shown = browser.shownGrouping(in: library)
        let found = offer.entry(for: shown)
        ViewPanelHead(title: String(localized: "Group"), back: { panel.page = .main })
        Menu {
            GroupByChoices(browser: browser, offer: offer, shown: shown)
        } label: {
            ViewPanelRowLabel(
                symbol: "rectangle.grid.1x2", label: String(localized: "Group by"),
                value: found?.entry.label ?? String(localized: "None"), end: .pops)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityIdentifier("ViewPanelGroupBy")
        if let found, found.entry.choices.count > 1 {
            Menu {
                ForEach(Array(found.entry.runs.enumerated()), id: \.offset) { index, run in
                    if index > 0 { Divider() }
                    ForEach(run) { choice in
                        Toggle(isOn: Binding { shown == choice.grouping } set: { _ in browser.chooseGrouping(choice.grouping) }) {
                            Text(verbatim: choice.label)
                        }
                    }
                }
            } label: {
                ViewPanelRowLabel(symbol: "square.split.2x1", label: String(localized: "By"), value: found.choice.label, end: .pops)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityIdentifier("ViewPanelGroupMode")
        }
        if shown != .none, browser.datedList == nil {
            let hidden = browser.viewMode == .board && browser.boardLanes(in: library)?.isOwn == false
                ? Set<String>() : browser.tableOptions[browser.shown]?.hiddenGroups ?? []
            let rows = browser.groupRows(in: library).filter { $0.key != GroupKey.notApplicable }
            if !rows.isEmpty {
                ViewPanelSection(title: String(localized: "Groups")) {
                    ForEach(rows, id: \.key) { row in
                        ViewPanelGroupRow(browser: browser, key: row.key, title: row.title, isShown: !hidden.contains(row.key))
                    }
                }
            }
        }
        ViewPanelSection {
            ViewPanelSwitchRow(
                symbol: "eye.slash", label: String(localized: "Hide Empty Groups"), isOn: browser.hidesEmptyGroups,
                set: { browser.setHidesEmptyGroups($0) })
                .accessibilityIdentifier("ViewPanelHideEmptyGroups")
        }
        ViewPanelFoot(text: panel.purpose == .place
            ? ViewPanelKeeping.mac : String(localized: "Saved in Marfa for every app, except Hide Empty Groups."))
    }
}

/// The choices of Group by: None, Status, the fields, what every item has, then More Fields.
struct GroupByChoices: View {
    let browser: Browser
    let offer: GroupOffer
    let shown: ItemTableOptions.Grouping

    var body: some View {
        if offer.offersNone {
            choice(String(localized: "None"), .none)
            Divider()
        }
        ForEach(Array(offer.sections.enumerated()), id: \.offset) { index, section in
            if index > 0 { Divider() }
            ForEach(section) { entry($0) }
        }
        if !offer.moreFields.isEmpty {
            Divider()
            Menu("More Fields") {
                ForEach(offer.moreFields) { entry($0) }
            }
        }
    }

    @ViewBuilder private func entry(_ entry: GroupOffer.Entry) -> some View {
        if entry.choices.count == 1, let only = entry.choices.first {
            choice(entry.label, only.grouping)
        } else {
            Menu(entry.label) {
                ForEach(entry.choices) { option in
                    if option.startsSection { Divider() }
                    choice(option.label, option.grouping)
                }
            }
        }
    }

    private func choice(_ label: String, _ grouping: ItemTableOptions.Grouping) -> some View {
        Toggle(isOn: Binding { shown == grouping } set: { _ in browser.chooseGrouping(grouping) }) {
            Text(verbatim: label)
        }
    }
}

/// One group: a handle to drag it into order, its name, and the switch that shows or hides it. A hidden group leaves
/// the layout, and its items still count in the place.
private struct ViewPanelGroupRow: View {
    @CurrentLibrary private var library
    let browser: Browser
    let key: String
    let title: String
    let isShown: Bool

    private static let prefix = "group:"

    var body: some View {
        HStack(spacing: 8) {
            ViewPanelGrabber()
            Toggle(isOn: Binding { isShown } set: { browser.setGroup(key, hidden: !$0, in: library) }) {
                Text(verbatim: title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .interfaceFont(.body)
        .frame(minHeight: ViewPanelMetrics.rowHeight)
        .padding(.horizontal, ViewPanelMetrics.inset)
        .contentShape(.rect)
        .modifier(Arrangeable(isOn: true, id: Self.prefix + key, move: move))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewPanelGroup.\(key)")
    }

    private func move(_ dragged: String) -> Bool {
        guard dragged.hasPrefix(Self.prefix) else { return false }
        let moved = String(dragged.dropFirst(Self.prefix.count))
        guard moved != key else { return false }
        browser.moveGroup(moved, onto: key, in: library)
        return true
    }
}

// MARK: Properties

/// Properties, or a table's Columns: what shows after the title, in order, each with a handle to drag it and a switch.
/// The name is always first. Until the list is changed each item shows its own type's look ("As in Layouts"); Use
/// Layouts puts that back. Edit Layouts… opens Settings > Layouts at a type's page.
struct ViewPanelProperties: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    @Bindable var panel: ViewPanel

    var body: some View {
        let properties = browser.properties
        let listed = properties.arranged(browser.offeredProperties(in: library))
        let all = browser.tableContent(in: library).columns
        ViewPanelHead(title: browser.viewMode == .table ? String(localized: "Columns") : String(localized: "Properties"), back: {
            panel.page = .main
        })
        ForEach(listed) { column in
            ViewPanelPropertyRow(browser: browser, columns: all, column: column, isShown: properties.isShown(column))
        }
        ViewPanelSection {
            if properties.isChanged {
                Button { browser.useLayouts() } label: {
                    ViewPanelRowLabel(symbol: "arrow.uturn.backward", label: String(localized: "Use Layouts"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ViewPanelUseLayouts")
            }
            EditLayoutsCommand(types: browser.layoutTypes(in: library)) { browser.showLayouts(of: $0) }
                .buttonStyle(.plain)
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .frame(minHeight: ViewPanelMetrics.rowHeight)
                .padding(.horizontal, ViewPanelMetrics.inset)
        }
        ViewPanelFoot(text: ViewPanelKeeping.mac)
    }
}

private struct ViewPanelPropertyRow: View {
    let browser: Browser
    /// Every column of the place, which a move is spliced into.
    let columns: [ItemTableColumn]
    let column: ItemTableColumn
    let isShown: Bool

    private static let prefix = "column:"

    var body: some View {
        let isName = column.content == .title
        HStack(spacing: 8) {
            ViewPanelGrabber(isHidden: isName)
            Image(systemName: column.symbol)
                .foregroundStyle(.secondary)
                .frame(width: ViewPanelMetrics.symbolWidth)
                .accessibilityHidden(true)
            Toggle(isOn: Binding { isName || isShown } set: { browser.setColumn(column, shown: $0) }) {
                Text(verbatim: column.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            // The name always shows.
            .disabled(isName)
            .accessibilityIdentifier("ViewPanelPropertySwitch.\(column.id)")
        }
        .interfaceFont(.body)
        .frame(minHeight: ViewPanelMetrics.rowHeight)
        .padding(.horizontal, ViewPanelMetrics.inset)
        .contentShape(.rect)
        .modifier(Arrangeable(isOn: !isName, id: Self.prefix + column.id, move: move))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewPanelProperty.\(column.id)")
    }

    private func move(_ dragged: String) -> Bool {
        guard dragged.hasPrefix(Self.prefix) else { return false }
        let moved = String(dragged.dropFirst(Self.prefix.count))
        guard moved != column.id else { return false }
        browser.changeProperties { properties in
            let order = properties.arranged(columns).map(\.id)
            properties.move(moved, before: Reordering.anchor(dropping: moved, onto: column.id, in: order), in: columns)
        }
        return true
    }
}

/// Edit Layout of Events… for a place of one type, or Edit Layouts… with a menu of its types for several, each opening
/// Settings > Layouts at that type's page. Nothing for a place with no type.
struct EditLayoutsCommand: View {
    let types: [ItemTypeInfo]
    let open: (ItemTypeInfo) -> Void

    var body: some View {
        if types.count == 1, let type = types.first {
            Button("Edit Layout of \(type.plural)…", systemImage: "slider.horizontal.3") { open(type) }
                .accessibilityIdentifier("EditLayoutsCommand")
        } else if types.count > 1 {
            Menu("Edit Layouts…", systemImage: "slider.horizontal.3") {
                ForEach(types) { type in Button(type.plural) { open(type) } }
            }
            .accessibilityIdentifier("EditLayoutsCommand")
        }
    }
}
