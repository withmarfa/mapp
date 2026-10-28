#if DEBUG
import SwiftUI

/// The sidebar design experiment: a short list in the manner of the Claude app. New and Search act, then Items,
/// Sources and Collections open. Below that every block is one the person can switch off in Settings > Sidebar, with
/// the real sidebar's own switches, order and per-library layout (`SidebarLayouts`): the places (Inbox, Recents,
/// Favorites), the types and the saved views. There is no More. The foot is the real one, and Recently Deleted stays in
/// its menu. Its text is not localized.
struct ExperimentSidebar: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    let browser: Browser
    let order: NoteOrder
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    @AppStorage(SidebarTypeRow.subtypeIconsKey) private var showsSubtypeIcons = false
    @State private var showsAllTypes = false
    @State private var editsTypes = false
    @State private var choosingIcon: TypeIconRequest?

    /// Items opens the landing, which is Items in a layout that spans the window; every other place opens as in the
    /// real sidebar.
    private var selection: Binding<SidebarItem?> {
        Binding {
            browser.showsSettings ? nil : browser.sidebarItem
        } set: { item in
            guard let item else { return }
            if item == .allNotes {
                browser.showItemsLanding(in: library, order: order)
            } else if item == browser.sidebarItem {
                browser.leaveSettings()
            } else {
                browser.show(item, in: library, order: order)
            }
        }
    }

    var body: some View {
        let plan = SidebarPlan(library, layout: libraries.sidebarLayout)
        let blocks = ExperimentBlocks(plan)
        List(selection: selection) {
            Section {
                actionRow("New", symbol: "square.and.pencil") { browser.openQuickAdd(remembered: lastType, in: library) }
                    .accessibilityIdentifier("ExperimentNew")
                actionRow("Search", symbol: "magnifyingglass") { browser.palette = .search }
                    .accessibilityIdentifier("ExperimentSearch")
                ForEach(blocks.top, id: \.key) { placeRow($0) }
            }
            if !blocks.places.isEmpty {
                Section {
                    ForEach(blocks.places, id: \.key) { placeRow($0) }
                }
                .accessibilityIdentifier("ExperimentPlaces")
            }
            if blocks.showsTypes { typesSection(plan) }
            if blocks.showsViews { viewsSection(plan) }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { SidebarFoot(browser: browser) }
        .softSelection(rows: selectionRows(plan) + [String(showsAllTypes)], selection: browser.sidebarItem)
        .accessibilityIdentifier("Sidebar")
        .onKeyPress(.rightArrow, phases: [.down, .repeat]) { pressArrow(.right, $0) }
        .onKeyPress(.leftArrow, phases: [.down, .repeat]) { pressArrow(.left, $0) }
        .onChange(of: library.views.map(\.id)) { browser.placeRemoved(in: library, order: order) }
        .sheet(item: $choosingIcon) { TypeIconPicker(request: $0, library: library) }
    }

    private func selectionRows(_ plan: SidebarPlan) -> [String] {
        plan.shownTop.map(\.key) + plan.shownBrowse.map(\.key) + plan.shownLibrary.map(\.key)
            + libraries.sidebarLayout.collapsed.sorted() + libraries.sidebarLayout.hidden.sorted()
            + library.itemTypeCounts.map { $0.id.rawValue } + library.views.map(\.id.rawValue)
    }

    // MARK: Rows

    private func actionRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SidebarLabel(title: title, icon: .symbol(symbol)).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .selectionDisabled()
    }

    private struct PlaceLook {
        let item: SidebarItem
        let symbol: String
        let counted: Bool
    }

    private func look(of place: SidebarPlace) -> PlaceLook? {
        switch place {
        case .all: PlaceLook(item: .allNotes, symbol: "square.grid.2x2", counted: true)
        case .sources: PlaceLook(item: .sources, symbol: "antenna.radiowaves.left.and.right", counted: false)
        case .collections: PlaceLook(item: .collections, symbol: "square.stack", counted: false)
        case .inbox: PlaceLook(item: .inbox, symbol: "tray", counted: true)
        // Always the same number, so it says nothing.
        case .recents: PlaceLook(item: .recents, symbol: "clock", counted: false)
        case .favorites: PlaceLook(item: .favorites, symbol: "heart", counted: true)
        default: nil
        }
    }

    @ViewBuilder private func placeRow(_ place: SidebarPlace) -> some View {
        if let look = look(of: place) {
            let count = look.counted ? library.count(in: look.item) : 0
            SidebarLabel(title: library.name(of: look.item), icon: .symbol(look.symbol))
                .badge(count > 0 ? Text(count, format: .number).monospacedDigit() : nil)
                .tag(look.item)
                .contextMenu { hideButton(place) }
                .accessibilityIdentifier("ExperimentPlace-\(place.key)")
        }
    }

    @ViewBuilder private func hideButton(_ place: SidebarPlace) -> some View {
        Button("Hide from Sidebar") { libraries.updateSidebarLayout { $0.setHidden(place, true) } }
        if case .view = place {
            Button("Hide Views from Sidebar") { libraries.updateSidebarLayout { $0.setHidden(.views, true) } }
        }
    }

    // MARK: Types

    /// The real Types block: its heading with Edit on hover, the same folding rows, and at most `shownCount` types until
    /// Show More.
    private func typesSection(_ plan: SidebarPlan) -> some View {
        let limited = ExperimentTypeLimit.rows(plan.typeRows, showsAll: showsAllTypes)
        let rows = limited.rows
        let steps = SidebarTypeRow.steps(for: rows, subtypeIcons: showsSubtypeIcons)
        let widest = rows.filter(\.isExpandable).map(count(of:)).max() ?? 0
        return Section {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                typeRow(row, widestFoldingCount: widest, steps: steps[index])
            }
            if limited.hasMore { showMoreRow }
        } header: {
            TypesHeading(editsTypes: $editsTypes)
        }
    }

    /// A row of text under the types, laid out like a row with a mark so its words start where the names above do.
    private var showMoreRow: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { showsAllTypes.toggle() }
        } label: {
            Label {
                Text(verbatim: showsAllTypes ? "Show Less" : "Show More")
                    .interfaceFont(.body)
                    .foregroundStyle(.secondary)
            } icon: {
                RowIconImage(icon: .symbol("circle")).interfaceFont(.body).hidden()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .accessibilityIdentifier(showsAllTypes ? "ExperimentShowLess" : "ExperimentShowMore")
    }

    @ViewBuilder private func typeRow(_ row: SidebarPlan.TypeRow, widestFoldingCount: Int, steps: [SidebarTypeRow.Step]) -> some View {
        let node = row.node
        let content = SidebarTypeRow(
            row: row, count: count(of: row), widestFoldingCount: widestFoldingCount, steps: steps,
            showsIcon: SidebarTypeRow.showsIcon(row, subtypeIcons: showsSubtypeIcons), toggle: { toggle(row) })
        if node.opens, let type = node.type {
            content
                .tag(SidebarItem.itemType(type.rawValue))
                .listRowInsets(.vertical, 0)
                .contextMenu { typeMenu(node) }
                .accessibilityIdentifier("SidebarType-\(node.id)")
        } else {
            Button { toggle(row) } label: { content.contentShape(.rect) }
                .buttonStyle(.plain)
                .selectionDisabled()
                .listRowInsets(.vertical, 0)
                .contextMenu { typeMenu(node) }
                .accessibilityLabel(Text(node.label))
                .accessibilityValue(row.isExpanded ? Text("Expanded") : Text("Collapsed"))
                .accessibilityIdentifier("SidebarTypeGroup-\(node.id)")
        }
    }

    @ViewBuilder private func typeMenu(_ node: TypeNode) -> some View {
        if let type = node.type {
            Button("Choose Icon…") { choosingIcon = TypeIconRequest(type: type) }
                .disabled(!library.canChooseTypeIcons)
            Divider()
        }
        hideButton(.type(node.id))
    }

    private func count(of row: SidebarPlan.TypeRow) -> Int {
        guard row.node.opens, let type = row.node.type else { return 0 }
        return library.count(in: .itemType(type.rawValue))
    }

    private func toggle(_ row: SidebarPlan.TypeRow) {
        setCollapsed(row.node.id, row.isExpanded)
    }

    /// Folding a row that holds the selected type selects the row, so something stays highlighted.
    private func setCollapsed(_ id: String, _ collapsed: Bool) {
        if collapsed, !browser.showsSettings {
            let plan = SidebarPlan(library, layout: libraries.sidebarLayout)
            if let item = plan.selectionAfterFolding(id, selected: browser.sidebarItem) {
                browser.show(item, in: library, order: order)
            }
        }
        withAnimation(.snappy(duration: 0.2)) {
            libraries.updateSidebarLayout { $0.setCollapsed(.type(id), collapsed) }
        }
    }

    private func pressArrow(_ arrow: SidebarPlan.Arrow, _ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isEmpty, !browser.showsSettings else { return .ignored }
        let plan = SidebarPlan(library, layout: libraries.sidebarLayout)
        switch plan.outcome(of: arrow, selected: browser.sidebarItem) {
        case .fold(let id, let collapsed): setCollapsed(id, collapsed)
        case .select(let item): browser.show(item, in: library, order: order)
        case nil: return .ignored
        }
        return .handled
    }

    // MARK: Views

    private func viewsSection(_ plan: SidebarPlan) -> some View {
        Section {
            ForEach(plan.shownViews) { view in
                SidebarLabel(title: view.title, icon: .symbol(SidebarPlace.viewSymbol))
                    .tag(SidebarItem.view(view.id))
                    .contextMenu {
                        SavedViewRowMenu(view: view.id, browser: browser)
                        Divider()
                        hideButton(.view(view.id))
                    }
                    .accessibilityIdentifier("SidebarView-\(view.id.rawValue)")
            }
            .onMove { source, destination in
                libraries.updateSidebarLayout {
                    $0.move(plan.views, shown: plan.shownViews, by: { SidebarPlace.view($0.id).key }, fromOffsets: source, toOffset: destination)
                }
            }
        } header: {
            ViewsHeading(browser: browser)
        }
        .accessibilityIdentifier("SidebarViews")
    }
}
#endif
