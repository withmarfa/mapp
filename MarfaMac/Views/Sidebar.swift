import SwiftUI

/// The window's sidebar: Search and New, then the Library and the Feed, then Pinned, the Types and the person's own
/// sections, in tabs where there is more than one. A Control-click on the sidebar offers Customize Sidebar, which
/// arranges it in place (`Browser.customizesSidebar`); the foot holds the instance. Settings can draw it white.
struct Sidebar: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @AppStorage(SidebarColor.key) private var color = SidebarColor.gray
    let browser: Browser
    let order: ItemOrder

    /// Works out what the list draws once, from what the sidebar depends on and nothing else: the library's
    /// membership, its saved views and catalogue, the person's layout, and this window's tab and whether it is
    /// customizing. A click, a selection or an edit that moves none of them never runs it, and its parts are handed
    /// down as values, so a row whose own input is the same is not drawn again.
    var body: some View {
        let _ = Cost.record(.sidebarBody, since: .now)
        SidebarList(
            content: SidebarContent(
                library: library, layout: libraries.sidebarLayout, tab: browser.sidebarTab, customizing: browser.customizesSidebar),
            browser: browser, order: order)
            .sidebarColor(color)
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
    /// Every shown type row, folded open as the person left them, before the "N More" row cuts them short.
    let typeRows: [SidebarPlan.TypeRow]
    /// The types a plus under the pointer can make an item of, by identifier.
    let creatable: Set<String>
    /// Everything the rows' look depends on, so the soft selection redraws when any of it changes.
    let marksSignature: Int
    /// What the faint places of Customize Sidebar and a heading's Add offer.
    let offers: SidebarOffers

    /// The tabs show once there is a second, and always while customizing, so one can be added.
    var showsTabs: Bool { tabs.count > 1 || customizing }

    init(library: any ItemLibrary, layout: SidebarLayout, tab: String?, customizing: Bool) {
        let plan = SidebarPlan(library, layout: layout)
        self.plan = plan
        self.customizing = customizing
        tabs = plan.tabs
        self.tab = layout.tab(tab)
        canCreate = QuickAdd.isAvailable(in: library)
        typeRows = plan.typeRows
        creatable = Set(QuickAdd.types(in: library).map(\.id.rawValue))
        let creatable = creatable
        sections = plan.groups(in: self.tab.id, customizing: customizing).map { group in
            SidebarSectionData(
                plan: group, rows: group.shown.compactMap { Self.row($0, in: library, creatable: creatable) },
                shortcuts: group.group.shortcuts.compactMap { Self.shortcutRow($0, in: library, creatable: creatable) })
        }
        offers = SidebarOffers(library: library, plan: plan, creatable: creatable)
        var hasher = Hasher()
        hasher.combine(customizing)
        hasher.combine(self.tab.id)
        hasher.combine(tabs)
        hasher.combine(sections.map { [$0.id, $0.plan.group.name] + $0.rows.map(\.title) + $0.shortcuts.map(\.title) })
        hasher.combine(layout.collapsed.sorted() + layout.hidden.sorted())
        hasher.combine(plan.types.map(\.id))
        hasher.combine(plan.views.map(\.id))
        marksSignature = hasher.finalize()
    }

    /// A place as a row, or nil where what it names is gone.
    static func row(_ place: SidebarPlace, in library: any ItemLibrary, creatable: Set<String>) -> SidebarPlaceRowData? {
        let catalogue = library.catalogue
        switch place {
        case .library:
            return SidebarPlaceRowData(place: place, opens: .library, title: library.name(of: .library), mark: .symbol("square.grid.2x2"),
                                       count: library.count(in: .library))
        case .feed, .types, .collections, .sources:
            guard let opens = place.opens, let symbol = place.symbol else { return nil }
            return SidebarPlaceRowData(place: place, opens: opens, title: library.name(of: opens), mark: .symbol(symbol))
        case .view(let id):
            guard let view = library.views.first(where: { $0.id == id }) else { return nil }
            return SidebarPlaceRowData(place: place, opens: .saved(id), title: view.title, mark: .view(id))
        case .collection(let id):
            guard let item = library.item(id) else { return nil }
            return SidebarPlaceRowData(
                place: place, opens: .collection(id), title: item.displayTitle, mark: .grayType(catalogue.icon(for: item.type)),
                adds: true)
        case .source(let code):
            guard let info = library.sourceCounts.first(where: { $0.code == code }) else { return nil }
            return SidebarPlaceRowData(
                place: place, opens: .source(code), title: info.name, mark: .icon(SourceTile.icon(for: library.sources.info(code))))
        case .item(let id):
            guard let item = library.item(id) else { return nil }
            return SidebarPlaceRowData(place: place, opens: nil, title: item.displayTitle, mark: .icon(.type(catalogue.icon(for: item.type))))
        case .type:
            return nil
        }
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
            if case .type(let id) = place {
                guard library.catalogue.itemTypes[TypeID(id)] != nil else { return nil }
                return row(library.catalogue.plural(for: TypeID(id)), .type(library.catalogue.icon(for: TypeID(id))), opens: .type(TypeID(id)))
            }
            guard let data = Self.row(place, in: library, creatable: creatable), let opens = data.opens else { return nil }
            return row(data.title, data.menuIcon, opens: opens)
        }
    }
}

/// One section of the open tab as the list draws it.
nonisolated struct SidebarSectionData: Identifiable, Equatable {
    let plan: SidebarGroupPlan
    let rows: [SidebarPlaceRowData]
    let shortcuts: [SidebarShortcutRowData]

    var id: String { plan.id }
}

/// What a sidebar row draws before its name.
nonisolated enum SidebarMark: Equatable {
    /// A gray symbol.
    case symbol(String)
    /// A type's mark in its own color, or a source's.
    case icon(RowIcon)
    /// A collection's type mark, drawn gray, as a place's is.
    case grayType(String?)
    /// A saved view's mark, the symbol of its layout on this Mac (`SidebarViewMark`).
    case view(ItemID)
}

/// A place's row: its mark, its name, the count the row says, and whether a plus under the pointer makes an item in it.
nonisolated struct SidebarPlaceRowData: Equatable {
    let place: SidebarPlace
    /// What choosing the row opens; nil for a pinned item, which opens the item.
    let opens: PlaceView?
    let title: String
    let mark: SidebarMark
    /// The Library's count; nil for every other place.
    var count: Int?
    /// A collection's row offers a plus under the pointer.
    var adds = false

    /// The row's mark as a menu item or a shortcut draws it.
    @MainActor var menuIcon: RowIcon {
        switch mark {
        case .symbol(let name): .symbol(name)
        case .icon(let icon): icon
        case .grayType(let id): .type(id)
        case .view(let id): .symbol(SidebarPlace.symbol(ofView: id, in: ViewLayouts.stored()))
        }
    }
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
    @State private var choosingItem: SidebarItemRequest?
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
        let actions = SidebarActions(
            ask: { request in
                name = request.current
                naming = request
            },
            chooseItem: { choosingItem = SidebarItemRequest(group: $0) })
        List(selection: selection) {
            if content.customizing, !content.sections.contains(where: { $0.plan.group.kind == .shortcuts }) {
                Section {
                    SidebarAddPlace(group: nil, kind: .shortcuts, tab: content.tab.id, offers: content.offers, actions: actions)
                }
            }
            ForEach(content.sections) { section in
                sectionView(section, folding: folding, actions: actions)
            }
            if content.customizing {
                Section {
                    SidebarAddPlace(group: nil, kind: .custom, tab: content.tab.id, offers: content.offers, actions: actions)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if content.showsTabs {
                SidebarTabBar(tabs: content.tabs, chosen: content.tab.id, customizing: content.customizing, browser: browser)
            }
        }
        // The foot is a bar on the list's bottom edge that draws the toolbar's band mirrored, and only while rows pass
        // under it. The system's soft edge is hidden, since the list's own background would count as content.
        .bandsFoot(memory: browser.sidebarMemory) {
            if content.customizing {
                SidebarDoneBar(browser: browser)
            } else {
                SidebarFoot(browser: browser, order: order)
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
        .sheet(item: $choosingItem) { request in
            SidebarItemChooser { id in
                // A collection chosen as an item is pinned as the collection, so it has one row.
                let place: SidebarPlace = library.collections.contains { $0.id == id } ? .collection(id) : .item(id)
                libraries.updateSidebarLayout { $0.put(place, in: request.group) }
            }
        }
        .namingAlert($naming, name: $name) { request, name in
            libraries.updateSidebarLayout { request.apply(name: name, to: &$0) }
        }
    }

    @ViewBuilder private func sectionView(_ section: SidebarSectionData, folding: SidebarFolding, actions: SidebarActions) -> some View {
        let headed = content.sections.filter { $0.plan.group.hasHeading }
        let position = headed.firstIndex { $0.id == section.id }
        let header = SidebarGroupHeader(
            section: section, tabs: content.tabs, tab: content.tab.id, customizing: content.customizing, offers: content.offers,
            browser: browser, isFirst: position == 0, isLast: position == headed.count - 1, actions: actions)
        switch section.plan.group.kind {
        case .shortcuts:
            SidebarShortcutsSection(
                section: section, tab: content.tab.id, canCreate: content.canCreate, customizing: content.customizing,
                addsShortcuts: content.sections.first { $0.plan.group.kind == .shortcuts }?.id == section.id, offers: content.offers,
                actions: actions, browser: browser, order: order)
        case .types:
            SidebarTypesSection(
                rows: content.typeRows, plan: content.plan, showsAll: browser.sidebarShowsAllTypes, open: openType,
                customizing: content.customizing,
                creatable: content.creatable, folding: folding, browser: browser, choosingIcon: $choosingIcon, header: header,
                place: SidebarAddPlace(group: section.id, kind: .types, tab: content.tab.id, offers: content.offers, actions: actions))
        case .places, .pinned, .custom:
            SidebarPlacesSection(
                section: section, groups: groupChoices(excluding: section.id), customizing: content.customizing, browser: browser,
                order: order, header: section.plan.group.hasHeading ? header : nil,
                place: SidebarAddPlace(
                    group: section.id, kind: section.plan.group.kind, tab: content.tab.id, offers: content.offers, actions: actions,
                    name: section.plan.group.name))
        }
    }

    /// The type the window shows, if it shows one.
    private var openType: TypeID? {
        if case .type(let type)? = browser.showing?.place { type } else { nil }
    }

    /// The sections a row can move to, apart from the one it is in.
    private func groupChoices(excluding id: String) -> [SidebarGroupChoice] {
        content.plan.groups.filter { $0.group.holdsPlaces && !content.plan.layout.hides($0.group) && $0.id != id }
            .map { SidebarGroupChoice(id: $0.id, name: $0.group.name, kind: $0.group.kind) }
    }
}

/// What a row or a place asks of the list: a name, or an item to pin.
struct SidebarActions {
    let ask: (SidebarNaming) -> Void
    /// Opens the chooser that pins an item in the section with this identifier.
    let chooseItem: (String) -> Void
}

/// The chooser of an item to pin, and the section it goes in.
struct SidebarItemRequest: Identifiable {
    let group: String
    var id: String { group }
}

/// What the alert that names a section is for. A tab is named in place, in the tab bar.
enum SidebarNaming: Identifiable, Equatable {
    case renameGroup(String, current: String)

    var id: String {
        switch self {
        case .renameGroup(let id, _): "group:" + id
        }
    }

    var current: String {
        switch self {
        case .renameGroup(_, let name): name
        }
    }

    func apply(name: String, to layout: inout SidebarLayout) {
        switch self {
        case .renameGroup(let id, _): layout.renameGroup(id, to: name)
        }
    }
}

extension View {
    /// The alert that names a section, for the sidebar.
    func namingAlert(_ naming: Binding<SidebarNaming?>, name: Binding<String>, apply: @escaping (SidebarNaming, String) -> Void) -> some View {
        alert("Rename Section", isPresented: Binding { naming.wrappedValue != nil } set: { if !$0 { naming.wrappedValue = nil } },
              presenting: naming.wrappedValue) { request in
            TextField("Name", text: name)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { apply(request, name.wrappedValue) }
        }
    }
}

/// A section a row can move to.
struct SidebarGroupChoice: Equatable, Identifiable {
    let id: String
    let name: String
    let kind: SidebarGroup.Kind
}

/// Done, at the foot while the sidebar is being customized, in place of the instance.
struct SidebarDoneBar: View {
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
