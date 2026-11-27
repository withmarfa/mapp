import SwiftUI

/// The View button at the end of a view's toolbar, which opens the View panel under it and stays pressed while it is
/// open. It is tinted and counts the filters where the place has any, and carries a dot while the person has changed the
/// saved view since the window opened it, which Revert View takes back.
struct ViewPanelButton: View {
    @CurrentLibrary private var library
    @Environment(\.controlActiveState) private var activeState
    @Bindable var browser: Browser

    var body: some View {
        let count = browser.filterCount
        // Only an active window tints the button. In any other state it sets no style of its own, so it dims as its
        // neighbours do.
        let tinted = count > 0 && activeState != .inactive
        let changed = browser.isViewChanged
        Toggle(isOn: Binding { browser.showsViewPanel } set: { open in
            if open { browser.openViewPanel(in: library) } else { browser.escapeViewPanel(in: library) }
        }) {
            HStack(spacing: 3) {
                Image(systemName: "slider.horizontal.3")
                if count > 0 { Text("\(count)").font(.caption.monospacedDigit()) }
            }
            .tintedWhen(tinted)
            .overlay(alignment: .topTrailing) {
                if changed {
                    Circle()
                        .fill(.secondary)
                        .frame(width: 5, height: 5)
                        .offset(x: 4, y: -2)
                        .accessibilityHidden(true)
                }
            }
        }
        .toggleStyle(.button)
        .disabled(!browser.offersViewOptions || !library.isLoaded || browser.showsPlaceIndex)
        .help("View")
        .accessibilityLabel(Self.label(count: count, changed: changed))
        .accessibilityIdentifier("ViewOptionsToolbar")
        .popover(isPresented: presented, arrowEdge: .bottom) {
            if let panel = browser.viewPanel {
                ViewPanelPopover(browser: browser, panel: panel)
                    .environment(\.library, library)
            }
        }
    }

    private static func label(count: Int, changed: Bool) -> Text {
        switch (count > 0, changed) {
        case (true, true): Text("View, \(count) filters applied, changed")
        case (true, false): Text("View, \(count) filters applied")
        case (false, true): Text("View, changed")
        case (false, false): Text("View")
        }
    }

    /// The popover shows while the window holds a panel. A click outside it ends the panel as `dismissViewPanel` says.
    private var presented: Binding<Bool> {
        Binding { browser.showsViewPanel } set: { shown in
            if !shown { browser.dismissViewPanel(in: library) }
        }
    }
}

/// The View panel (`ViewPanel`): one page at a time, the view's settings first, and each of Types, Filter, Sort, Group
/// and Properties opened in place with a way back. Every change is kept as it is made, so it has no Save and no Done;
/// a new view, which does not exist until it is made, ends with Create View.
struct ViewPanelPopover: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    @Bindable var panel: ViewPanel

    /// The open page's own height, so each page is as tall as it needs, up to the most the panel grows to.
    @State private var height: CGFloat?

    var body: some View {
        ScrollView {
            page.onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: ViewPanelMetrics.width, height: height.map { min($0, ViewPanelMetrics.maxHeight) }, alignment: .top)
        .onExitCommand {
            if panel.page != .main { panel.page = .main } else { browser.escapeViewPanel(in: library) }
        }
        // A new view holding the person's work stays until they make it or cancel it.
        .interactiveDismissDisabled(browser.keepsNewViewOpen)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewPanel")
    }

    @ViewBuilder private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch panel.page {
            case .main:
                if panel.isNew { NewViewPage(browser: browser, panel: panel) } else { ViewPanelMain(browser: browser, panel: panel) }
            case .types: ViewPanelTypes(browser: browser, panel: panel)
            case .filter: ViewPanelFilter(browser: browser, panel: panel)
            case .sort: ViewPanelSort(browser: browser, panel: panel)
            case .group: ViewPanelGroup(browser: browser, panel: panel)
            case .properties: ViewPanelProperties(browser: browser, panel: panel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The panel's first page: the name with More, the layouts, the layout's own section, Items, Open Items and Quick
/// Actions, then the foot line.
private struct ViewPanelMain: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    @Bindable var panel: ViewPanel

    var body: some View {
        let mode = browser.viewMode
        ViewPanelNameHead(browser: browser, panel: panel)
        ViewPanelSection {
            ViewPanelLayoutTiles(browser: browser)
        }
        ViewPanelSection(title: mode.title) {
            ViewPanelLayoutRows(browser: browser, panel: panel)
        }
        ViewPanelSection(title: String(localized: "Items")) {
            ViewPanelItemsRows(browser: browser, panel: panel)
        }
        ViewPanelSection {
            ViewPanelOpeningRow(browser: browser)
            // Quick Actions belong where the view lists the Feed; one turned on elsewhere stays, to be turned off.
            if browser.showsQuickActions || ViewMacSettings.showsQuickActions(nil, in: browser.shown, scope: browser.listing.scope) {
                ViewPanelSwitchRow(
                    symbol: "bolt", label: String(localized: "Quick Actions"), isOn: browser.showsQuickActions,
                    set: { browser.setShowsQuickActions($0) })
                    .help("Buttons on the row under the pointer, such as Archive and Delete")
                    .accessibilityIdentifier("ViewPanelQuickActions")
            }
        }
        ViewPanelFoot(text: panel.purpose == .place ? ViewPanelKeeping.mac : ViewPanelKeeping.savedViewOverview)
    }
}

/// The head of the first page: the view's name, a field while it is renamed, and More.
private struct ViewPanelNameHead: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Bindable var browser: Browser
    @Bindable var panel: ViewPanel
    @FocusState private var nameFocused: Bool

    var body: some View {
        if panel.isRenaming {
            HStack {
                TextField("View Name", text: $panel.shownName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit { commitRename() }
                    .accessibilityIdentifier("ViewPanelName")
            }
            .frame(minHeight: ViewPanelMetrics.rowHeight)
            .padding(.horizontal, ViewPanelMetrics.inset)
            .padding(.top, 8)
            .task(id: panel.isRenaming) { nameFocused = true }
            // A rename is written when the person commits it: Return, or leaving the field.
            .onChange(of: nameFocused) { if !nameFocused, panel.isRenaming { commitRename() } }
        } else {
            ViewPanelHead(title: title) {
                more
            }
        }
    }

    private var title: String {
        panel.viewID == nil ? library.name(of: browser.shown) : panel.shownName
    }

    @ViewBuilder private var more: some View {
        let canSave = SavedViews.canSave(browser, in: library)
        Menu {
            if let id = panel.viewID {
                Button("Revert View", systemImage: "arrow.uturn.backward") { browser.revertView(in: library) }
                    .disabled(!browser.canRevertView)
                Button("Save as New View…", systemImage: "plus.rectangle.on.rectangle") { browser.openNewViewPanel(in: library) }
                    .disabled(!canSave)
                Button("Rename…", systemImage: "pencil") { panel.isRenaming = true }
                let place = SidebarPlace.view(id)
                let hidden = libraries.sidebarLayout.isHidden(place)
                Button(hidden ? "Add to Sidebar" : "Remove from Sidebar", systemImage: hidden ? "sidebar.left" : "minus.circle") {
                    libraries.updateSidebarLayout { $0.setHidden(place, !hidden) }
                }
                Divider()
                Button("Delete View…", systemImage: "trash", role: .destructive) {
                    // The window asks, and the panel is not left open over the question.
                    browser.escapeViewPanel(in: library)
                    browser.deletingView = id
                }
                .disabled(!library.reachesServer)
            } else {
                Button("New View…", systemImage: "plus.rectangle.on.rectangle") { browser.openNewViewPanel(in: library) }
                    .disabled(!canSave)
            }
        } label: {
            Label("More", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("More")
        .accessibilityIdentifier("ViewPanelMore")
    }

    private func commitRename() {
        panel.isRenaming = false
        Task { await browser.commitViewName(of: panel, in: library) }
    }
}

/// The layouts as tiles, four by two, each a symbol over its name. The chosen one has a grey fill, and one the place
/// cannot show is dimmed.
private struct ViewPanelLayoutTiles: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        let available = browser.availableViewModes(in: library)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(ItemViewMode.allCases, id: \.self) { mode in
                let chosen = browser.viewMode == mode
                Button {
                    browser.viewMode = mode
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.symbol)
                            .font(.title3)
                            .frame(height: 22)
                        Text(verbatim: mode.title)
                            .interfaceFont(.caption)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(chosen ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
                    .contentShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!available.contains(mode))
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier("ViewAs\(mode.rawValue.capitalized)")
            }
        }
        .padding(.horizontal, ViewPanelMetrics.inset)
        .padding(.vertical, 4)
    }
}

/// Items: Types, From, Archived Items, Filter, Sort and Group, each where the place takes it.
private struct ViewPanelItemsRows: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    @Bindable var browser: Browser
    @Bindable var panel: ViewPanel

    var body: some View {
        let content = browser.tableContent(in: library)
        let listing = browser.listing
        let mode = browser.viewMode
        if ViewPanelTypes.offersTypes(browser, content: content, library: library) {
            ViewPanelOpenRow(symbol: "square.grid.2x2", label: String(localized: "Types"), value: typesValue(content)) {
                panel.page = .types
            }
            .accessibilityIdentifier("ViewPanelTypesRow")
        }
        if Self.takesListing(browser.shown) {
            ViewPanelChoiceRow(
                symbol: "tray.2", label: String(localized: "From"), choices: ListScope.allCases, title: \.title,
                selection: listing.scope, choose: { browser.setScope($0) })
                .accessibilityIdentifier("ViewPanelFrom")
            ViewPanelChoiceRow(
                symbol: "archivebox", label: String(localized: "Archived Items"), choices: ArchivedItems.allCases, title: \.title,
                selection: listing.archived, choose: { browser.setArchived($0) })
                .accessibilityIdentifier("ViewPanelArchived")
        }
        ViewPanelOpenRow(symbol: "line.3.horizontal.decrease", label: String(localized: "Filter"), value: filterValue(content)) {
            panel.page = .filter
        }
        .accessibilityIdentifier("ViewPanelFilterRow")
        // The timeline and the calendar place items by time and the map by place, so a sort would change nothing there.
        if mode != .timeline, mode != .calendar, mode != .map {
            ViewPanelOpenRow(symbol: "arrow.up.arrow.down", label: String(localized: "Sort"), value: sortValue(content)) {
                panel.page = .sort
            }
            .disabled(browser.keepsPlaceOrder)
            .accessibilityIdentifier("ViewPanelSortRow")
            // A timeline groups by its date, which its own section sets.
            ViewPanelOpenRow(symbol: "rectangle.grid.1x2", label: String(localized: "Group"), value: groupValue) {
                panel.page = .group
            }
            .accessibilityIdentifier("ViewPanelGroupRow")
        }
    }

    /// Whether the place has a From and Archived Items of its own: a saved view, Favorites, and a type's, a
    /// collection's or a source's list. The Library, the Feed and the Archive are where they list from.
    static func takesListing(_ shown: PlaceView) -> Bool {
        switch shown.view {
        case .saved, .favorites: true
        case .own: shown.place.takesScope
        }
    }

    private func typesValue(_ content: ItemTableContent) -> String {
        guard content.filterOffer.targets[ViewDraft.typeFieldID] != nil else {
            return browser.listing.includesKinds ? String(localized: "With Kinds") : String(localized: "Own Items Only")
        }
        let chosen = ViewPanelTypes.chosen(in: browser)
        guard !chosen.isEmpty else { return String(localized: "All Types") }
        let catalogue = library.catalogue
        return chosen.map { catalogue.itemTypes[TypeID($0)]?.plural ?? $0 }.formatted(.list(type: .and, width: .narrow))
    }

    private func filterValue(_ content: ItemTableContent) -> String {
        let clauses = ViewPanelFilter.conditions(in: browser).filter { $0.clause.isComplete }
        switch clauses.count {
        case 0: return String(localized: "None")
        case 1:
            let clause = clauses[0].clause
            guard let target = content.filterOffer.targets[clause.field] else { return String(localized: "1 Condition") }
            let parts = FilterWording.parts(of: clause, target: target, calendar: .current, titles: { _ in nil })
            return [parts.field, parts.relation, parts.values].filter { !$0.isEmpty }.joined(separator: " ")
        default: return String(localized: "\(clauses.count) Conditions")
        }
    }

    private func sortValue(_ content: ItemTableContent) -> String {
        if browser.keepsPlaceOrder { return String(localized: "Collection Order") }
        if browser.ordersByRelevance { return String(localized: "Relevance") }
        let sort = SavedViews.arrangement(browser, content: content, order: order).sort
        guard let first = sort.first else { return String(localized: "None") }
        return sort.count > 1 ? String(localized: "\(first.column.label) and \(sort.count - 1) More") : first.column.label
    }

    private var groupValue: String {
        let shown = browser.shownGrouping(in: library)
        guard shown != .none, let found = browser.groupOffer(in: library).entry(for: shown) else { return String(localized: "None") }
        return found.entry.label
    }
}

/// Where an item opens from this place: as Settings says, or one way of the place's own.
private struct ViewPanelOpeningRow: View {
    @AppStorage(ListKey.openItemsIn) private var settings = ItemOpening.standard
    /// Only watched: a saved view's choice is kept in the app's settings, which `Browser.chosenOpening` reads.
    @AppStorage(ViewLayouts.key) private var layouts = ViewLayouts()
    @Bindable var browser: Browser

    var body: some View {
        let _ = layouts
        ViewPanelChoiceRow(
            symbol: "arrow.up.right.square", label: String(localized: "Open Items"),
            choices: [ItemOpening?.none] + ItemOpening.allCases.map(Optional.some),
            title: { $0?.title ?? String(localized: "As in Settings (\(settings.asDefault.title))") },
            selection: browser.chosenOpening, choose: { browser.setOpening($0) })
            .accessibilityIdentifier("ViewPanelOpenItems")
    }
}

/// What a new view will not keep of the window, so nothing is a surprise once it is made.
struct ViewPanelUnkept: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    let browser: Browser

    var body: some View {
        let window = SavedViews.window(browser, in: library, order: order)
        let unkept = ViewDraft.draft(window, catalogue: library.catalogue, views: library.views)?.unkept ?? []
        if !unkept.isEmpty {
            ViewPanelSection(title: String(localized: "Not Saved in the View")) {
                ForEach(unkept, id: \.self) { item in
                    Label(SavedViews.describe(item), systemImage: "exclamationmark.circle")
                        .interfaceFont(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, ViewPanelMetrics.inset)
                        .padding(.vertical, 2)
                }
            }
            .accessibilityIdentifier("ViewPanelUnkept")
        }
    }
}

extension ItemViewMode {
    /// The layout's name.
    var title: String {
        switch self {
        case .list: String(localized: "List")
        case .gallery: String(localized: "Gallery")
        case .table: String(localized: "Table")
        case .board: String(localized: "Board")
        case .timeline: String(localized: "Timeline")
        case .calendar: String(localized: "Calendar")
        case .digest: String(localized: "Digest")
        case .map: String(localized: "Map")
        }
    }
}

extension ArchivedItems {
    /// The View panel's words for each choice.
    var title: String {
        switch self {
        case .hidden: String(localized: "Hidden")
        case .shown: String(localized: "Shown")
        case .only: String(localized: "Only Archived")
        }
    }
}

private extension View {
    /// The accent color when `tinted`, and no style of its own otherwise, which a toolbar dims with its window.
    @ViewBuilder func tintedWhen(_ tinted: Bool) -> some View {
        if tinted { foregroundStyle(Color.accentColor) } else { self }
    }
}
