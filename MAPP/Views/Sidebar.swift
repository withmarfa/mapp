import SwiftUI

/// The window's sidebar, in the manner of the Claude desktop app: New and Search act, then Items, Sources and
/// Collections open. The Views block follows, holding Inbox, Recents and Favorites and then the saved views, and the
/// Types block after it. Settings > Sidebar switches each place on or off, and the foot holds the instance.
struct Sidebar: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    @State private var choosingIcon: TypeIconRequest?
    let browser: Browser
    let order: NoteOrder

    /// Empty clicks leave the destination intact. Settings clears the visible selection, so choosing the previous
    /// destination returns to its existing state.
    private var selection: Binding<SidebarItem?> {
        Binding {
            browser.showsSettings ? nil : browser.sidebarItem
        } set: { item in
            guard let item else { return }
            if item == browser.sidebarItem {
                browser.leaveSettings()
            } else {
                browser.choose(item, in: library, order: order)
            }
        }
    }

    private var showsAllTypes: Binding<Bool> {
        Binding { browser.sidebarShowsAllTypes } set: { browser.sidebarShowsAllTypes = $0 }
    }

    var body: some View {
        let plan = SidebarPlan(library, layout: libraries.sidebarLayout)
        let folding = SidebarFolding(library: library, libraries: libraries, browser: browser, order: order)
        List(selection: selection) {
            Section {
                actionRow(String(localized: "New"), symbol: "square.and.pencil", identifier: "SidebarNew") {
                    browser.openQuickAdd(remembered: lastType, in: library)
                }
                .disabled(!QuickAdd.isAvailable(in: library))
                actionRow(String(localized: "Search"), symbol: "magnifyingglass", identifier: "SidebarSearch") {
                    browser.palette = .search
                }
                ForEach(plan.shownDestinations, id: \.key) { placeRow($0) }
            }
            if plan.showsViews { viewsSection(plan) }
            if plan.showsTypes {
                SidebarTypesSection(plan: plan, folding: folding, showsAll: showsAllTypes,choosingIcon: $choosingIcon)
            }
        }
        .listStyle(.sidebar)
        // The foot is a bar on the list's bottom edge, so the system draws its scroll edge effect there: nothing while
        // no row is beneath it, and the soft material once rows pass under.
        .safeAreaBar(edge: .bottom, spacing: 0) { SidebarFoot(browser: browser) }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .softSelection(rows: selectionRows(plan), selection: browser.sidebarItem)
        .accessibilityIdentifier("Sidebar")
        // The right and left arrows open and close the selected type, as the system's outline does for its own rows.
        .onKeyPress(.rightArrow, phases: [.down, .repeat]) { folding.press(.right, $0) }
        .onKeyPress(.leftArrow, phases: [.down, .repeat]) { folding.press(.left, $0) }
        .onChange(of: library.items(in: .favorites).map(\.id)) { browser.placeRemoved(in: library, order: order) }
        .onChange(of: library.views.map(\.id)) { browser.placeRemoved(in: library, order: order) }
        .sheet(item: $choosingIcon) { TypeIconPicker(request: $0, library: library) }
    }

    /// Everything the rows' look depends on, so the soft selection redraws when any of it changes.
    private func selectionRows(_ plan: SidebarPlan) -> [String] {
        plan.shownBuiltInViews.map(\.key) + plan.shownDestinations.map(\.key) + plan.shownLibrary.map(\.key)
            + libraries.sidebarLayout.collapsed.sorted() + libraries.sidebarLayout.hidden.sorted()
            + library.itemTypeCounts.map { $0.id.rawValue } + library.views.map(\.id.rawValue) + [String(browser.sidebarShowsAllTypes)]
    }

    // MARK: Rows

    /// A row that does something instead of opening a place, so it never takes the selection.
    private func actionRow(_ title: String, symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SidebarLabel(title: title, icon: .symbol(symbol)).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .accessibilityIdentifier(identifier)
    }

    /// One of the six places. Recents has no count since it always holds the same number, and the indexes list what
    /// the copy holds on their own.
    @ViewBuilder private func placeRow(_ place: SidebarPlace) -> some View {
        if let item = place.item, let symbol = place.symbol {
            let count = place.showsCount ? library.count(in: item) : 0
            SidebarLabel(title: library.name(of: item), icon: .symbol(symbol))
                .badge(count > 0 ? Text(count, format: .number).monospacedDigit() : nil)
                .tag(item)
                .contextMenu { SidebarHideButtons(place: place) }
                .accessibilityIdentifier("SidebarPlace-\(place.key)")
        }
    }

    /// One block under the Views heading: the built-in views, then the saved ones, which the person can rename, hide
    /// and reorder. The built-ins are places drawn here, not stored views. A saved view lists what the copy holds of
    /// its items, read on its own, so its row has no count.
    private func viewsSection(_ plan: SidebarPlan) -> some View {
        Section {
            ForEach(plan.shownBuiltInViews, id: \.key) { placeRow($0) }
            ForEach(plan.shownSavedViews) { view in
                SidebarLabel(title: view.title, icon: .symbol(SidebarPlace.viewSymbol))
                    .tag(SidebarItem.view(view.id))
                    .contextMenu {
                        SavedViewRowMenu(view: view.id, browser: browser)
                        Divider()
                        SidebarHideButtons(place: .view(view.id))
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

/// Hide from Sidebar for a row's context menu. A saved view's row hides that view alone, and offers the whole Views
/// block's saved views as well.
struct SidebarHideButtons: View {
    @Environment(Libraries.self) private var libraries
    let place: SidebarPlace

    var body: some View {
        Button("Hide from Sidebar") { libraries.updateSidebarLayout { $0.setHidden(place, true) } }
        if case .view = place {
            Button("Hide Views from Sidebar") { libraries.updateSidebarLayout { $0.setHidden(.views, true) } }
        }
    }
}
