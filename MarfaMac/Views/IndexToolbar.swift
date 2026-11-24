import SwiftUI

/// The tabs of an index page as a segmented control in the window's toolbar, which come in once the page's own tabs have
/// scrolled away. They stand in the middle of the toolbar, where the title would.
struct IndexTabsToolbarItem: CustomizableToolbarContent {
    let browser: Browser

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "indexTabs", placement: .principal) {
            if let place = browser.indexPlace { IndexTabPicker(place: place).id(place) }
        }
        .customizationBehavior(.disabled)
        .hidden(!browser.showsIndexTools)
    }
}

/// What the page's buttons are in the toolbar once the page's title has scrolled away: Edit, Search, Filter and New,
/// then the page's View Options. Edit is on Items whether or not the page is scrolled, since it has no counterpart
/// on the page, but only while the page shows its New tiles (Settings > Lists). The rest are absent while the page's own buttons show. Search is the toolbar's field, which takes the
/// text and the open state of the page's.
struct IndexToolbarItems: CustomizableToolbarContent {
    @Bindable var browser: Browser
    @AppStorage(ListKey.showsQuickAdd) private var showsQuickAdd = false

    var body: some CustomizableToolbarContent {
        let showsTools = browser.showsIndexTools && browser.indexPlaceHasTools
        ToolbarItem(id: "indexEdit") {
            IndexEditButton(browser: browser)
        }
        .customizationBehavior(.disabled)
        .hidden(browser.indexPlace != .items || !showsQuickAdd)
        ColumnSearch(
            isExpanded: $browser.isSearchExpanded,
            text: $browser.searchText,
            prompt: String(localized: "Search"),
            layout: .item,
            focusRequests: browser.searchFocusRequests,
            onDown: { browser.focusRequest = .list },
            restoresTitle: false
        )
        .hidden(!showsTools)
        ToolbarItem(id: "indexFilter") {
            Toggle(isOn: Binding { browser.showsFilterRow } set: { _ in browser.toggleIndexFilter() }) {
                Label("Filter", systemImage: "line.3.horizontal.decrease")
            }
            // Gray while on, as the page's own Filter button is, rather than the accent color.
            .tint(.secondary)
            .help(browser.toggleFiltersTitle)
            .accessibilityIdentifier("IndexFilterToolbar")
        }
        .customizationBehavior(.disabled)
        .hidden(!showsTools)
        ToolbarItem(id: "indexNew") {
            IndexNewButton(browser: browser)
        }
        .customizationBehavior(.disabled)
        .hidden(!showsTools)
        ToolbarItem(id: "viewOptions") {
            if let place = browser.indexPlace { IndexViewOptionsMenu(place: place, browser: browser) }
        }
    }
}

/// The page's tabs as a segmented control.
private struct IndexTabPicker: View {
    let place: IndexPlace
    @AppStorage private var stored: IndexTab

    init(place: IndexPlace) {
        self.place = place
        _stored = AppStorage(wrappedValue: .all, place.tabKey)
    }

    var body: some View {
        Picker("Show", selection: Binding { place.tabs.contains(stored) ? stored : .all } set: { stored = $0 }) {
            ForEach(place.tabs, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("IndexTabsToolbar")
    }
}

/// Edit: opens the list of the types the New row offers, as a glass button like the toolbar's others.
private struct IndexEditButton: View {
    @Bindable var browser: Browser

    var body: some View {
        Button("Edit") { browser.isEditingNewRow.toggle() }
            .popover(isPresented: $browser.isEditingNewRow, arrowEdge: .bottom) { NewRowEditor() }
            .help("Edit the New row")
            .accessibilityIdentifier("IndexEditToolbar")
    }
}

/// New in the toolbar: a new item on Items, a new collection on Collections.
private struct IndexNewButton: View {
    @CurrentLibrary private var library
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    let browser: Browser

    var body: some View {
        let title: LocalizedStringKey = browser.indexPlace == .collections ? "New Collection" : "New Item"
        Button(title, systemImage: "plus") { browser.openQuickAddFromIndex(remembered: lastType, in: library) }
            .disabled(!QuickAdd.isAvailable(in: library))
            .help(title)
            .accessibilityIdentifier("IndexNewToolbar")
    }
}

/// The View menu's commands for an index page's own controls, which are the page's and the toolbar's buttons too: the
/// tab shown, the filter and the New row's Edit.
struct IndexPageCommands: View {
    @Bindable var browser: Browser
    @AppStorage(ListKey.showsQuickAdd) private var showsQuickAdd = false
    let place: IndexPlace
    let shortcuts: ShortcutBindings
    @AppStorage private var stored: IndexTab

    init(browser: Browser, place: IndexPlace, shortcuts: ShortcutBindings) {
        self.browser = browser
        self.place = place
        self.shortcuts = shortcuts
        _stored = AppStorage(wrappedValue: .all, place.tabKey)
    }

    var body: some View {
        Section("Show") {
            ForEach(place.tabs, id: \.self) { tab in
                Toggle(tab.title, isOn: Binding { (place.tabs.contains(stored) ? stored : .all) == tab } set: { _ in stored = tab })
            }
        }
        if browser.indexPlaceHasTools {
            Button(browser.toggleFiltersTitle) { browser.toggleIndexFilter() }
                .shortcut(.toggleFilters, shortcuts)
        }
        if place == .items, showsQuickAdd {
            Button("Edit New Row…") { browser.isEditingNewRow = true }
        }
    }
}
