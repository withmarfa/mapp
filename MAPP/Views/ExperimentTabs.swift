#if DEBUG
import MarfaIcons
import SwiftUI

/// The tab-bar sidebar experiment (`SidebarStyle.tabs`), in the manner of Notion's top tabs: a row of icon tabs above
/// a short list of collections and views. The tab row decides where the window is; the list is a real sidebar `List`.
/// The foot is the real one. Its text is not localized.
struct TabsSidebar: View {
    @CurrentLibrary private var library
    let browser: Browser
    let order: NoteOrder
    @AppStorage("experiment.tabs.collectionsOpen") private var collectionsOpen = true
    @AppStorage("experiment.tabs.viewsOpen") private var viewsOpen = true

    /// Home and Settings show no row as selected; every other place is a row or a tab.
    private var selection: Binding<SidebarItem?> {
        Binding {
            browser.showsSettings || browser.showsTabsHome ? nil : browser.sidebarItem
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
        let collections = library.collections
        let views = library.views
        List(selection: selection) {
            Section(isExpanded: $collectionsOpen) {
                if collections.isEmpty {
                    Text(verbatim: "No collections yet")
                        .interfaceFont(.body)
                        .foregroundStyle(.tertiary)
                        .selectionDisabled()
                }
                ForEach(collections) { collection in
                    let count = library.count(in: .collection(collection.id))
                    SidebarLabel(
                        title: collection.title.isEmpty ? String(localized: "Untitled") : collection.title,
                        icon: .type(library.catalogue.icon(for: collection.type))
                    )
                    .badge(count > 0 ? Text(count, format: .number).monospacedDigit() : nil)
                    .tag(SidebarItem.collection(collection.id))
                    .accessibilityIdentifier("TabsCollection-\(collection.id.rawValue)")
                }
            } header: {
                CollectionsHeading(browser: browser, order: order)
            }
            .accessibilityIdentifier("TabsCollections")
            Section(isExpanded: $viewsOpen) {
                ForEach(views) { view in
                    SidebarLabel(title: view.title, icon: .symbol(SidebarPlace.viewSymbol))
                        .tag(SidebarItem.view(view.id))
                        .contextMenu { SavedViewRowMenu(view: view.id, browser: browser) }
                        .accessibilityIdentifier("TabsView-\(view.id.rawValue)")
                }
                if views.isEmpty {
                    Text(verbatim: "No saved views yet")
                        .interfaceFont(.body)
                        .foregroundStyle(.tertiary)
                        .selectionDisabled()
                }
            } header: {
                ViewsHeading(browser: browser)
            }
            .accessibilityIdentifier("TabsViews")
        }
        .listStyle(.sidebar)
        // A bar, not an inset, so rows passing beneath the tabs get the system's scroll edge.
        .safeAreaBar(edge: .top, spacing: 0) {
            TabsBar(browser: browser, order: order)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { SidebarFoot(browser: browser) }
        .softSelection(
            rows: collections.map(\.id.rawValue) + views.map(\.id.rawValue) + [String(collectionsOpen), String(viewsOpen)],
            selection: browser.showsSettings || browser.showsTabsHome ? nil : browser.sidebarItem)
        .accessibilityIdentifier("Sidebar")
        .onChange(of: collections.map(\.id)) { browser.placeRemoved(in: library, order: order) }
        .onChange(of: views.map(\.id)) { browser.placeRemoved(in: library, order: order) }
    }
}

/// The Collections heading. A button at its trailing side opens the page of every collection, while the pointer is over
/// the heading.
private struct CollectionsHeading: View {
    @CurrentLibrary private var library
    let browser: Browser
    let order: NoteOrder
    @State private var isHovering = false

    var body: some View {
        HStack {
            Text(library.name(of: .collections))
            Spacer()
            Button {
                browser.show(.collections, in: library, order: order)
            } label: {
                Image(systemName: "arrow.up.forward")
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .help(Text(verbatim: "Show all collections"))
            .accessibilityLabel(Text(verbatim: "Show all collections"))
            .accessibilityIdentifier("TabsAllCollections")
        }
        .padding(.trailing, 12)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
    }
}

// MARK: Tab bar

/// The row of tabs: an icon each, the selected one a soft pill with its name beside the icon, then Search and the
/// Inbox, with its count, at the end. Where the sidebar is too narrow for the name, every tab is an icon.
private struct TabsBar: View {
    @CurrentLibrary private var library
    @Environment(\.interfaceTextSize) private var textSize
    let browser: Browser
    let order: NoteOrder

    private var selected: SidebarTab? {
        SidebarTab.current(item: browser.item, home: browser.showsTabsHome, settings: browser.showsSettings)
    }

    private var inboxIsShown: Bool {
        browser.item == .inbox && !browser.showsSettings && !browser.showsTabsHome
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showsName: true)
            row(showsName: false)
            ScrollView(.horizontal) { row(showsName: false) }.scrollIndicators(.hidden)
        }
        .animation(.snappy(duration: 0.22), value: selected)
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Tabs"))
        .accessibilityIdentifier("TabsBar")
    }

    private func row(showsName: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(SidebarTab.allCases) { tab in
                tabButton(tab, showsName: showsName)
            }
            Spacer(minLength: 4)
            Button { browser.palette = .search } label: { TabsIcon(symbol: "magnifyingglass") }
                .buttonStyle(TabsButtonStyle(isSelected: false))
                .help(Text(verbatim: "Search"))
                .accessibilityLabel(Text(verbatim: "Search"))
                .accessibilityIdentifier("TabsSearch")
            inboxButton
        }
    }

    private func tabButton(_ tab: SidebarTab, showsName: Bool) -> some View {
        let isSelected = tab == selected
        return Button { choose(tab) } label: {
            HStack(spacing: 5) {
                TabsIcon(symbol: tab.symbol, filled: isSelected)
                if isSelected, showsName {
                    Text(verbatim: tab.title)
                        .interfaceFont(.body.weight(.medium))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.trailing, 3)
                }
            }
        }
        .buttonStyle(TabsButtonStyle(isSelected: isSelected))
        .help(Text(verbatim: tab.title))
        .accessibilityLabel(Text(verbatim: tab.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("TabsTab-\(tab.rawValue)")
        .contextMenu { if tab == .items { itemsMenu } }
    }

    private var inboxButton: some View {
        let count = library.count(in: .inbox)
        return Button {
            browser.show(.inbox, in: library, order: order)
        } label: {
            TabsIcon(symbol: "tray", filled: inboxIsShown)
                .overlay(alignment: .topTrailing) {
                    if count > 0 { TabsBadge(count: count).offset(x: 8, y: -6) }
                }
        }
        .buttonStyle(TabsButtonStyle(isSelected: inboxIsShown))
        .help(Text(verbatim: "Inbox"))
        .accessibilityLabel(Text(verbatim: count > 0 ? "Inbox, \(count) items" : "Inbox"))
        .accessibilityAddTraits(inboxIsShown ? .isSelected : [])
        .accessibilityIdentifier("TabsInbox")
    }

    /// The lists of items that have no tab: reached from the Items tab's menu, and from Home.
    @ViewBuilder private var itemsMenu: some View {
        Button(library.name(of: .recents), systemImage: "clock") { go(.recents) }
        Button(library.name(of: .favorites), systemImage: "heart") { go(.favorites) }
        Button(library.name(of: .recentlyDeleted), systemImage: "trash") { go(.recentlyDeleted) }
        let types = openingTypes(library.typeTree)
        if !types.isEmpty {
            Divider()
            Menu {
                ForEach(types) { node in
                    Button { go(.itemType(node.type?.rawValue ?? node.id)) } label: { Label(node.label, typeIcon: node.icon) }
                }
            } label: {
                Text(verbatim: "Types")
            }
        }
    }

    private func openingTypes(_ nodes: [TypeNode]) -> [TypeNode] {
        nodes.flatMap { ($0.opens ? [$0] : []) + openingTypes($0.children) }
    }

    private func go(_ item: SidebarItem) { browser.show(item, in: library, order: order) }

    private func choose(_ tab: SidebarTab) {
        switch SidebarTab.move(for: tab, item: browser.item, home: browser.showsTabsHome, settings: browser.showsSettings) {
        case .stay: break
        case .home:
            browser.show(.allNotes, in: library, order: order)
            browser.tabsHome = true
        case .place(let item): go(item)
        case .settings: browser.showSettings()
        case .leaveSettings: browser.leaveSettings()
        }
    }
}

/// A tab's mark, in a square that grows with the interface text size.
private struct TabsIcon: View {
    @Environment(\.interfaceTextSize) private var textSize
    let symbol: String
    var filled = false

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        Image(systemName: symbol)
            .symbolVariant(filled ? .fill : .none)
            .interfaceFont(.body)
            .frame(minWidth: 18 * scale, minHeight: 18 * scale)
            .contentTransition(.symbolEffect(.replace))
    }
}

/// The Inbox's count, as a small red capsule on its icon.
private struct TabsBadge: View {
    let count: Int

    var body: some View {
        Text(verbatim: count > 99 ? "99+" : String(count))
            .interfaceFont(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(minWidth: 15)
            .background(.red, in: .capsule)
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// A tab's look: quiet grey until pointed at, a soft pill behind it when it is the one shown. The pill is the grey of
/// the sidebar's own selection (`softSelection`), so the two read as one family.
private struct TabsButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        TabLook(configuration: configuration, isSelected: isSelected)
    }

    private struct TabLook: View {
        @Environment(\.interfaceTextSize) private var textSize
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        @State private var isHovering = false

        var body: some View {
            let scale = InterfaceStyle.scale(for: textSize)
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            configuration.label
                .foregroundStyle(isSelected || isHovering ? .primary : .secondary)
                .padding(.horizontal, 6)
                .frame(minHeight: 26 * scale)
                .background(fill, in: shape)
                .contentShape(shape)
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
        }

        private var fill: Color {
            if configuration.isPressed { return .primary.opacity(0.14) }
            if isSelected { return .primary.opacity(0.08) }
            return isHovering ? .primary.opacity(0.05) : .clear
        }
    }
}

// MARK: Home

/// Home in the tab-bar experiment: a greeting, chips to make something new, and the recent and favorite items as cards.
/// A card opens its item as the list does. Its text is not localized. The chips and cards repeat the Items landing
/// page's look, which is kept apart so the two experiments can change on their own.
struct TabsHome: View {
    @CurrentLibrary private var library
    let browser: Browser
    let order: NoteOrder
    let showsCreation: Bool

    private static let corner: CGFloat = 14
    private static let shownLimit = 6

    var body: some View {
        let recent = Array(library.items(in: .recents).prefix(Self.shownLimit))
        let favorites = Array(library.items(in: .favorites).prefix(Self.shownLimit))
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: TabsGreeting.text(hour: Calendar.current.component(.hour, from: library.now())))
                        .interfaceFont(.largeTitle.weight(.medium))
                        .fontDesign(.serif)
                    Text(verbatim: summary)
                        .interfaceFont(.body)
                        .foregroundStyle(.secondary)
                }
                makeSomethingNew
                cards("Recent", items: recent, showAll: .recents)
                if !favorites.isEmpty { cards("Favorites", items: favorites, showAll: .favorites) }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
        .background(.background)
        .navigationTitle(Text(verbatim: "Home"))
        .toolbar {
            if showsCreation {
                ToolbarItem(id: "tabsHomeNewItem") { NewItemButton(browser: browser) }
            }
        }
        .accessibilityIdentifier("TabsHome")
    }

    private var summary: String {
        let count = library.count(in: .allNotes)
        return count == 1 ? "1 item in this library" : "\(count) items in this library"
    }

    private var makeSomethingNew: some View {
        let split = ExperimentChips.split(QuickAdd.types(in: library), usedMost: library.itemTypeCounts.map(\.id))
        return VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Make something new")
                .interfaceFont(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(split.shown) { option in
                        Button { browser.openQuickAdd(typeID: option.id.rawValue, in: library) } label: {
                            Chip(title: option.label, icon: .type(option.icon))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("TabsMake-\(option.id.rawValue)")
                    }
                    if !split.more.isEmpty {
                        Menu {
                            ForEach(split.more) { option in
                                Button { browser.openQuickAdd(typeID: option.id.rawValue, in: library) } label: {
                                    Label(option.label, typeIcon: option.icon)
                                }
                            }
                        } label: {
                            Chip(title: "More", icon: .symbol("plus"))
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityIdentifier("TabsMakeMore")
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private func cards(_ title: String, items: [Item], showAll: SidebarItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(verbatim: title)
                    .interfaceFont(.headline)
                Spacer()
                Button { browser.show(showAll, in: library, order: order) } label: {
                    Text(verbatim: "Show all")
                }
                .buttonStyle(.link)
                .interfaceFont(.subheadline)
                .accessibilityIdentifier("TabsShowAll-\(title)")
            }
            if items.isEmpty {
                Text(verbatim: "Nothing here yet. Make something new above.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 16)], spacing: 16) {
                    ForEach(items) { item in
                        Button { browser.reveal(item, in: library, order: order) } label: {
                            Card(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("TabsCard-\(title)-\(item.id.rawValue)")
                    }
                }
            }
        }
    }

    private struct Chip: View {
        let title: String
        let icon: RowIcon
        @State private var isHovering = false

        var body: some View {
            HStack(spacing: 8) {
                RowIconImage(icon: icon).foregroundStyle(.secondary)
                Text(verbatim: title)
            }
            .interfaceFont(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary), in: shape)
            .overlay(shape.strokeBorder(.quaternary, lineWidth: 1))
            .contentShape(shape)
            .onHover { isHovering = $0 }
        }

        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: TabsHome.corner, style: .continuous) }
    }

    private struct Card: View {
        @CurrentLibrary private var library
        let item: Item
        @State private var isHovering = false

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title.isEmpty ? String(localized: "Untitled") : item.title)
                    .interfaceFont(.headline)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(verbatim: item.preview)
                    .interfaceFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                HStack {
                    HStack(spacing: 5) {
                        TypeIcon(name: library.catalogue.icon(for: item.type))
                        Text(verbatim: library.catalogue.label(for: item.type)).lineLimit(1)
                    }
                    .interfaceFont(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Spacer(minLength: 8)
                    Text(item.modified, format: .relative(presentation: .named))
                        .interfaceFont(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .background(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary), in: shape)
            .overlay(shape.strokeBorder(.quaternary, lineWidth: 1))
            .contentShape(shape)
            .onHover { isHovering = $0 }
            .foregroundStyle(.primary)
        }

        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: TabsHome.corner, style: .continuous) }
    }
}
#endif
