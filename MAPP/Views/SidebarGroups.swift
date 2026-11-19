import SwiftUI
import UniformTypeIdentifiers

// MARK: Data the sections are drawn from

/// A place a section's Show list offers, shown or not.
nonisolated struct SidebarShowChoice: Equatable, Identifiable {
    let place: SidebarPlace
    let title: String
    let isShown: Bool

    var id: String { place.key }
}

/// Something Add Shortcut or Add Section can name: its key (a place's, or a type's identifier) and its name.
nonisolated struct SidebarPick: Equatable, Identifiable {
    let key: String
    let title: String

    var id: String { key }
}

/// What the Add Shortcut and Add Section menus offer, worked out only while the sidebar is being customized.
nonisolated struct SidebarChoices: Equatable {
    var views: [SidebarPick] = []
    var types: [SidebarPick] = []
    var collections: [SidebarPick] = []
    var sources: [SidebarPick] = []
    /// The kinds a Create shortcut can make, by type identifier.
    var creatable: [SidebarPick] = []
}

/// A section as it is dragged by its handle, which is all a drop on another section's heading reads.
nonisolated struct SidebarSectionDrag: Codable, Transferable {
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .mappSidebarSection)
    }
}

extension UTType {
    /// Named for the bundle identifier, as `MAPP/Info.plist` declares it, so a section never drags into the other build.
    nonisolated static let mappSidebarSection = UTType(exportedAs: "\(Bundle.main.bundleIdentifier ?? "com.withmarfa.mapp").sidebar-section")
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

/// A section's heading. Outside customizing it is the name alone, with New View on hover for the section that holds
/// the saved views. While customizing it has the section's menu and a handle that drags the section.
struct SidebarGroupHeader: View {
    @Environment(Libraries.self) private var libraries
    let section: SidebarSectionData
    let tabs: [SidebarTab]
    let tab: String
    let customizing: Bool
    let browser: Browser
    let isFirst: Bool
    let isLast: Bool
    let ask: (SidebarNaming) -> Void

    var body: some View {
        let group = section.plan.group
        if !customizing, group.kind == .views {
            ViewsHeading(title: group.name, browser: browser)
        } else {
            HStack(spacing: 8) {
                Text(group.name)
                Spacer()
                if customizing {
                    menu
                    SidebarHandle().draggable(SidebarSectionDrag(id: group.id))
                }
            }
            .padding(.trailing, 12)
            .contentShape(.rect)
            .dropDestination(for: SidebarSectionDrag.self) { drops, _ in
                guard customizing, let drop = drops.first else { return false }
                libraries.updateSidebarLayout { $0.moveGroup(drop.id, onto: group.id) }
                return true
            }
            .accessibilityIdentifier("SidebarSection-\(group.id)")
        }
    }

    private var menu: some View {
        let group = section.plan.group
        return Menu {
            if !section.choices.isEmpty {
                Menu("Show") {
                    ForEach(section.choices) { choice in
                        Toggle(choice.title, isOn: Binding {
                            choice.isShown
                        } set: { shown in
                            libraries.updateSidebarLayout { $0.setHidden(choice.place, !shown) }
                        })
                    }
                }
            }
            Button("Rename…") { ask(.renameGroup(group.id, current: group.name)) }
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
                Button("New Tab…") { ask(.newTab(moving: group.id)) }
            }
            Divider()
            Button("Hide Section") { libraries.updateSidebarLayout { $0.hideGroup(group.id) } }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("Section Options"))
        .accessibilityIdentifier("SidebarSectionMenu-\(group.id)")
    }
}

// MARK: Shortcuts

/// The shortcuts block: rows that act or go somewhere, never taking the selection. While customizing each has a
/// handle, a context menu that removes it, and the Add Shortcut row follows.
struct SidebarShortcutsSection: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    let section: SidebarSectionData
    let tab: String
    let canCreate: Bool
    let customizing: Bool
    let addsShortcuts: Bool
    let choices: SidebarChoices
    let browser: Browser
    let order: ItemOrder

    var body: some View {
        Section {
            ForEach(section.shortcuts) { data in
                row(data)
            }
            .onMove { source, destination in
                libraries.updateSidebarLayout { $0.moveShortcuts(in: section.id, fromOffsets: source, toOffset: destination) }
            }
            if customizing, addsShortcuts {
                SidebarAddShortcutRow(tab: tab, present: Set(section.plan.group.shortcuts), choices: choices)
            }
        }
    }

    private func row(_ data: SidebarShortcutRowData) -> some View {
        Button { perform(data) } label: {
            // The label is only as wide as its words; the frame gives the click the whole row.
            HStack {
                SidebarLabel(title: data.title, icon: data.icon)
                Spacer(minLength: 0)
                if customizing { SidebarHandle() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .disabled(customizing || ((data.shortcut == .new || isCreate(data.shortcut)) && !canCreate))
        .contextMenu {
            Button("Remove Shortcut") {
                libraries.updateSidebarLayout { $0.removeShortcut(data.shortcut, from: section.id) }
            }
            Divider()
            SidebarCustomizeButton(browser: browser)
        }
        .accessibilityIdentifier(Self.identifier(of: data.shortcut))
    }

    private func isCreate(_ shortcut: SidebarShortcut) -> Bool {
        if case .create = shortcut { true } else { false }
    }

    private func perform(_ data: SidebarShortcutRowData) {
        switch data.shortcut {
        case .new: browser.openQuickAdd(remembered: lastType, in: library)
        case .create(let type): browser.openQuickAdd(typeID: type, in: library)
        case .search: browser.palette = .search
        case .settings: browser.showSettings()
        case .go:
            if let item = data.item { browser.choose(item, in: library, order: order) }
        }
    }

    private static func identifier(of shortcut: SidebarShortcut) -> String {
        switch shortcut {
        case .new: "SidebarNew"
        case .search: "SidebarSearch"
        default: "SidebarShortcut-" + shortcut.key
        }
    }
}

/// The row that adds a shortcut to the tab: New, Search or Settings where it is not there, a place to go to, or a
/// kind of item to create.
struct SidebarAddShortcutRow: View {
    @Environment(Libraries.self) private var libraries
    let tab: String
    let present: Set<SidebarShortcut>
    let choices: SidebarChoices

    var body: some View {
        Menu {
            let fixed: [(SidebarShortcut, String)] = [
                (.new, String(localized: "New")), (.search, String(localized: "Search")), (.settings, String(localized: "Settings")),
            ]
            ForEach(fixed.filter { !present.contains($0.0) }, id: \.0.key) { shortcut, title in
                Button(title) { add(shortcut) }
            }
            Divider()
            Menu("Go To") {
                pickMenu("A View", choices.views) { .go($0) }
                pickMenu("A Type", choices.types) { .go($0) }
                pickMenu("A Collection", choices.collections) { .go($0) }
                pickMenu("A Source", choices.sources) { .go($0) }
            }
            pickMenu("Create", choices.creatable) { .create($0) }
        } label: {
            SidebarLabel(title: String(localized: "Add Shortcut"), icon: .symbol("plus"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityIdentifier("SidebarAddShortcut")
    }

    private func pickMenu(_ title: LocalizedStringKey, _ picks: [SidebarPick], make: @escaping (String) -> SidebarShortcut) -> some View {
        Menu(title) {
            ForEach(picks) { pick in
                let shortcut = make(pick.key)
                Button(pick.title) { add(shortcut) }
                    .disabled(present.contains(shortcut))
            }
        }
        .disabled(picks.isEmpty)
    }

    private func add(_ shortcut: SidebarShortcut) {
        libraries.updateSidebarLayout { $0.addShortcut(shortcut, toTab: tab) }
    }
}

// MARK: Add Section

/// The row that adds a section to the tab: a built-in one that was hidden, a new one, or a new one holding a
/// collection or a source.
struct SidebarAddSectionRow: View {
    @Environment(Libraries.self) private var libraries
    let tab: String
    let hiddenKinds: [SidebarGroup.Kind]
    let choices: SidebarChoices

    var body: some View {
        Menu {
            ForEach(hiddenKinds, id: \.self) { kind in
                Button(Self.title(of: kind)) { libraries.updateSidebarLayout { $0.addGroup(kind, toTab: tab) } }
            }
            Button("New Section") { libraries.updateSidebarLayout { $0.addGroup(.custom, toTab: tab) } }
            Divider()
            holding("A Collection", choices.collections)
            holding("A Source", choices.sources)
        } label: {
            SidebarLabel(title: String(localized: "Add Section"), icon: .symbol("plus"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityIdentifier("SidebarAddSection")
    }

    private func holding(_ title: LocalizedStringKey, _ picks: [SidebarPick]) -> some View {
        Menu(title) {
            ForEach(picks) { pick in
                Button(pick.title) {
                    libraries.updateSidebarLayout { layout in
                        let group = layout.addGroup(.custom, toTab: tab)
                        if let place = SidebarPlace(key: pick.key) { layout.put(place, in: group) }
                    }
                }
            }
        }
        .disabled(picks.isEmpty)
    }

    private static func title(of kind: SidebarGroup.Kind) -> String {
        SidebarGroup(id: kind.rawValue, kind: kind, tab: "").name
    }
}

// MARK: Places

/// A section of places: the library's indexes, views, collections and sources, in the order the person arranged. While
/// customizing, the rows carry handles and drag to reorder.
struct SidebarPlacesSection: View {
    @Environment(Libraries.self) private var libraries
    let section: SidebarSectionData
    let groups: [SidebarGroupChoice]
    let customizing: Bool
    let browser: Browser
    let header: SidebarGroupHeader

    var body: some View {
        let group = section.plan.group
        Section {
            ForEach(section.rows, id: \.place.key) { data in
                SidebarPlaceRow(data: data, groups: groups, customizing: customizing, browser: browser)
                    .tag(data.item)
            }
            .onMove { source, destination in
                libraries.updateSidebarLayout { $0.move(section.plan.members, shown: section.plan.shown, by: \.key, fromOffsets: source, toOffset: destination) }
            }
            if group.kind == .views { SidebarPendingViewRow(browser: browser) }
        } header: {
            header
        }
        .accessibilityIdentifier(group.kind == .views ? "SidebarViews" : group.kind == .library ? "SidebarLibraryGroup" : "SidebarGroup-\(group.id)")
    }
}

/// One place of a section: its mark, its name and the count the row says, if any. Recents has no count since it always
/// holds the same number, and the indexes list what the copy holds on their own.
struct SidebarPlaceRow: View, Equatable {
    let data: SidebarPlaceRowData
    let groups: [SidebarGroupChoice]
    let customizing: Bool
    let browser: Browser

    static func == (a: Self, b: Self) -> Bool { a.data == b.data && a.groups == b.groups && a.customizing == b.customizing }

    var body: some View {
        Group {
            if customizing {
                HStack {
                    label
                    Spacer(minLength: 8)
                    SidebarHandle()
                }
            } else {
                label.badge(data.count > 0 ? Text(data.count, format: .number).monospacedDigit() : nil)
            }
        }
        .contextMenu { SidebarPlaceMenu(data: data, groups: groups, browser: browser) }
        .accessibilityIdentifier(identifier)
    }

    private var label: SidebarLabel { SidebarLabel(title: data.title, icon: .symbol(data.symbol), tone: data.tone) }

    private var identifier: String {
        if case .view(let id) = data.place { "SidebarView-\(id.rawValue)" } else { "SidebarPlace-\(data.place.key)" }
    }
}

/// A place's context menu: a view's own commands and its color, where it goes, and Hide from Sidebar.
struct SidebarPlaceMenu: View {
    @Environment(Libraries.self) private var libraries
    @Environment(\.colorScheme) private var scheme
    let data: SidebarPlaceRowData
    let groups: [SidebarGroupChoice]
    let browser: Browser

    var body: some View {
        if case .view(let id) = data.place {
            SavedViewRowMenu(view: id, browser: browser)
            Divider()
        }
        if data.place.defaultTone != nil {
            Picker("Color", selection: Binding {
                libraries.sidebarLayout.color(of: data.place)
            } set: { tone in
                libraries.updateSidebarLayout { $0.setColor(tone, of: data.place) }
            }) {
                ForEach(TypeTone.allCases, id: \.self) { tone in
                    Label(tone.name, systemImage: "circle.fill")
                        .tint(tone.color(for: scheme))
                        .tag(tone)
                }
            }
            .pickerStyle(.palette)
        }
        if !groups.isEmpty {
            Menu("Move to Section") {
                ForEach(groups) { group in
                    Button(group.name) { libraries.updateSidebarLayout { $0.put(data.place, in: group.id) } }
                }
            }
        }
        Divider()
        SidebarHideButtons(place: data.place)
        Divider()
        SidebarCustomizeButton(browser: browser)
    }
}

extension TypeTone {
    /// What the color is called, for the palette's help and for VoiceOver.
    var name: String {
        switch self {
        case .blue: String(localized: "Blue")
        case .green: String(localized: "Green")
        case .orange: String(localized: "Orange")
        case .red: String(localized: "Red")
        case .purple: String(localized: "Purple")
        case .teal: String(localized: "Teal")
        case .yellow: String(localized: "Yellow")
        case .pink: String(localized: "Pink")
        case .indigo: String(localized: "Indigo")
        case .gray: String(localized: "Gray")
        }
    }
}

/// The view a New View panel is making, drawn as the selected row of Views until Done makes it or Escape drops it. It
/// is no place yet, so it takes no selection of its own.
struct SidebarPendingViewRow: View {
    let browser: Browser

    var body: some View {
        if browser.viewPanel?.isNew == true {
            SidebarLabel(title: String(localized: "New View"), icon: .symbol(SidebarPlace.viewSymbol))
                .listRowBackground(Color(nsColor: .labelColor).opacity(0.08).clipShape(.rect(cornerRadius: 6)))
                .selectionDisabled()
                .accessibilityAddTraits(.isSelected)
                .accessibilityIdentifier("SidebarNewView")
        }
    }
}

// MARK: Tabs

/// The tabs, above the list, shown only where there is more than one: each a symbol, the chosen one with its name, and a
/// plus that adds another.
struct SidebarTabBar: View {
    @Environment(Libraries.self) private var libraries
    let tabs: [SidebarTab]
    let chosen: String
    let browser: Browser
    let ask: (SidebarNaming) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                let isChosen = tab.id == chosen
                Button { browser.sidebarTab = tab.id } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                        if isChosen { Text(tab.name).lineLimit(1) }
                    }
                    .interfaceFont(.body)
                    .foregroundStyle(isChosen ? .primary : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isChosen ? Color(nsColor: .labelColor).opacity(0.08) : .clear, in: .rect(cornerRadius: 6))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(tab.name)
                .accessibilityLabel(Text(tab.name))
                .accessibilityAddTraits(isChosen ? .isSelected : [])
                .contextMenu {
                    Button("Rename…") { ask(.renameTab(tab.id, current: tab.name)) }
                    Button("Remove Tab") { libraries.updateSidebarLayout { $0.removeTab(tab.id) } }
                        .disabled(tabs.count < 2)
                }
                .accessibilityIdentifier("SidebarTab-\(tab.id)")
            }
            Spacer(minLength: 0)
            Button("New Tab", systemImage: "plus") { ask(.newTab(moving: nil)) }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("SidebarNewTab")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
