import SwiftUI

/// The window's sidebar, in the manner of the Claude desktop app: New and Search act, then Items, Sources and
/// Collections open. The Views block follows, holding Inbox, Recents and Favorites and then the saved views, and the
/// Types block after it. Settings > Sidebar switches each place on or off, and the foot holds the instance.
struct Sidebar: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    let browser: Browser
    let order: NoteOrder

    /// Works out what the list draws once, from what the sidebar depends on and nothing else: the library's
    /// membership, its saved views and catalogue, and the person's layout. A click, a selection or an edit that
    /// moves none of them never runs it, and its parts are handed down as values, so a row whose own input is the
    /// same is not drawn again.
    var body: some View {
        let _ = Cost.record(.sidebarBody, since: .now)
        SidebarList(content: SidebarContent(library: library, layout: libraries.sidebarLayout), browser: browser, order: order)
    }
}

/// What the sidebar's list draws, worked out from the library and the person's layout.
struct SidebarContent {
    let plan: SidebarPlan
    let canCreate: Bool
    let destinations: [SidebarPlaceRowData]
    let builtInViews: [SidebarPlaceRowData]
    /// Every shown type row, folded open as the person left them, before Show More cuts them short.
    let typeRows: [SidebarPlan.TypeRow]
    /// Everything the rows' look depends on, so the soft selection redraws when any of it changes.
    let marksSignature: Int

    init(library: any ItemLibrary, layout: SidebarLayout) {
        let plan = SidebarPlan(library, layout: layout)
        self.plan = plan
        canCreate = QuickAdd.isAvailable(in: library)
        func row(_ place: SidebarPlace) -> SidebarPlaceRowData? {
            guard let item = place.item, let symbol = place.symbol else { return nil }
            return SidebarPlaceRowData(
                place: place, item: item, title: library.name(of: item), symbol: symbol, count: place.showsCount ? library.count(in: item) : 0)
        }
        destinations = plan.shownDestinations.compactMap(row)
        builtInViews = plan.shownBuiltInViews.compactMap(row)
        typeRows = plan.typeRows
        var hasher = Hasher()
        hasher.combine(plan.shownBuiltInViews.map(\.key) + plan.shownDestinations.map(\.key) + plan.shownLibrary.map(\.key))
        hasher.combine(layout.collapsed.sorted() + layout.hidden.sorted())
        hasher.combine(plan.types.map(\.id))
        hasher.combine(plan.views.map(\.id))
        marksSignature = hasher.finalize()
    }
}

/// A place's row: its mark, its name and the count the row says, if any.
nonisolated struct SidebarPlaceRowData: Equatable {
    let place: SidebarPlace
    /// What choosing the row opens.
    let item: SidebarItem
    let title: String
    let symbol: String
    let count: Int
}

/// The list itself. It reads the selection and nothing else that changes as a person clicks, so a click runs only
/// this body, which builds the rows from values they compare, and the rows stay as they are.
private struct SidebarList: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @State private var choosingIcon: TypeIconRequest?
    let content: SidebarContent
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

    var body: some View {
        let plan = content.plan
        let folding = SidebarFolding(library: library, libraries: libraries, browser: browser, order: order, plan: plan)
        List(selection: selection) {
            SidebarTopSection(canCreate: content.canCreate, destinations: content.destinations, browser: browser)
            if plan.showsViews {
                SidebarViewsSection(builtIn: content.builtInViews, plan: plan, browser: browser)
            }
            if plan.showsTypes {
                SidebarTypesSection(rows: content.typeRows, showsAll: browser.sidebarShowsAllTypes, folding: folding, browser: browser, choosingIcon: $choosingIcon)
            }
        }
        .listStyle(.sidebar)
        // The foot is a bar on the list's bottom edge that draws the toolbar's band mirrored, and only while rows pass
        // under it. The system's soft edge is hidden, since the list's own background would count as content.
        .bandsFoot(memory: browser.sidebarMemory) { SidebarFoot(browser: browser) }
        // The window mounts this list afresh when its presentation changes, so it starts where the last one was.
        .remembersScroll(in: browser.sidebarMemory)
        .softSelection(rows: [content.marksSignature, browser.sidebarShowsAllTypes ? 1 : 0], selection: browser.sidebarItem)
        .accessibilityIdentifier("Sidebar")
        // The right and left arrows open and close the selected type, as the system's outline does for its own rows.
        .onKeyPress(.rightArrow, phases: [.down, .repeat]) { folding.press(.right, $0) }
        .onKeyPress(.leftArrow, phases: [.down, .repeat]) { folding.press(.left, $0) }
        .sheet(item: $choosingIcon) { TypeIconPicker(request: $0, library: library) }
    }
}

/// New and Search act, then Items, Sources and Collections open.
private struct SidebarTopSection: View, Equatable {
    @CurrentLibrary private var library
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    let canCreate: Bool
    let destinations: [SidebarPlaceRowData]
    let browser: Browser

    static func == (a: Self, b: Self) -> Bool { a.canCreate == b.canCreate && a.destinations == b.destinations }

    var body: some View {
        Section {
            SidebarActionRow(title: String(localized: "New"), symbol: "square.and.pencil", identifier: "SidebarNew") {
                browser.openQuickAdd(remembered: lastType, in: library)
            }
            .disabled(!canCreate)
            SidebarActionRow(title: String(localized: "Search"), symbol: "magnifyingglass", identifier: "SidebarSearch") {
                browser.palette = .search
            }
            ForEach(destinations, id: \.place.key) { data in
                SidebarPlaceRow(data: data).tag(data.item)
            }
        }
    }
}

/// A row that does something instead of opening a place, so it never takes the selection.
private struct SidebarActionRow: View {
    let title: String
    let symbol: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // The label is only as wide as its words; the frame gives the click the whole row.
            SidebarLabel(title: title, icon: .symbol(symbol))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .accessibilityIdentifier(identifier)
    }
}

/// One of the six places. Recents has no count since it always holds the same number, and the indexes list what
/// the copy holds on their own.
private struct SidebarPlaceRow: View, Equatable {
    let data: SidebarPlaceRowData

    var body: some View {
        SidebarLabel(title: data.title, icon: .symbol(data.symbol))
            .badge(data.count > 0 ? Text(data.count, format: .number).monospacedDigit() : nil)
            .contextMenu { SidebarHideButtons(place: data.place) }
            .accessibilityIdentifier("SidebarPlace-\(data.place.key)")
    }
}

/// One block under the Views heading: the built-in views, then the saved ones, which the person can rename, hide
/// and reorder. The built-ins are places drawn here, not stored views. A saved view lists what the copy holds of
/// its items, read on its own, so its row has no count.
private struct SidebarViewsSection: View, Equatable {
    @Environment(Libraries.self) private var libraries
    let builtIn: [SidebarPlaceRowData]
    let plan: SidebarPlan
    let browser: Browser

    static func == (a: Self, b: Self) -> Bool {
        a.builtIn == b.builtIn && a.plan.views == b.plan.views && a.plan.shownSavedViews == b.plan.shownSavedViews
            && a.plan.shownViews == b.plan.shownViews
    }

    var body: some View {
        Section {
            ForEach(builtIn, id: \.place.key) { data in
                SidebarPlaceRow(data: data).tag(data.item)
            }
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
