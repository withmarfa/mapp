import SwiftUI

/// What the top row says for the place a window shows, worked out once from the browser and the library so the row's
/// views only draw it. The row is drawn in the content (`TopRow`), under the window's hidden title.
struct TopRowContent {
    /// One of the place's views as a pill.
    struct Choice: Identifiable, Hashable {
        let id: String
        let title: String
        let target: PlaceView
    }

    /// One of the Library's places that fold into Browse.
    struct Browsed: Identifiable, Hashable {
        var id: String { title }
        let title: String
        let count: Int?
        let target: PlaceView
    }

    /// A choice of the control after the count.
    struct ScopeChoice: Identifiable, Hashable {
        var id: ListScope { scope }
        let scope: ListScope
        let title: String
        let count: Int
    }

    let place: Place
    let title: String
    let count: Int
    /// What a search found, or a filter leaves of the Archive, out of everything the place holds.
    let narrowed: Int?
    let views: [Choice]
    let chosen: String
    let places: [Browsed]
    /// Whether the chosen view differs from how it was when last opened.
    let isChanged: Bool
    /// The control's choices and the current one, where the place has items in the Feed.
    let scopes: [ScopeChoice]
    let scope: ListScope
    let defaultScope: ListScope

    var hasViews: Bool { views.count > 1 }
    var showsScope: Bool { !scopes.isEmpty }
    /// Whether the control says what Settings does, which is when it is quiet and the first thing to give way.
    var isDefaultScope: Bool { scope == defaultScope }
    /// The view chosen; none while the window shows one of the Library's places.
    var chosenChoice: Choice? { views.first { $0.id == chosen } ?? (chosen.isEmpty ? nil : views.first) }

    /// The title's count as it is read: "1,205", and "38 of 48,312" while searching or narrowing the Archive.
    var countText: String {
        guard let narrowed else { return count.formatted() }
        return String(localized: "\(narrowed.formatted()) of \(count.formatted())")
    }

    /// What VoiceOver reads for the title, the count being part of it: "Notes, 1 item".
    var titleLabel: String {
        guard let narrowed else { return String(AttributedString(localized: "\(title), ^[\(count) item](inflect: true)").characters) }
        return String(AttributedString(localized: "\(title), \(narrowed.formatted()) of ^[\(count) item](inflect: true)").characters)
    }

    @MainActor
    static func make(browser: Browser, library: any ItemLibrary) -> TopRowContent {
        let shown = browser.shown
        let place = shown.savedView.map { id in library.views.first { $0.id == id }.map { Place.home(of: $0.query, catalogue: library.catalogue) } ?? .library } ?? shown.place
        let listing = browser.listing
        // Types, Collections, Sources and the Archive are pages of the Library: its title, its views with none chosen,
        // and its places with theirs.
        let ofLibrary = Self.libraryPages.contains(place)
        let views = choices(in: ofLibrary ? .library : place, library: library)
        let chosenWord = shown.view.word
        let chosen = ofLibrary && place != .library ? "" : views.first { $0.target.view.word == chosenWord }?.id ?? views.first?.id ?? ""

        let base: Int
        if shown.view != .own { base = library.count(in: shown, favoritesScope: listing.scope) }
        else { base = library.count(in: place, scope: listing.scope) }
        // A filter or an arrangement leaves fewer in the list than the place holds, and the count says what is listed.
        let listed = browser.listShape == nil ? base : browser.listedCount(in: library) ?? browser.filteredItems(in: library).count
        // A search of Types, Collections or Sources narrows their rows, not the items.
        let results = browser.showsPlaceIndex ? nil : browser.searchResults(in: library)
        // A search of everything finds items beyond the place, so it is counted against all of them.
        let everything = browser.searchScope(in: library) == .everywhere
            ? library.count(in: .library) + library.count(in: .feed) : library.count(in: shown, favoritesScope: listing.scope)

        // The Archive is a page of the Library and keeps its title through a search; its count says how many items it
        // holds and how many of them a search or a filter leaves.
        // The tokens narrow the list as the filters do, so with them the list's own count is what the search leaves.
        let tokened = browser.hasSearchTokens
        var count = results == nil && !tokened ? listed : everything
        var narrowed = tokened ? listed : results.map(\.items.count)
        if browser.showsPlaceIndex {
            (count, narrowed) = (library.count(in: .library), nil)
        } else if browser.listsArchive {
            let held = library.count(in: .archive, scope: .all)
            let leaves = results.flatMap { tokened ? nil : $0.items.count } ?? browser.listedCount(in: library) ?? browser.filteredItems(in: library).count
            (count, narrowed) = (held, leaves == held ? nil : leaves)
        }

        let counts = library.scopeCounts(in: place)
        let offers = shown.view == .own && ListScope.showsScopeControl(place: place, counts: counts)
        let scopes = offers ? ListScope.allCases.map { ScopeChoice(scope: $0, title: $0.title, count: counts.count(in: $0)) } : []
        return TopRowContent(
            place: place, title: ofLibrary ? library.name(of: .library) : library.name(of: place), count: count,
            narrowed: narrowed, views: views, chosen: chosen,
            places: ofLibrary ? browsed(in: library) : [], isChanged: ofLibrary && place != .library ? false : browser.hasViewChanges,
            scopes: scopes, scope: listing.scope, defaultScope: ListScope.defaultScope(in: browser.defaults))
    }

    /// The Library and the places that are pages of it.
    private static let libraryPages: [Place] = [.library, .types, .collections, .sources, .archive]

    /// The place's views in the order the person arranged them, the ones they did not place after it.
    @MainActor
    private static func choices(in place: Place, library: any ItemLibrary) -> [Choice] {
        let orders = ViewOrders.stored()
        var all = [Choice(id: ViewChoice.own.word, title: ownTitle(of: place, library: library), target: PlaceView(place, .own))]
        if place == .library { all.append(Choice(id: ViewChoice.favorites.word, title: String(localized: "Favorites"), target: .favorites)) }
        for view in library.views(in: place, order: orders.savedOrder(in: place)) {
            all.append(Choice(id: ViewChoice.saved(view.id).word, title: view.title, target: PlaceView(place, .saved(view.id))))
        }
        let rank = Dictionary(orders.order(in: place).enumerated().map { ($1.word, $0) }, uniquingKeysWith: { first, _ in first })
        return all.enumerated().sorted { a, b in
            switch (rank[a.element.id], rank[b.element.id]) {
            case let (x?, y?): x < y
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.offset < b.offset
            }
        }.map(\.element)
    }

    /// A type's own view says what it lists, "All Highlights"; any other place's says All.
    @MainActor
    private static func ownTitle(of place: Place, library: any ItemLibrary) -> String {
        if case .type = place { return String(localized: "All \(library.name(of: place))") }
        return String(localized: "All")
    }

    @MainActor
    private static func browsed(in library: any ItemLibrary) -> [Browsed] {
        [
            Browsed(title: library.name(of: .types), count: library.itemTypeCounts.count, target: .types),
            Browsed(title: library.name(of: .collections), count: library.collections.count, target: .collections),
            Browsed(title: library.name(of: .sources), count: library.sources.counts?.count ?? library.sources.infos.count, target: .sources),
            Browsed(title: library.name(of: .archive), count: nil, target: .archive),
        ]
    }
}

extension ListScope {
    /// The control's words for each choice.
    var title: String {
        switch self {
        case .all: String(localized: "All Items")
        case .library: String(localized: "Library")
        case .feed: String(localized: "Feed")
        }
    }
}

/// The steps a row of views gives way by as the room shrinks, from the most to the least: the control after the count
/// while it says the default; then the Library's places, folded into Browse; then the views one by one into More, down
/// to the chosen one; then the chosen view as one pill.
struct TopRowFold: Hashable {
    /// Whether the control after the count shows.
    var scope: Bool
    var places: Places
    /// How many views show, the chosen one among them; the rest are in More. Nil is every view.
    var shown: Int?
    var onePill = false

    enum Places: Hashable { case inline, browse, none }

    /// Every step, in order. `hasPlaces` is true only on the Library; `restsBelow` is true while the views have a row of
    /// their own, where the places stand at its end and the title's row holds the control.
    static func steps(viewCount: Int, hasPlaces: Bool, offersScope: Bool, scopeIsDefault: Bool, restsBelow: Bool) -> [TopRowFold] {
        var steps: [TopRowFold] = []
        func add(_ fold: TopRowFold) { steps.append(fold) }
        // Beside the title the places are folded from the start: the row has no room for four more words.
        let first: Places = hasPlaces ? (restsBelow ? .inline : .browse) : .none
        add(TopRowFold(scope: offersScope, places: first, shown: nil))
        if offersScope, scopeIsDefault { add(TopRowFold(scope: false, places: first, shown: nil)) }
        let keepsScope = offersScope && !scopeIsDefault
        let after = hasPlaces ? Places.browse : .none
        if first == .inline { add(TopRowFold(scope: keepsScope, places: after, shown: nil)) }
        if viewCount > 1 {
            for shown in stride(from: viewCount - 1, through: 1, by: -1) {
                add(TopRowFold(scope: keepsScope, places: after, shown: shown))
            }
        }
        add(TopRowFold(scope: keepsScope, places: after, shown: nil, onePill: true))
        return steps
    }
}
