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
                case .views: viewsSection
                default: EmptyView()
                }
            }

        }
        .listStyle(.sidebar)
        // The system's scroll edge shows the foot over a material only while rows pass beneath it.
        .safeAreaInset(edge: .bottom, spacing: 0) { SidebarFoot(browser: browser) }
        .softSelection(rows: selectionRows(plan), selection: browser.sidebarItem)
        .accessibilityIdentifier("Sidebar")
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

    /// A view lists what the copy holds of its items, read on its own, so its row has no count.
    private var viewsSection: some View {
        Section("Views") {
            ForEach(library.views) { view in
                row(.view(view.id), symbol: SidebarPlace.viewSymbol, title: view.title, hiding: .views, counted: false)
                    .accessibilityIdentifier("SidebarView-\(view.id.rawValue)")
            }
        }
        .accessibilityIdentifier("SidebarViews")
    }

    private func typesSection(_ plan: SidebarPlan) -> some View {
        Section {
            ForEach(plan.shownTypes) { typeRow($0) }
        } header: {
            TypesHeading(editsTypes: $editsTypes)
        }
    }

    /// A type opens its own items; a type with subtypes also folds them open, and a group only folds. Erased, since
    /// a row holds rows of its own kind.
    private func typeRow(_ node: TypeNode) -> AnyView {
        guard !node.children.isEmpty else { return AnyView(typeLabel(node)) }
        return AnyView(DisclosureGroup(isExpanded: expansion(.type(node.id))) {
            ForEach(node.children) { typeRow($0) }
        } label: {
            typeLabel(node)
        })
    }

    @ViewBuilder private func typeLabel(_ node: TypeNode) -> some View {
        if node.opens, let type = node.type {
            row(.itemType(type.rawValue), symbol: node.symbol, title: node.label, hiding: .type(node.id))
                .accessibilityIdentifier("SidebarType-\(node.id)")
        } else {
            sidebarLabel(node.label, symbol: node.symbol)
                .selectionDisabled()
                .contextMenu { hideButton(.type(node.id)) }
                .accessibilityIdentifier("SidebarTypeGroup-\(node.id)")
        }
    }

    /// A section's or a row's disclosure, kept in the library's sidebar layout so it is remembered for each library.
    /// Everything starts open.
    private func expansion(_ section: SidebarPlace) -> Binding<Bool> {
        Binding {
            !libraries.sidebarLayout.isCollapsed(section)
        } set: { isExpanded in
            libraries.updateSidebarLayout { $0.setCollapsed(section, !isExpanded) }
        }
    }

    private var favorites: [Item] {
        library.items(in: .favorites)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// A view's row hides the whole Views section, which its title says, since the layout keeps no view of its own.
    @ViewBuilder private func hideButton(_ place: SidebarPlace) -> some View {
        let hide = { libraries.updateSidebarLayout { $0.setHidden(place, true) } }
        if place == .views {
            Button("Hide Views from Sidebar", action: hide)
        } else {
            Button("Hide from Sidebar", action: hide)
        }
    }

    private func row(
        _ item: SidebarItem, symbol: String, title: String? = nil, hiding place: SidebarPlace? = nil, counted: Bool = true
    ) -> some View {
        sidebarLabel(title ?? library.name(of: item), symbol: symbol)
            .badge(counted ? count(in: item) : nil)
            .tag(item)
            .contextMenu {
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
                "collection-\(index)", type: "sample.project",
                properties: ["title": .string("Research collection \(index) with a longer title")], created: date, edited: date),
            SampleLibrary.row(
                "child-\(index)", type: "core.note", properties: ["title": .string("Field note \(index)")], created: date,
                edited: date),
        ]
    }
    let edges = (1...100).map { index in
        Marfa.Edge(
            id: "edge-\(index)", sourceId: "collection-\(index)", targetId: "child-\(index)", edgeType: "parent-of",
            properties: [:], version: 1, createdAt: SampleLibrary.stamp(date), updatedAt: SampleLibrary.stamp(date))
    }
    let library = MarfaLibrary(source: SampleLibrary.open(SampleLibrary.connection, items: rows, edges: edges, now: date), notices: Notices())
    let browser = Browser()
    NavigationSplitView {
        Sidebar(browser: browser, order: NoteOrder())
        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 340)
        .toolbar {
            ToolbarItem { NewItemButton(browser: browser) }
        }
    } detail: {
        Color.clear
    }
    .environment(\.library, library)
    .environment(ItemPreviewFixtures.libraries(named: "MAPP.LargeSidebarPreview"))
    .frame(width: 700, height: 740)
}
#endif
