import SwiftUI

/// The top of an index page: its large title, then the tabs with the page's buttons at their trailing end. This is what
/// scrolls away, and what the window's toolbar takes over once it has (`IndexToolbarItems`).
struct IndexPageTop: View {
    let title: String
    let browser: Browser
    let tabs: [(tab: IndexTab, count: Int)]
    @Binding var tab: IndexTab
    /// What the page's New button does, where the page has one.
    var new: (() -> Void)?
    /// Whether the places the Library leads on to stand before the tools (`LibraryPlaces`).
    var leadsOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .padding(.horizontal, IndexMetrics.side)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("IndexTitle")
            IndexTabBar(tabs: tabs, tab: $tab) {
                if leadsOn { LibraryPlaces(browser: browser) }
                if browser.indexPlaceHasTools { IndexTools(browser: browser, new: new) }
            }
        }
    }
}

/// The places the Library leads on to, at the end of its tabs: Collections and Sources with how many each holds, and the
/// Archive. Types has no page yet, so it is not here.
struct LibraryPlaces: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    let browser: Browser

    var body: some View {
        HStack(spacing: 4) {
            place(String(localized: "Collections"), .collections, count: library.count(in: .collections, scope: .all))
            place(String(localized: "Sources"), .sources, count: library.count(in: .sources, scope: .all))
            place(String(localized: "Archive"), .archive, count: nil)
        }
    }

    private func place(_ title: String, _ place: PlaceView, count: Int?) -> some View {
        Button {
            browser.show(place, in: library, order: order)
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: title)
                if let count { Text(count, format: .number).monospacedDigit().foregroundStyle(.secondary) }
            }
        }
        .appButton(.plain)
        .accessibilityIdentifier("LibraryPlace.\(place.place.word)")
    }
}

/// Search, Filter and New at the tabs' trailing edge. Escape closes Search, as does leaving the field empty.
struct IndexTools: View {
    @Bindable var browser: Browser
    let new: (() -> Void)?

    /// How wide the search field is while it is out.
    static let fieldWidth: CGFloat = 240

    var body: some View {
        HStack(spacing: 4) {
            if browser.isSearchExpanded, !browser.isIndexHeaderAway {
                InlineSearchField(
                    text: $browser.searchText, prompt: String(localized: "Search"), identifier: "ColumnSearch", clearIdentifier: "ClearColumnSearch",
                    focusRequests: browser.searchFocusRequests,
                    onDown: { browser.focusRequest = .list },
                    onCancel: closeSearch, onEnd: closeSearch
                )
                .frame(width: Self.fieldWidth)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ColumnSearchField")
            } else {
                symbol("Search", "magnifyingglass", id: "IndexSearch") { browser.showSearchField() }
            }
            symbol("Filter", "line.3.horizontal.decrease", isOn: browser.showsFilterRow, id: "IndexFilter") {
                browser.toggleIndexFilter()
            }
            if let new {
                symbol("New", "plus", id: "IndexNew", action: new)
            }
        }
    }

    private func closeSearch() {
        browser.searchText = ""
        browser.isSearchExpanded = false
    }

    private func symbol(
        _ title: LocalizedStringKey, _ image: String, isOn: Bool = false, id: String, action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: image, action: action)
            .labelStyle(.iconOnly)
            .appButton(isOn ? .secondary : .plain, icon: true)
            .help(title)
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .accessibilityIdentifier(id)
    }
}

/// The row that stands where the New row does while a filter is set: Collections' source filter.
struct CollectionFilterRow: View {
    @Bindable var browser: Browser
    /// The sources the collections come from, by name.
    let sources: [String]

    var body: some View {
        HStack(spacing: FilterChipMetrics.spacing) {
            Menu {
                ForEach(sources, id: \.self) { name in
                    Toggle(name, isOn: Binding { browser.collectionSourceFilter.contains(name) } set: { _ in browser.toggleCollectionSource(name) })
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Source").foregroundStyle(.secondary)
                    Text(verbatim: browser.collectionSourceFilter.isEmpty ? "…" : browser.collectionSourceFilter.sorted().joined(separator: ", "))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .frame(height: FilterChipMetrics.height)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: FilterChipMetrics.radius, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityIdentifier("CollectionSourceFilter")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, IndexMetrics.side)
        .padding(.vertical, 6)
        .padding(.bottom, 6)
    }
}
