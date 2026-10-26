import SwiftUI

extension SearchExcerpt {
    /// The excerpt with each match in bold. `matchColor` is the match's color, for a row whose text is not the
    /// usual secondary color.
    func attributed(matchColor: Color = .primary) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            if run.isMatch {
                piece.inlinePresentationIntent = .stronglyEmphasized
                piece.foregroundColor = matchColor
            }
            result.append(piece)
        }
        return result
    }
}

/// What sits above the results while the window searches: where to look, where there is more than one choice, and a
/// plain line for whatever makes the results less than all there is. It draws nothing when it has nothing to say.
struct SearchStatusBar: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser

    var body: some View {
        let results = browser.searchResults(in: library)
        let offersScope = SearchScope.narrows(browser.item)
        if offersScope || results?.isIncomplete == true || results?.cappedCount != nil {
            VStack(alignment: .leading, spacing: 6) {
                if offersScope {
                    Picker("Search Scope", selection: $browser.searchesPlace) {
                        Text("Everywhere").tag(false)
                        Text(verbatim: library.name(of: browser.item)).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("SearchScope")
                }
                if results?.isIncomplete == true {
                    Text("Still loading your items, so these results may be incomplete.")
                        .accessibilityIdentifier("SearchIncomplete")
                }
                if let shown = results?.cappedCount {
                    Text("Showing the first \(shown) results.")
                        .accessibilityIdentifier("SearchCapped")
                }
            }
            .interfaceFont(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

extension View {
    /// The search's scope and notices above the content, while the window searches.
    func searchStatus(_ browser: Browser) -> some View {
        safeAreaBar(edge: .top, spacing: 0) {
            if browser.isSearching { SearchStatusBar(browser: browser) }
        }
    }
}

/// The answer to a search that lists nothing. It says nothing until the search has answered, and never says that
/// nothing matches while the copy is still filling, since what matches may not have arrived.
struct SearchEmptyState: View {
    @CurrentLibrary private var library
    let browser: Browser

    var body: some View {
        let results = browser.searchResults(in: library)
        if results?.isPending == true {
            EmptyView()
        } else if results?.isIncomplete == true {
            EmptyState(
                title: Text("Still Looking"),
                detail: Text("Your items are still loading, so nothing has matched “\(browser.searchText)” yet."),
                actions: { EmptyView() })
        } else {
            EmptyState.search(browser.searchText)
        }
    }
}
