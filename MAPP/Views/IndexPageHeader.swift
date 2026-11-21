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
                if browser.indexPlaceHasTools { IndexTools(browser: browser, new: new) }
            }
        }
    }
}

/// Search, Filter and New as plain symbol buttons at the tabs' trailing end. Search opens into a field in place, which
/// filters the page as it is typed in and closes on Escape or when it is cleared. Filter shows or hides the filter row,
/// and is drawn gray while it is on, never in the accent color.
struct IndexTools: View {
    @Bindable var browser: Browser
    let new: (() -> Void)?

    /// How wide the search field is while it is out.
    static let fieldWidth: CGFloat = 240

    var body: some View {
        HStack(spacing: 4) {
            if browser.isSearchExpanded, !browser.isIndexHeaderAway {
                ColumnSearchField(
                    text: $browser.searchText, prompt: String(localized: "Search"), focusRequests: browser.searchFocusRequests,
                    trailingPadding: 8, onSubmit: {}, onDown: { browser.focusRequest = .list },
                    restoresTitle: false
                ) {
                    browser.searchText = ""
                    browser.isSearchExpanded = false
                }
                .frame(width: Self.fieldWidth, height: 28)
                .background(Color.primary.opacity(0.065), in: .rect(cornerRadius: 9, style: .continuous))
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

    private func symbol(
        _ title: LocalizedStringKey, _ image: String, isOn: Bool = false, id: String, action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: image, action: action)
            .labelStyle(.iconOnly)
            .mappButton(isOn ? .secondary : .plain, icon: true)
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
