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
        let plan = SidebarPlan(library, layout: libraries.sidebarLayout)
        List(selection: selection) {
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
        .onKeyPress(.rightArrow) { foldSelectedType(open: true) }
        .onKeyPress(.leftArrow) { foldSelectedType(open: false) }
        .onChange(of: favorites.map(\.id)) {
            browser.placeRemoved(in: library, order: order)
        }
        .onChange(of: library.views.map(\.id)) {
            browser.placeRemoved(in: library, order: order)
        }
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
        // Every row keeps the chevron's width once any row can fold, so the counts line up in one column.
        let reservesChevron = rows.contains(where: \.isExpandable)
        return Section {
            ForEach(rows) { typeRow($0, reservesChevron: reservesChevron) }
        } header: {
            TypesHeading(editsTypes: $editsTypes)
        }
    }

    /// A type opens its own items; a type with subtypes also folds them open, and a group only folds. The rows are
    /// one flat list, a subtype's drawn indented under its parent, because the system's disclosure puts its chevron
    /// at the leading edge and cannot be moved. `SidebarDisclosure` draws the chevron at the trailing edge instead.
    @ViewBuilder private func typeRow(_ row: SidebarPlan.TypeRow, reservesChevron: Bool) -> some View {
        let node = row.node
        if node.opens, let type = node.type {
            let item = SidebarItem.itemType(type.rawValue)
            typeContent(row, count: library.count(in: item), reservesChevron: reservesChevron)
                .tag(item)
                .contextMenu { hideButton(.type(node.id)) }
                .accessibilityIdentifier("SidebarType-\(node.id)")
        } else {
            // A group only folds, so a click anywhere on its row does.
            Button { toggle(row) } label: {
                typeContent(row, count: 0, reservesChevron: reservesChevron)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .selectionDisabled()
            .contextMenu { hideButton(.type(node.id)) }
            .accessibilityLabel(Text(node.label))
            .accessibilityValue(row.isExpanded ? Text("Expanded") : Text("Collapsed"))
            .accessibilityIdentifier("SidebarTypeGroup-\(node.id)")
        }
    }

    /// The row's mark and name, then its count and chevron at the trailing end.
    private func typeContent(_ row: SidebarPlan.TypeRow, count: Int, reservesChevron: Bool) -> some View {
        HStack(spacing: 4) {
            sidebarLabel(row.node.label, symbol: row.node.symbol)
                .padding(.leading, CGFloat(row.depth) * 14)
            Spacer(minLength: 8)
            if count > 0 {
                Text(count, format: .number)
                    .monospacedDigit()
                    // The size of the system's own count on the rows above, which does not follow the base text size.
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if row.isExpandable {
                SidebarDisclosure(title: row.node.label, id: row.node.id, isExpanded: row.isExpanded, isButton: row.node.opens) {
                    toggle(row)
                }
            } else if reservesChevron {
                Color.clear.frame(width: SidebarDisclosure.width)
            }
        }
    }

    private func foldSelectedType(open: Bool) -> KeyPress.Result {
        let plan = SidebarPlan(library, layout: libraries.sidebarLayout)
        guard let row = plan.typeRows.first(where: { row in
            row.isExpandable && row.isExpanded != open && row.node.type.map { .itemType($0.rawValue) } == browser.sidebarItem
        }) else { return .ignored }
        toggle(row)
        return .handled
    }

    private func toggle(_ row: SidebarPlan.TypeRow) {
        withAnimation(.snappy(duration: 0.2)) {
            libraries.updateSidebarLayout { $0.setCollapsed(.type(row.node.id), row.isExpanded) }
        }
    }

    private var favorites: [Item] {
        library.items(in: .favorites)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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
        sidebarLabel(title ?? library.name(of: item), symbol: symbol)
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

    private func sidebarLabel(_ title: String, symbol: String) -> some View {
        Label {
            Text(title).interfaceFont(.body).lineLimit(1).truncationMode(.tail)
        } icon: {
            Image(systemName: symbol).interfaceFont(.body).foregroundStyle(.secondary)
        }
    }
}

/// The Types heading. Edit shows only while the pointer is over the heading, or its picker is open, as the control
/// of a sidebar's section heading does.
private struct TypesHeading: View {
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
