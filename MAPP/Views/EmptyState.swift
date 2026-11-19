import SwiftUI

/// What a view says when it has nothing to show: a short title and at most one short line, with no icon.
struct EmptyState<Actions: View>: View {
    let title: Text
    var detail: Text?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 6) {
            title
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
            if let detail {
                detail
                    .foregroundStyle(.secondary)
            }
            actions
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

extension EmptyState where Actions == EmptyView {
    init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil) {
        self.init(title: Text(title), detail: detail.map { Text($0) }, actions: { EmptyView() })
    }

    /// The answer to a search with no results.
    static func search() -> EmptyState {
        EmptyState("No Results", detail: "Nothing matches your search.")
    }
}

/// What the window's place says when it holds nothing (`PlaceEmpty`): its own title and line, and for a type, New and the
/// type's name, which opens quick add holding that type.
struct PlaceEmptyState: View {
    @CurrentLibrary private var library
    let browser: Browser

    var body: some View {
        let offered = QuickAdd.isAvailable(in: library) ? QuickAdd.types(in: library).map(\.id.rawValue) : []
        let empty = PlaceEmpty.of(browser.item, in: library.catalogue, offered: offered)
        EmptyState(title: Text(verbatim: empty.title), detail: empty.line.map { Text(verbatim: $0) }) {
            if let type = empty.makes, let title = empty.buttonTitle {
                Button(title, systemImage: "plus") { browser.openQuickAdd(typeID: type, in: library) }
                    .mappButton(.secondary)
                    .padding(.top, 6)
                    .accessibilityIdentifier("EmptyStateNew")
            }
        }
    }
}

/// What the window's content says when the list beside it holds nothing and there is no page to show: the filters that
/// hide everything, a search with no match, or the place's own words. The list column stays blank, as the page would be.
struct ListEmptyState: View {
    @CurrentLibrary private var library
    let browser: Browser

    var body: some View {
        if browser.filtersHideEverything(in: library) {
            FilteredEmptyState(browser: browser)
        } else if browser.isSearching {
            SearchEmptyState(browser: browser)
        } else {
            PlaceEmptyState(browser: browser)
        }
    }
}
