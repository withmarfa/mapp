import SwiftUI

/// A new view's page of the View panel, in the View panel's place: the starting points that fit the place, three to a
/// row; the view as one sentence of values, each a menu; the name, Add to Sidebar and Quick Actions; then Cancel and
/// Create View. The window behind lists what the view will list, and its pill stands in the row until it is made.
struct NewViewPage: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    @Environment(Libraries.self) private var libraries
    @Bindable var browser: Browser
    @Bindable var panel: ViewPanel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        let starts = browser.newViewStarts(in: library)
        let suggestion = browser.suggestedViewName(in: library)
        ViewPanelHead(title: String(localized: "New View"))
        if !starts.isEmpty {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(starts) { tile($0) }
            }
            .padding(.horizontal, ViewPanelMetrics.inset)
            .padding(.vertical, 6)
            .accessibilityIdentifier("NewViewStarts")
        }
        ViewPanelSection {
            NewViewSentence(browser: browser, panel: panel)
                .padding(.horizontal, ViewPanelMetrics.inset)
                .padding(.vertical, 4)
            ViewPanelUnkept(browser: browser)
        }
        ViewPanelSection {
            TextField("View Name", text: $panel.shownName, prompt: Text(verbatim: suggestion))
                .textFieldStyle(.roundedBorder)
                .onSubmit { create() }
                .padding(.horizontal, ViewPanelMetrics.inset)
                .frame(minHeight: ViewPanelMetrics.rowHeight)
                .accessibilityIdentifier("ViewPanelName")
            ViewPanelSwitchRow(
                symbol: "sidebar.left", label: String(localized: "Add to Sidebar"), isOn: panel.addsToSidebar,
                set: { panel.addsToSidebar = $0 })
                .accessibilityIdentifier("NewViewAddToSidebar")
            ViewPanelSwitchRow(
                symbol: "bolt", label: String(localized: "Quick Actions"), isOn: browser.showsQuickActions,
                set: { browser.setShowsQuickActions($0) })
                .help("Buttons on the row under the pointer, such as Archive and Delete")
                .accessibilityIdentifier("ViewPanelQuickActions")
        }
        if let problem = shownProblem {
            Label(problem, systemImage: "exclamationmark.triangle")
                .interfaceFont(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, ViewPanelMetrics.inset)
                .padding(.top, 6)
                .accessibilityIdentifier("NewViewProblem")
        }
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text(verbatim: ViewPanelKeeping.savedViewOverview)
                .interfaceFont(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { browser.escapeViewPanel(in: library) }
                    .accessibilityIdentifier("ViewPanelCancel")
                Button("Create View") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(panel.form?.isBusy == true || clash != nil || !library.reachesServer)
                    .accessibilityIdentifier("ViewPanelCreate")
            }
        }
        .padding(.horizontal, ViewPanelMetrics.inset)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .onChange(of: suggestion) { panel.suggest(suggestion) }
    }

    /// The name another view already has, which Create View will not take.
    private var clash: String? {
        let name = panel.trimmedName
        return !name.isEmpty && browser.viewNamed(name, in: library) != nil ? name : nil
    }

    private var shownProblem: String? {
        if let clash { return String(localized: "A view named “\(clash)” already exists. Choose another name.") }
        switch panel.problem {
        case .offline?:
            return library.reachesServer
                ? String(localized: "Your Marfa server is back. Choose Create View to save the view.")
                : String(localized: "Can’t Save View. Your Marfa server can’t be reached. Everything here stays until you choose Create View again.")
        case .refused?: return String(localized: "Can’t Save View. Change what Marfa refused, or choose Cancel.")
        case .clash?, nil: return nil
        }
    }

    private func tile(_ start: NewViewStart) -> some View {
        let theirs = browser.existingView(for: start, in: library)
        let chosen = panel.start == start
        return Button {
            if let theirs { browser.openExistingView(theirs, in: library, order: order) } else { browser.chooseStart(start, in: library) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: theirs == nil ? start.symbol : "checkmark.circle.fill")
                    .font(.body)
                    .frame(height: 18)
                Text(verbatim: start.title)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(chosen ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary), in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(theirs.map { Text("Open “\(title(of: $0))”") } ?? Text(start.title))
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("NewViewStart.\(start.rawValue)")
    }

    private func title(of place: PlaceView) -> String {
        switch place.view {
        case .saved(let id): library.views.first { $0.id == id }?.title ?? ""
        case .favorites: String(localized: "Favorites")
        case .own: library.name(of: place.place)
        }
    }

    private func create() {
        let addsToSidebar = panel.addsToSidebar
        Task {
            guard let made = await browser.finishViewPanel(in: library, order: order), !addsToSidebar else { return }
            libraries.updateSidebarLayout { $0.setHidden(SidebarPlace.view(made.id), true) }
        }
    }
}

/// The new view as one sentence, "Tasks from All Items as a Table sorted by Created", each value a menu. Edit Filter…
/// and the other Edit choices open the panel's own page for anything the menu does not hold.
private struct NewViewSentence: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    @Bindable var browser: Browser
    @Bindable var panel: ViewPanel

    var body: some View {
        let content = browser.tableContent(in: library)
        let place = browser.shown.place
        let mode = browser.viewMode
        TagFlowLayout(spacing: 4) {
            types(content)
            switch place {
            case .library: words(String(localized: "from the Library"))
            case .feed: words(String(localized: "from the Feed"))
            case .collection, .source: words(String(localized: "in \(library.name(of: place))"))
            default: EmptyView()
            }
            if place.takesScope {
                words(String(localized: "from"))
                value(browser.listing.scope.title, id: "From") {
                    ForEach(ListScope.allCases, id: \.self) { scope in
                        Toggle(scope.title, isOn: Binding { browser.listing.scope == scope } set: { _ in browser.setScope(scope) })
                    }
                }
            }
            filter(content, place: place)
            words(String(localized: "as a"))
            value(mode.title, id: "Layout") {
                ForEach(browser.availableViewModes(in: library), id: \.self) { layout in
                    Toggle(layout.title, isOn: Binding { browser.viewMode == layout } set: { _ in browser.viewMode = layout })
                }
            }
            if mode != .timeline, mode != .calendar, !browser.keepsPlaceOrder {
                words(String(localized: "sorted by"))
                sort(content)
                group
            }
        }
        .font(.system(size: 15))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("NewViewSentence")
    }

    private func words(_ text: String) -> some View {
        Text(verbatim: text).frame(minHeight: 28)
    }

    private func value<Items: View>(_ title: String, id: String, @ViewBuilder items: () -> Items) -> some View {
        Menu {
            items()
        } label: {
            Text(verbatim: title)
                .padding(.horizontal, 7)
                .frame(minHeight: 24)
                .background(.quaternary, in: .rect(cornerRadius: 7))
                .contentShape(.rect(cornerRadius: 7))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .frame(minHeight: 28)
        .accessibilityIdentifier("NewViewValue.\(id)")
    }

    @ViewBuilder private func types(_ content: ItemTableContent) -> some View {
        let catalogue = library.catalogue
        let chosen = ViewPanelTypes.chosen(in: browser).map { catalogue.itemTypes[TypeID($0)]?.plural ?? $0 }
        let title: String = if !chosen.isEmpty { chosen.formatted(.list(type: .and, width: .standard)) }
            else if case .type = browser.shown.place { library.name(of: browser.shown.place) }
            else { String(localized: "All items") }
        if ViewPanelTypes.offersTypes(browser, content: content, library: library) {
            value(title, id: "Types") {
                Button("Edit Types…") { panel.page = .types }
                if let index = ViewPanelTypes.typesClauseIndex(in: browser) {
                    Button("All Types") { browser.removeFilter(at: index) }
                }
            }
        } else {
            words(title)
        }
    }

    @ViewBuilder private func filter(_ content: ItemTableContent, place: Place) -> some View {
        let conditions = ViewPanelFilter.conditions(in: browser).filter { $0.clause.isComplete && !ViewPanelTypes.isTypesClause($0.clause) }
        if place == .feed, panel.start == .inbox || !browser.chosenSources.isEmpty {
            let sources = browser.inboxSources(in: library)
            let chosen = browser.chosenSources
            let names = sources.filter { chosen.contains($0.code) }.map(\.name)
            words(String(localized: "whose source is"))
            value(names.isEmpty ? String(localized: "any source") : names.formatted(.list(type: .or, width: .standard)), id: "Sources") {
                ForEach(sources, id: \.code) { source in
                    Toggle(isOn: Binding { chosen.isEmpty || chosen.contains(source.code) } set: {
                        browser.setSource(source.code, chosen: $0, in: library)
                    }) {
                        Text("\(source.name)  \(source.count.formatted())")
                    }
                }
                Divider()
                Button("Edit Filter…") { panel.page = .filter }
            }
        } else if conditions.isEmpty {
            words(String(localized: "with"))
            value(String(localized: "no filter"), id: "Filter") {
                Button("Edit Filter…") { panel.page = .filter }
            }
        } else {
            words(String(localized: "where"))
            value(filterTitle(conditions.map(\.clause), content: content), id: "Filter") {
                Button("Edit Filter…") { panel.page = .filter }
                Button("Remove Filters") {
                    for index in conditions.map(\.index).sorted(by: >) { browser.removeFilter(at: index) }
                }
            }
        }
    }

    private func filterTitle(_ clauses: [FilterClause], content: ItemTableContent) -> String {
        guard clauses.count == 1, let clause = clauses.first, let target = content.filterOffer.targets[clause.field] else {
            return String(localized: "\(clauses.count) conditions")
        }
        let parts = FilterWording.parts(of: clause, target: target, calendar: .current, titles: { _ in nil })
        return [parts.field, parts.relation, parts.values].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func sort(_ content: ItemTableContent) -> some View {
        let sort = SavedViews.arrangement(browser, content: content, order: order).sort
        return value(sort.first?.column.label ?? String(localized: "None"), id: "Sort") {
            ForEach(content.sortChoices) { column in
                Toggle(column.label, isOn: Binding { sort.first?.column.id == column.id } set: { _ in
                    browser.setSort([ItemTableComparator(column: column, order: column.firstOrder)])
                })
            }
            Divider()
            Button("Edit Sort…") { panel.page = .sort }
        }
    }

    @ViewBuilder private var group: some View {
        let shown = browser.shownGrouping(in: library)
        let offer = browser.groupOffer(in: library)
        if shown != .none, let found = offer.entry(for: shown) {
            words(String(localized: "grouped by"))
            value(found.entry.label, id: "Group") {
                GroupByChoices(browser: browser, offer: offer, shown: shown)
                Divider()
                Button("Edit Group…") { panel.page = .group }
            }
        }
    }
}
