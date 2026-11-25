import SwiftUI

/// The window's sidebar, in the manner of the Claude desktop app: tabs (none shown while there is one), and in each tab the
/// person's sections, which start as New and Search, the Library, the Views and the Types. A Control-click on the sidebar
/// offers Customize Sidebar, which arranges it in place (`Browser.customizesSidebar`); the foot holds the instance.
struct Sidebar: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    /// The places' kept choices, for the From whose favorites the Favorites row counts.
    @AppStorage(PlaceDefaults.key) private var placeDefaults: Data?
    let browser: Browser
    let order: ItemOrder

    /// Works out what the list draws once, from what the sidebar depends on and nothing else: the library's
    /// membership, its saved views and catalogue, the person's layout, the places' kept choices (for the Favorites
    /// view's From), and this window's tab and whether it is customizing. A click, a selection or an edit that moves
    /// none of them never runs it, and its parts are handed down as values, so a row whose own input is the same is not
    /// drawn again.
    var body: some View {
        let _ = Cost.record(.sidebarBody, since: .now)
        SidebarList(
            content: SidebarContent(
                library: library, layout: libraries.sidebarLayout, tab: browser.sidebarTab, customizing: browser.customizesSidebar,
                favoritesScope: PlaceDefaults.favoritesScope(in: placeDefaults)),
            browser: browser, order: order)
    }
}

/// What the sidebar's list draws, worked out from the library and the person's layout.
struct SidebarContent {
    let plan: SidebarPlan
    let tabs: [SidebarTab]
    let tab: SidebarTab
    let customizing: Bool
    let canCreate: Bool
    /// The sections of the open tab that show: all of them while customizing, otherwise those with something in them.
    let sections: [SidebarSectionData]
    /// Every shown type row, folded open as the person left them, before Show More cuts them short.
    let typeRows: [SidebarPlan.TypeRow]
    /// Everything the rows' look depends on, so the soft selection redraws when any of it changes.
    let marksSignature: Int
    /// What Add Shortcut and Add Section offer; empty unless customizing.
    let choices: SidebarChoices
    /// The built-in sections hidden from the tab, which Add Section brings back.
    let hiddenKinds: [SidebarGroup.Kind]

    var showsTabs: Bool { tabs.count > 1 }

    init(library: any ItemLibrary, layout: SidebarLayout, tab: String?, customizing: Bool, favoritesScope: ListScope = .library) {
        let plan = SidebarPlan(library, layout: layout)
        self.plan = plan
        self.customizing = customizing
        tabs = plan.tabs
        self.tab = layout.tab(tab)
        canCreate = QuickAdd.isAvailable(in: library)
        typeRows = plan.typeRows
        let creatable = Set(QuickAdd.types(in: library).map(\.id.rawValue))
        func row(_ place: SidebarPlace) -> SidebarPlaceRowData? {
            guard let item = place.opens, let symbol = place.symbol else { return nil }
            return SidebarPlaceRowData(
                place: place, item: item, title: library.name(of: item), symbol: symbol,
                count: place.showsCount ? library.count(in: item, favoritesScope: favoritesScope) : 0, tone: place.defaultTone == nil ? nil : layout.color(of: place))
        }
        sections = plan.groups(in: self.tab.id, customizing: customizing).map { group in
            SidebarSectionData(
                plan: group, rows: group.shown.compactMap(row),
                choices: customizing ? Self.showChoices(of: group, in: library, plan: plan) : [],
                shortcuts: group.group.shortcuts.compactMap { Self.shortcutRow($0, in: library, creatable: creatable) })
        }
        hiddenKinds = customizing
            ? plan.groups.filter { layout.hides($0.group) && [.library, .views, .types].contains($0.group.kind) }.map(\.group.kind)
            : []
        choices = customizing ? Self.choices(in: library, plan: plan, layout: layout) : SidebarChoices()
        var hasher = Hasher()
        hasher.combine(customizing)
        hasher.combine(self.tab.id)
        hasher.combine(tabs)
        hasher.combine(sections.map { [$0.id, $0.plan.group.name] + $0.rows.map(\.title) + $0.shortcuts.map(\.title) })
        hasher.combine(sections.flatMap(\.rows).map { $0.tone?.rawValue ?? "" })
        hasher.combine(layout.collapsed.sorted() + layout.hidden.sorted())
        hasher.combine(plan.types.map(\.id))
        hasher.combine(plan.views.map(\.id))
        marksSignature = hasher.finalize()
    }

    /// What a section's Show list offers, shown or not: its places, and for Views the saved views as a whole. Types lists
    /// the top-level rows, and the subtypes hidden by their own row's Hide from Sidebar, which only Show can bring back.
    static func showChoices(of group: SidebarGroupPlan, in library: any ItemLibrary, plan: SidebarPlan) -> [SidebarShowChoice] {
        let layout = plan.layout
        switch group.group.kind {
        case .shortcuts: return []
        case .types:
            func hiddenSubtypes(of node: TypeNode) -> [SidebarShowChoice] {
                node.children.flatMap { child in
                    let own = layout.isHidden(.type(child.id))
                        ? [SidebarShowChoice(place: .type(child.id), title: String(localized: "\(node.label) > \(child.label)"), isShown: false)]
                        : []
                    return own + hiddenSubtypes(of: child)
                }
            }
            return plan.types.flatMap { node in
                [SidebarShowChoice(place: .type(node.id), title: node.label, isShown: !layout.isHidden(.type(node.id)))]
                    + hiddenSubtypes(of: node)
            }
        case .views, .library, .custom:
            let saved = group.group.kind == .views
                ? [SidebarShowChoice(place: .views, title: String(localized: "Saved Views"), isShown: !layout.isHidden(.views))] : []
            return saved + group.members.compactMap { place in
                place.opens.map { SidebarShowChoice(place: place, title: library.name(of: $0), isShown: !layout.isHidden(place)) }
            }
        }
    }

    /// The views, types, collections and sources a shortcut or a new section can name.
    static func choices(in library: any ItemLibrary, plan: SidebarPlan, layout: SidebarLayout) -> SidebarChoices {
        let catalogue = library.catalogue
        func types(_ ids: [TypeID]) -> [SidebarPick] {
            ids.map { SidebarPick(key: SidebarPlace.type($0.rawValue).key, title: catalogue.plural(for: $0)) }
        }
        let collections = library.collections.map { SidebarPick(key: SidebarPlace.collection($0.id).key, title: $0.displayTitle) }
        let sources = library.sourceCounts.map { SidebarPick(key: SidebarPlace.source($0.code).key, title: $0.name) }
        // A collection or a source has a row only where it was put, in a section that is still there, so only one with
        // no home can be added to a new section. Going to one is always possible, placed or not.
        func unplaced(_ picks: [SidebarPick]) -> [SidebarPick] {
            picks.filter { pick in SidebarPlace(key: pick.key).map { layout.home(of: $0) == nil } ?? false }
        }
        return SidebarChoices(
            views: plan.views.map { SidebarPick(key: SidebarPlace.view($0.id).key, title: $0.title) },
            types: types(QuickAdd.typeIDs(of: plan.types)),
            collections: collections, sources: sources,
            unplacedCollections: unplaced(collections), unplacedSources: unplaced(sources),
            creatable: QuickAdd.types(in: library).map { SidebarPick(key: $0.id.rawValue, title: $0.label) })
    }

    /// A shortcut as a row, or nil where what it names is gone: a type or collection deleted, or a view that left
    /// the library. The layout keeps the shortcut, so it returns with what it names.
    static func shortcutRow(
        _ shortcut: SidebarShortcut, in library: any ItemLibrary, creatable: Set<String>
    ) -> SidebarShortcutRowData? {
        func row(_ title: String, _ icon: RowIcon, opens item: PlaceView? = nil) -> SidebarShortcutRowData {
            SidebarShortcutRowData(shortcut: shortcut, title: title, icon: icon, item: item)
        }
        switch shortcut {
        case .new: return row(String(localized: "New"), .symbol("square.and.pencil"))
        case .search: return row(String(localized: "Search"), .symbol("magnifyingglass"))
        case .settings: return row(String(localized: "Settings"), .symbol("gearshape"))
        case .create(let type):
            guard creatable.contains(type) else { return nil }
            let catalogue = library.catalogue
            return row(String(localized: "New \(catalogue.label(for: TypeID(type)))"), .type(catalogue.icon(for: TypeID(type))))
        case .go(let key):
            guard let place = SidebarPlace(key: key) else { return nil }
            switch place {
            case .type(let id):
                guard library.catalogue.itemTypes[TypeID(id)] != nil else { return nil }
                return row(library.catalogue.plural(for: TypeID(id)), .type(library.catalogue.icon(for: TypeID(id))), opens: .type(TypeID(id)))
            case .view(let id):
                guard library.views.contains(where: { $0.id == id }) else { return nil }
                return row(library.name(of: .saved(id)), .symbol(SidebarPlace.viewSymbol), opens: .saved(id))
            case .collection(let id):
                guard library.collections.contains(where: { $0.id == id }) else { return nil }
                return row(library.name(of: .collection(id)), .symbol(place.symbol ?? "square.stack"), opens: .collection(id))
            default:
                guard let item = place.opens, let symbol = place.symbol else { return nil }
                return row(library.name(of: item), .symbol(symbol), opens: item)
            }
        }
    }
}

/// One section of the open tab as the list draws it.
nonisolated struct SidebarSectionData: Identifiable, Equatable {
    let plan: SidebarGroupPlan
    let rows: [SidebarPlaceRowData]
    /// What the section's Show list offers; empty unless customizing.
    let choices: [SidebarShowChoice]
    let shortcuts: [SidebarShortcutRowData]

    var id: String { plan.id }
}

/// A place's row: its mark, its name and the count the row says, if any.
nonisolated struct SidebarPlaceRowData: Equatable {
    let place: SidebarPlace
    /// What choosing the row opens.
    let item: PlaceView
    let title: String
    let symbol: String
    let count: Int
    /// The color of a view's mark; nil for a place whose mark is gray.
    let tone: TypeTone?
}

/// A shortcut's row. It does something or goes somewhere, so it never takes the selection.
nonisolated struct SidebarShortcutRowData: Equatable, Identifiable {
    let shortcut: SidebarShortcut
    let title: String
    let icon: RowIcon
    /// Where it goes, for a shortcut that opens a place.
    let item: PlaceView?

    var id: String { shortcut.key }
}

/// The list itself. It reads the selection and nothing else that changes as a person clicks, so a click runs only
/// this body, which builds the rows from values they compare, and the rows stay as they are.
private struct SidebarList: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @State private var choosingIcon: TypeIconRequest?
    @State private var naming: SidebarNaming?
    @State private var name = ""
    let content: SidebarContent
    let browser: Browser
    let order: ItemOrder

    /// Empty clicks leave the destination intact. While customizing, a click chooses nothing.
    private var selection: Binding<PlaceView?> {
        // A row names a saved view at the Library (`PlaceView.memoryKey`), wherever its home is.
        Binding {
            browser.showing?.memoryKey
        } set: { item in
            guard let item, !browser.customizesSidebar else { return }
            if !item.isSame(browser.showing) { browser.show(item, in: library, order: order) }
        }
    }

    var body: some View {
        let plan = content.plan
        let folding = SidebarFolding(library: library, libraries: libraries, browser: browser, order: order, plan: plan)
        let ask: (SidebarNaming) -> Void = { request in
            name = request.current
            naming = request
        }
        List(selection: selection) {
            if content.customizing, !content.sections.contains(where: { $0.plan.group.kind == .shortcuts }) {
                Section {
                    SidebarAddShortcutRow(tab: content.tab.id, present: [], choices: content.choices)
                }
            }
            ForEach(content.sections) { section in
                sectionView(section, folding: folding, ask: ask)
            }
            if content.customizing {
                Section {
                    SidebarAddSectionRow(tab: content.tab.id, hiddenKinds: content.hiddenKinds, choices: content.choices)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if content.showsTabs {
                SidebarTabBar(tabs: content.tabs, chosen: content.tab.id, browser: browser, ask: ask)
            }
        }
        // The foot is a bar on the list's bottom edge that draws the toolbar's band mirrored, and only while rows pass
        // under it. The system's soft edge is hidden, since the list's own background would count as content.
        .bandsFoot(memory: browser.sidebarMemory) {
            if content.customizing {
                SidebarDoneBar(browser: browser)
            } else {
                SidebarFoot(browser: browser)
            }
        }
        // The window mounts this list afresh when its presentation changes, so it starts where the last one was.
        .remembersScroll(in: browser.sidebarMemory)
        .softSelection(rows: [content.marksSignature, browser.sidebarShowsAllTypes ? 1 : 0], selection: { browser.showing?.memoryKey })
        .contextMenu { if !content.customizing { SidebarCustomizeButton(browser: browser) } }
        .accessibilityIdentifier("Sidebar")
        // The right and left arrows open and close the selected type, as the system's outline does for its own rows.
        .onKeyPress(.rightArrow, phases: [.down, .repeat]) { folding.press(.right, $0) }
        .onKeyPress(.leftArrow, phases: [.down, .repeat]) { folding.press(.left, $0) }
        .sheet(item: $choosingIcon) { TypeIconPicker(request: $0, library: library) }
        .namingAlert($naming, name: $name) { apply($0, name: $1) }
    }

    @ViewBuilder private func sectionView(_ section: SidebarSectionData, folding: SidebarFolding, ask: @escaping (SidebarNaming) -> Void) -> some View {
        let shown = content.sections.filter { $0.plan.group.kind != .shortcuts }
        let position = shown.firstIndex { $0.id == section.id }
        let header = SidebarGroupHeader(
            section: section, tabs: content.tabs, tab: content.tab.id, customizing: content.customizing, browser: browser,
            isFirst: position == 0, isLast: position == shown.count - 1, ask: ask)
        switch section.plan.group.kind {
        case .shortcuts:
            SidebarShortcutsSection(
                section: section, tab: content.tab.id, canCreate: content.canCreate, customizing: content.customizing,
                addsShortcuts: content.sections.first { $0.plan.group.kind == .shortcuts }?.id == section.id, choices: content.choices,
                browser: browser, order: order)
        case .types:
            SidebarTypesSection(
                rows: content.typeRows, plan: content.plan, showsAll: browser.sidebarShowsAllTypes, customizing: content.customizing,
                folding: folding, browser: browser, choosingIcon: $choosingIcon, header: header)
        case .library, .views, .custom:
            SidebarPlacesSection(
                section: section, groups: groupChoices(excluding: section.id), customizing: content.customizing, browser: browser,
                header: header)
        }
    }

    /// The sections a row can move to, apart from the one it is in.
    private func groupChoices(excluding id: String) -> [SidebarGroupChoice] {
        content.plan.groups.filter { $0.group.holdsPlaces && !$0.group.isHidden && $0.id != id }
            .map { SidebarGroupChoice(id: $0.id, name: $0.group.name) }
    }

    private func apply(_ request: SidebarNaming, name: String) {
        var created: String?
        libraries.updateSidebarLayout { created = request.apply(name: name, to: &$0) }
        if let created { browser.sidebarTab = created }
    }
}

/// What the alert that names a tab or a section is for.
enum SidebarNaming: Identifiable, Equatable {
    /// A new tab, with the section to move into it, where it was made from a section's menu.
    case newTab(moving: String?)
    case renameTab(String, current: String)
    case renameGroup(String, current: String)

    var id: String {
        switch self {
        case .newTab(let moving): "new:" + (moving ?? "")
        case .renameTab(let id, _): "tab:" + id
        case .renameGroup(let id, _): "group:" + id
        }
    }

    var current: String {
        switch self {
        case .newTab: ""
        case .renameTab(_, let name), .renameGroup(_, let name): name
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .newTab: "New Tab"
        case .renameTab: "Rename Tab"
        case .renameGroup: "Rename Section"
        }
    }

    /// Makes the change the person named, returning the identifier of the tab it made.
    @discardableResult
    func apply(name: String, to layout: inout SidebarLayout) -> String? {
        switch self {
        case .newTab(let moving):
            let created = layout.addTab(named: name)
            if let moving { layout.moveGroup(moving, toTab: created) }
            return created
        case .renameTab(let id, _):
            layout.renameTab(id, to: name)
        case .renameGroup(let id, _):
            layout.renameGroup(id, to: name)
        }
        return nil
    }

    var confirmation: LocalizedStringKey {
        switch self {
        case .newTab: "Add"
        case .renameTab, .renameGroup: "Rename"
        }
    }
}

extension View {
    /// The alert that names a tab or a section, for the sidebar.
    func namingAlert(_ naming: Binding<SidebarNaming?>, name: Binding<String>, apply: @escaping (SidebarNaming, String) -> Void) -> some View {
        alert(naming.wrappedValue?.title ?? "", isPresented: Binding { naming.wrappedValue != nil } set: { if !$0 { naming.wrappedValue = nil } },
              presenting: naming.wrappedValue) { request in
            TextField("Name", text: name)
            Button("Cancel", role: .cancel) {}
            Button(request.confirmation) { apply(request, name.wrappedValue) }
        }
    }
}

/// A section a row can move to.
struct SidebarGroupChoice: Equatable, Identifiable {
    let id: String
    let name: String
}

/// Done, at the foot while the sidebar is being customized, in place of the instance.
private struct SidebarDoneBar: View {
    let browser: Browser

    var body: some View {
        Button { browser.customizesSidebar = false } label: {
            Text("Done").frame(maxWidth: .infinity)
        }
        .appButton(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityIdentifier("SidebarDone")
    }
}

/// Customize Sidebar, in the menu of the sidebar and of every row and heading in it.
struct SidebarCustomizeButton: View {
    let browser: Browser

    var body: some View {
        Button("Customize Sidebar…") { browser.customizesSidebar = true }
            .disabled(browser.customizesSidebar)
    }
}

/// Hide from Sidebar for a row's context menu. A saved view's row hides that view alone, and offers the whole Views
/// block's saved views as well.
struct SidebarHideButtons: View {
    @Environment(Libraries.self) private var libraries
    let place: SidebarPlace

    var body: some View {
        Button("Hide from Sidebar") { libraries.updateSidebarLayout { $0.take(place) } }
        if case .view = place {
            Button("Hide Views from Sidebar") { libraries.updateSidebarLayout { $0.setHidden(.views, true) } }
        }
    }
}
