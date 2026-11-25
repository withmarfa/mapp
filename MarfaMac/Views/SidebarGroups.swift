import SwiftUI
import UniformTypeIdentifiers

// MARK: Dragging

/// A section as it is dragged by its handle, which is all a drop on another section's heading reads.
nonisolated struct SidebarSectionDrag: Codable, Transferable {
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .marfaSidebarSection)
    }
}

extension UTType {
    /// Named for the bundle identifier, as `MarfaMac/Info.plist` declares it, so a section never drags into the other build.
    nonisolated static let marfaSidebarSection = UTType(exportedAs: "\(AppPaths.bundleIdentifier).sidebar-section")
}

/// The mark at the trailing edge of a row and a section while the sidebar is being customized: it says the row can be
/// dragged.
struct SidebarHandle: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

// MARK: Headings

/// A section's heading. Under the pointer it shows Add, which offers what the section can hold, and More, the
/// section's menu; while customizing it shows More and a handle that drags the section. Nothing in the heading moves.
struct SidebarGroupHeader: View, Equatable {
    @Environment(Libraries.self) private var libraries
    @State private var isHovering = false
    let section: SidebarSectionData
    let tabs: [SidebarTab]
    let tab: String
    let customizing: Bool
    let offers: SidebarOffers
    let browser: Browser
    let isFirst: Bool
    let isLast: Bool
    let actions: SidebarActions

    static func == (a: Self, b: Self) -> Bool {
        a.section == b.section && a.tabs == b.tabs && a.tab == b.tab && a.customizing == b.customizing && a.offers == b.offers
            && a.isFirst == b.isFirst && a.isLast == b.isLast
    }

    var body: some View {
        let group = section.plan.group
        HStack(spacing: 10) {
            Text(group.name)
            Spacer(minLength: 0)
            if customizing {
                more
                SidebarHandle().draggable(SidebarSectionDrag(id: group.id))
            } else {
                add.opacity(isHovering ? 1 : 0)
                more.opacity(isHovering ? 1 : 0)
            }
        }
        .padding(.trailing, 12)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .dropDestination(for: SidebarSectionDrag.self) { drops, _ in
            guard customizing, let drop = drops.first else { return false }
            libraries.updateSidebarLayout { $0.moveGroup(drop.id, onto: group.id) }
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(group.name))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("SidebarHeading-\(group.id)")
    }

    private var add: some View {
        let group = section.plan.group
        return Menu {
            SidebarOfferMenu(group: group.id, kind: group.kind, tab: tab, offers: offers, actions: actions, name: group.name)
        } label: {
            Image(systemName: "plus")
        }
        .headingButton()
        .accessibilityLabel(Text("Add to \(group.name)"))
        .accessibilityIdentifier("SidebarSectionAdd-\(group.id)")
    }

    private var more: some View {
        let group = section.plan.group
        return Menu {
            Button("Rename…") { actions.ask(.renameGroup(group.id, current: group.name)) }
            Divider()
            Button("Move Up") { libraries.updateSidebarLayout { $0.moveGroup(group.id, by: -1) } }
                .disabled(isFirst)
            Button("Move Down") { libraries.updateSidebarLayout { $0.moveGroup(group.id, by: 1) } }
                .disabled(isLast)
            Menu("Move to Tab") {
                ForEach(tabs.filter { $0.id != tab }) { other in
                    Button(other.name) { libraries.updateSidebarLayout { $0.moveGroup(group.id, toTab: other.id) } }
                }
                if tabs.count > 1 { Divider() }
                Button("New Tab") {
                    var created: String?
                    libraries.updateSidebarLayout { layout in
                        created = layout.addTab(named: "")
                        if let created { layout.moveGroup(group.id, toTab: created) }
                    }
                    if let created { browser.sidebarTab = created }
                }
            }
            Divider()
            Button("Hide Section") { libraries.updateSidebarLayout { $0.hideGroup(group.id) } }
            if !customizing {
                Divider()
                SidebarCustomizeButton(browser: browser)
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .headingButton()
        .accessibilityLabel(Text("Section Options"))
        .accessibilityIdentifier("SidebarSectionMenu-\(group.id)")
    }
}

private extension View {
    /// A heading's Add or More: a borderless menu as small as its symbol.
    func headingButton() -> some View {
        menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}

// MARK: Commands

/// Search, New and the other commands: rows that act or go somewhere, never taking the selection. Under the pointer
/// Search and New show their shortcuts. While customizing each has a handle and a context menu that removes it, and the
/// Command place follows.
struct SidebarShortcutsSection: View, Equatable {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Environment(ShortcutBindings.self) private var bindings: ShortcutBindings?
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    let section: SidebarSectionData
    let tab: String
    let canCreate: Bool
    let customizing: Bool
    let addsShortcuts: Bool
    let offers: SidebarOffers
    let actions: SidebarActions
    let browser: Browser
    let order: ItemOrder

    /// The section's data and nothing else, so a change of selection does not run its body.
    static func == (a: Self, b: Self) -> Bool {
        a.section == b.section && a.tab == b.tab && a.canCreate == b.canCreate && a.customizing == b.customizing
            && a.addsShortcuts == b.addsShortcuts && a.offers == b.offers && a.order == b.order
    }

    var body: some View {
        Section {
            ForEach(section.shortcuts) { data in
                SidebarShortcutRow(
                    data: data, keys: keys(for: data.shortcut), customizing: customizing,
                    isEnabled: !customizing && !((data.shortcut == .new || isCreate(data.shortcut)) && !canCreate)
                ) { perform(data) }
                .contextMenu {
                    Button("Remove from Sidebar") {
                        libraries.updateSidebarLayout { $0.removeShortcut(data.shortcut, from: section.id) }
                    }
                    Divider()
                    SidebarCustomizeButton(browser: browser)
                }
            }
            .onMove { source, destination in
                libraries.updateSidebarLayout { $0.moveShortcuts(in: section.id, fromOffsets: source, toOffset: destination) }
            }
            if customizing, addsShortcuts {
                SidebarAddPlace(group: section.id, kind: .shortcuts, tab: tab, offers: offers, actions: actions)
            }
        }
    }

    /// What a row shows under the pointer: the shortcut of the command it runs, where it has one.
    private func keys(for shortcut: SidebarShortcut) -> String? {
        switch shortcut {
        case .search: bindings?.display(for: .commandPalette)
        case .new: bindings?.display(for: .newItem)
        default: nil
        }
    }

    private func isCreate(_ shortcut: SidebarShortcut) -> Bool {
        if case .create = shortcut { true } else { false }
    }

    private func perform(_ data: SidebarShortcutRowData) {
        switch data.shortcut {
        case .new: browser.openQuickAdd(remembered: lastType, in: library)
        case .create(let type): browser.openQuickAdd(typeID: type, in: library)
        case .search: browser.palette = .commands
        case .settings: browser.showSettings()
        case .go:
            if let item = data.item { browser.show(item, in: library, order: order) }
        }
    }
}

/// One command's row. The label is only as wide as its words; the frame gives the click the whole row.
private struct SidebarShortcutRow: View {
    @State private var isHovering = false
    let data: SidebarShortcutRowData
    let keys: String?
    let customizing: Bool
    let isEnabled: Bool
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            HStack {
                SidebarLabel(title: data.title, icon: data.icon)
                Spacer(minLength: 0)
                if customizing {
                    SidebarHandle()
                } else if let keys {
                    Text(verbatim: keys).sidebarTrailing().opacity(isHovering ? 1 : 0).accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .accessibilityIdentifier(identifier)
    }

    private var identifier: String {
        switch data.shortcut {
        case .new: "SidebarNew"
        case .search: "SidebarSearch"
        default: "SidebarShortcut-" + data.shortcut.key
        }
    }
}

// MARK: Places

/// A section of places: the Library and the Feed with no heading, or Pinned or a person's own under one, in the order
/// the person arranged. While customizing, the rows carry handles and drag to reorder, and the section's place follows.
struct SidebarPlacesSection: View, Equatable {
    @Environment(Libraries.self) private var libraries
    let section: SidebarSectionData
    let groups: [SidebarGroupChoice]
    let customizing: Bool
    let browser: Browser
    let order: ItemOrder
    let header: SidebarGroupHeader?
    let place: SidebarAddPlace

    /// The section's data and nothing else, so a change of selection does not run its body.
    static func == (a: Self, b: Self) -> Bool {
        a.section == b.section && a.groups == b.groups && a.customizing == b.customizing && a.header == b.header
            && a.order == b.order && a.place.offers == b.place.offers
    }

    var body: some View {
        if let header {
            // A section never folds, so a press on the heading's menu cannot fold it.
            Section { rows } header: { header }
                .collapsible(false)
        } else {
            Section { rows }
        }
    }

    @ViewBuilder private var rows: some View {
        ForEach(section.rows, id: \.place.key) { data in
            row(data)
        }
        .onMove { source, destination in
            libraries.updateSidebarLayout {
                $0.moveInSection(section.id, places: section.plan.members, shown: section.plan.shown, fromOffsets: source, toOffset: destination)
            }
        }
        if customizing { place }
    }

    @ViewBuilder private func row(_ data: SidebarPlaceRowData) -> some View {
        let row = SidebarPlaceRow(data: data, groups: groups, customizing: customizing, browser: browser, order: order)
        if let opens = data.opens {
            row.tag(opens)
        } else {
            row.selectionDisabled()
        }
    }
}

/// One place's row: its mark and name, the Library's count, and under the pointer a collection's plus where a count
/// would be. A pinned item is a button that opens the item, since it is no place to select.
struct SidebarPlaceRow: View, Equatable {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    @State private var isHovering = false
    let data: SidebarPlaceRowData
    let groups: [SidebarGroupChoice]
    let customizing: Bool
    let browser: Browser
    let order: ItemOrder

    static func == (a: Self, b: Self) -> Bool {
        a.data == b.data && a.groups == b.groups && a.customizing == b.customizing && a.order == b.order
    }

    var body: some View {
        Group {
            if case .item(let id) = data.place, !customizing {
                Button { open(id) } label: { content.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect) }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            SidebarPlaceMenu(data: data, groups: groups, customizing: customizing, browser: browser, order: order)
        }
        .accessibilityActions {
            if data.adds, !customizing { Button(addName) { add() } }
        }
        .accessibilityIdentifier(identifier)
    }

    private var content: some View {
        HStack(spacing: 0) {
            SidebarMarkLabel(title: data.title, mark: data.mark)
            Spacer(minLength: 8)
            if customizing {
                SidebarHandle()
            } else if data.adds || data.count != nil {
                ZStack(alignment: .trailing) {
                    if let count = data.count {
                        Text(count, format: .number).monospacedDigit().sidebarTrailing()
                            .opacity(isHovering && data.adds ? 0 : 1)
                    }
                    if data.adds, isHovering {
                        SidebarPlus(name: addName, add: add)
                    }
                }
            }
        }
    }

    private var addName: String {
        String(localized: "New Item in \(data.title)")
    }

    private func add() {
        guard let opens = data.opens else { return }
        browser.show(opens, in: library, order: order)
        browser.openQuickAdd(remembered: lastType, in: library)
    }

    private func open(_ id: ItemID) {
        guard let item = library.item(id) else { return }
        browser.open(itemLink: item, in: library, order: order)
    }

    private var identifier: String {
        if case .view(let id) = data.place { "SidebarView-\(id.rawValue)" } else { "SidebarPlace-\(data.place.key)" }
    }
}

/// A row's mark and name, for every mark a place can have.
struct SidebarMarkLabel: View {
    let title: String
    let mark: SidebarMark

    var body: some View {
        switch mark {
        case .symbol(let name): SidebarLabel(title: title, icon: .symbol(name))
        case .icon(let icon): SidebarLabel(title: title, icon: icon)
        case .grayType(let id): SidebarLabel(title: title, icon: .type(id), grayType: true)
        case .view(let id): SidebarViewLabel(title: title, id: id)
        }
    }
}

/// A saved view's label, whose mark is its layout's on this Mac. It reads the views' layouts itself, so a change of
/// layout or of a column's width redraws the view rows alone.
private struct SidebarViewLabel: View {
    @AppStorage(ViewLayouts.key) private var layouts = ViewLayouts()
    let title: String
    let id: ItemID

    var body: some View {
        SidebarLabel(title: title, icon: .symbol(SidebarPlace.symbol(ofView: id, in: layouts)))
    }
}

/// The plus that takes a count's place under the pointer, and makes an item of a type or in a collection. Under the
/// pointer itself it has a ground, and its help names what it makes.
struct SidebarPlus: View {
    @State private var isHovering = false
    let name: String
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(
                    Color(nsColor: .labelColor).opacity(isHovering ? 0.08 : 0), in: .rect(cornerRadius: 5))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(name)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Text at a row's trailing end, a count or a shortcut, in the size of the system's own count, ending where it
    /// does.
    func sidebarTrailing() -> some View {
        font(.subheadline)
            .foregroundStyle(.tertiary)
            .padding(.trailing, 4)
    }
}

// MARK: Tabs

/// The tabs, above the list, shown where there is more than one and always while customizing: each a pill with its
/// name, the chosen one filled. A new tab is named in place. While customizing a faint "Tab" place adds one;
/// otherwise a plus does.
struct SidebarTabBar: View {
    @Environment(Libraries.self) private var libraries
    @State private var editing: String?
    @State private var draft = ""
    @FocusState private var isFocused: Bool
    let tabs: [SidebarTab]
    let chosen: String
    let customizing: Bool
    let browser: Browser

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                if editing == tab.id {
                    TextField("Name", text: $draft)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .fixedSize()
                        .interfaceFont(.body.weight(.medium))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color(nsColor: .labelColor).opacity(0.08), in: .capsule)
                        .onSubmit { commit(tab.id) }
                        .onExitCommand { editing = nil }
                        .onChange(of: isFocused) { if !isFocused { commit(tab.id) } }
                        .accessibilityIdentifier("SidebarTabName")
                } else {
                    pill(tab)
                }
            }
            if customizing {
                SidebarDashedButton(title: String(localized: "Tab"), height: 24) { addTab() }
                    .fixedSize()
                    .accessibilityIdentifier("SidebarNewTab")
            } else {
                Button("New Tab", systemImage: "plus") { addTab() }
                    .labelStyle(.iconOnly)
                    .appButton(.plain, size: .small, icon: true)
                    .accessibilityIdentifier("SidebarNewTab")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func pill(_ tab: SidebarTab) -> some View {
        let isChosen = tab.id == chosen
        return Button { browser.sidebarTab = tab.id } label: {
            Text(tab.name)
                .lineLimit(1)
                .interfaceFont(.body.weight(.medium))
                .foregroundStyle(isChosen ? .primary : .secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(isChosen ? Color(nsColor: .labelColor).opacity(0.08) : .clear, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .contextMenu {
            Button("Rename…") { beginNaming(tab) }
            Button("Remove Tab") { libraries.updateSidebarLayout { $0.removeTab(tab.id) } }
                .disabled(tabs.count < 2)
        }
        .accessibilityIdentifier("SidebarTab-\(tab.id)")
    }

    private func addTab() {
        var created: String?
        libraries.updateSidebarLayout { created = $0.addTab(named: "") }
        guard let created else { return }
        browser.sidebarTab = created
        draft = ""
        editing = created
        isFocused = true
    }

    private func beginNaming(_ tab: SidebarTab) {
        draft = tab.name
        editing = tab.id
        isFocused = true
    }

    private func commit(_ id: String) {
        guard editing == id else { return }
        editing = nil
        libraries.updateSidebarLayout { $0.renameTab(id, to: draft) }
    }
}
