import SwiftUI
#if DEBUG
import Marfa
#endif

struct Sidebar: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    let browser: Browser
    let order: NoteOrder
    @State private var editsTypes = false
    @State private var choosingIcon: TypeIconRequest?
    @AppStorage(SidebarTypeRow.subtypeIconsKey) private var showsSubtypeIcons = false

    /// Empty clicks leave the destination intact. Settings clears the visible selection, so choosing the
    /// previous destination returns to its existing state.
    private var selection: Binding<SidebarItem?> {
        Binding {
            browser.showsSettings ? nil : browser.sidebarItem
        } set: { item in
            guard let item else { return }
            if item == browser.sidebarItem {
                browser.leaveSettings()
            } else {
                browser.show(item, in: library, order: order)
            }
        }
    }

    var body: some View {
        #if DEBUG
        // The sidebar experiment (`SidebarStyle`), switched live from the tuning panel.
        switch SidebarStyle.selected {
        case .experiment: ExperimentSidebar(browser: browser, order: order)
        case .tabs: TabsSidebar(browser: browser, order: order)
        case .current: currentSidebar
        }
        #else
        currentSidebar
        #endif
    }

    private var currentSidebar: some View {
        let plan = SidebarPlan(library, layout: libraries.sidebarLayout)
        return List(selection: selection) {
            if !plan.shownTop.isEmpty {
                Section {
                    ForEach(plan.shownTop, id: \.key) { place in
                        switch place {
                        case .inbox: row(.inbox, symbol: "tray", hiding: .inbox)
                        // Always the same number, so it says nothing.
                        case .recents: row(.recents, symbol: "clock", hiding: .recents, counted: false)
                        default:
                            row(.favorites, symbol: "heart", hiding: .favorites)
                                .accessibilityIdentifier("SidebarFavorites")
                        }
                    }
                }
            }

            if !plan.shownBrowse.isEmpty {
                Section("Browse") {
                    ForEach(plan.shownBrowse, id: \.key) { place in
                        switch place {
                        case .sources:
                            row(.sources, symbol: "antenna.radiowaves.left.and.right", hiding: .sources, counted: false)
                                .accessibilityIdentifier("SidebarSources")
                        case .collections:
                            row(.collections, symbol: "square.stack", hiding: .collections, counted: false)
                                .accessibilityIdentifier("SidebarCollections")
                        default: row(.allNotes, symbol: "note.text", hiding: .all)
                        }
                    }
                }
                .accessibilityIdentifier("SidebarBrowse")
            }

            ForEach(plan.shownLibrary, id: \.key) { section in
                switch section {
                case .types: typesSection(plan)
                case .views: viewsSection(plan)
                default: EmptyView()
                }
            }

        }
        .listStyle(.sidebar)
        // The system's scroll edge shows the foot over a material only while rows pass beneath it.
        .safeAreaInset(edge: .bottom, spacing: 0) { SidebarFoot(browser: browser) }
        .softSelection(rows: selectionRows(plan), selection: browser.sidebarItem)
        .accessibilityIdentifier("Sidebar")
        // The right and left arrows open and close the selected type, as the system's outline does for its own rows.
        .onKeyPress(.rightArrow, phases: [.down, .repeat]) { pressArrow(.right, $0) }
        .onKeyPress(.leftArrow, phases: [.down, .repeat]) { pressArrow(.left, $0) }
        .onChange(of: favorites.map(\.id)) {
            browser.placeRemoved(in: library, order: order)
        }
        .onChange(of: library.views.map(\.id)) {
            browser.placeRemoved(in: library, order: order)
        }
        .sheet(item: $choosingIcon) { TypeIconPicker(request: $0, library: library) }
    }

    private func selectionRows(_ plan: SidebarPlan) -> [String] {
        plan.shownTop.map(\.key) + plan.shownBrowse.map(\.key) + plan.shownLibrary.map(\.key)
            + libraries.sidebarLayout.collapsed.sorted() + libraries.sidebarLayout.hidden.sorted()
            + library.itemTypeCounts.map { $0.id.rawValue } + library.views.map(\.id.rawValue)
    }

    /// A view lists what the copy holds of its items, read on its own, so its row has no count. The person can
    /// drag a row to a new place among the others.
    private func viewsSection(_ plan: SidebarPlan) -> some View {
        Section {
            ForEach(plan.shownViews) { view in
                row(.view(view.id), symbol: SidebarPlace.viewSymbol, title: view.title, hiding: .view(view.id), counted: false)
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

    private func typesSection(_ plan: SidebarPlan) -> some View {
        let rows = plan.typeRows
        let steps = SidebarTypeRow.steps(for: rows, subtypeIcons: showsSubtypeIcons)
        let widest = rows.filter(\.isExpandable).map(count(of:)).max() ?? 0
        return Section {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                typeRow(row, widestFoldingCount: widest, steps: steps[index])
            }
        } header: {
            TypesHeading(editsTypes: $editsTypes)
        }
    }

    /// A type opens its own items; a type with subtypes also folds them open, and a group only folds. The rows are
    /// one flat list, a subtype's drawn one step in under its parent, because the system's disclosure puts its chevron
    /// at the leading edge and cannot be moved or guided.
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
            // A group only folds, so a click anywhere on its row does.
            Button { toggle(row) } label: {
                content.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .selectionDisabled()
            .listRowInsets(.vertical, 0)
            .contextMenu { typeMenu(node) }
            .accessibilityLabel(Text(node.label))
            .accessibilityValue(row.isExpanded ? Text("Expanded") : Text("Collapsed"))
            .accessibilityIdentifier("SidebarTypeGroup-\(node.id)")
        }
    }

    private func count(of row: SidebarPlan.TypeRow) -> Int {
        guard row.node.opens, let type = row.node.type else { return 0 }
        return library.count(in: .itemType(type.rawValue))
    }

    /// An arrow key does what the system's outline does for the selected type. Settings shows no selection, and a
    /// key with a modifier belongs to someone else.
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

    private var favorites: [Item] {
        library.items(in: .favorites)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// A type's own icon is chosen from its row; a group has no type of its own, so it only hides.
    @ViewBuilder private func typeMenu(_ node: TypeNode) -> some View {
        if let type = node.type {
            Button("Choose Icon…") { choosingIcon = TypeIconRequest(type: type) }
                .disabled(!library.canChooseTypeIcons)
            Divider()
        }
        hideButton(.type(node.id))
    }

    /// A view's row hides that view alone, and offers the whole Views section as well.
    @ViewBuilder private func hideButton(_ place: SidebarPlace) -> some View {
        Button("Hide from Sidebar") { libraries.updateSidebarLayout { $0.setHidden(place, true) } }
        if case .view = place {
            Button("Hide Views from Sidebar") { libraries.updateSidebarLayout { $0.setHidden(.views, true) } }
        }
    }

    private func row(
        _ item: SidebarItem, symbol: String, title: String? = nil, hiding place: SidebarPlace? = nil, counted: Bool = true
    ) -> some View {
        SidebarLabel(title: title ?? library.name(of: item), icon: .symbol(symbol))
            .badge(counted ? count(in: item) : nil)
            .tag(item)
            .contextMenu {
                if case .view(let id) = item {
                    SavedViewRowMenu(view: id, browser: browser)
                    Divider()
                }
                if let place { hideButton(place) }
            }
    }

    /// The count at the row's trailing edge, in secondary text with digits that line up; none where it is zero.
    private func count(in item: SidebarItem) -> Text? {
        let count = library.count(in: item)
        return count > 0 ? Text(count, format: .number).monospacedDigit() : nil
    }
}

/// The Types heading. Edit shows only while the pointer is over the heading, or its picker is open, as the control
/// of a sidebar's section heading does.
struct TypesHeading: View {
    @Binding var editsTypes: Bool
    @State private var isHovering = false

    var body: some View {
        HStack {
            Text("Types")
            Spacer()
            Button("Edit") { editsTypes = true }
                .buttonStyle(.plain)
                .opacity(isHovering || editsTypes ? 1 : 0)
                .popover(isPresented: $editsTypes) {
                    SidebarTypePicker()
                }
                .accessibilityIdentifier("EditSidebarTypes")
        }
        .padding(.trailing, 12)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .accessibilityIdentifier("SidebarTypes")
    }
}

#if DEBUG
#Preview("Sample Sidebar") {
    Sidebar(browser: Browser(), order: NoteOrder())
        .environment(\.library, MarfaLibrary(source: SampleLibrary.open(SampleLibrary.connection), notices: Notices()))
        .environment(ItemPreviewFixtures.libraries(named: "MAPP.SidebarPreview"))
        .frame(width: 260, height: 740)
}

#Preview("Sidebar Without Favorites") {
    Sidebar(browser: Browser(), order: NoteOrder())
        .environment(\.library, ItemPreviewFixtures.library)
        .environment(ItemPreviewFixtures.libraries(named: "MAPP.SidebarPreview"))
        .frame(width: 260, height: 740)
}

#Preview("Sidebar: 100 Collections") {
    let date = ItemPreviewFixtures.date
    let rows = (1...100).flatMap { index in
        [
            SampleLibrary.row(
                "collection-\(index)", type: "core.collection",
                properties: ["title": .string("Research collection \(index) with a longer title")], created: date, edited: date),
            SampleLibrary.row(
                "child-\(index)", type: "core.note", properties: ["title": .string("Field note \(index)")], created: date,
                edited: date),
        ]
    }
    let edges = (1...100).map { index in
        Marfa.Edge(
            id: "edge-\(index)", sourceId: "child-\(index)", targetId: "collection-\(index)", edgeType: "in-collection",
            properties: [:], version: 1, createdAt: SampleLibrary.stamp(date), updatedAt: SampleLibrary.stamp(date))
    }
    let library = MarfaLibrary(source: SampleLibrary.open(SampleLibrary.connection, items: rows, edges: edges, now: date), notices: Notices())
    let browser = Browser()
    NavigationSplitView {
        Sidebar(browser: browser, order: NoteOrder())
        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 340)
    } detail: {
        Color.clear
    }
    .environment(\.library, library)
    .environment(ItemPreviewFixtures.libraries(named: "MAPP.LargeSidebarPreview"))
    .frame(width: 700, height: 740)
}
#endif
