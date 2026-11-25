import Foundation
import Marfa

/// Where a window can be: the Library, the Feed, one type, collection or source, an index of them, or the Archive.
/// A place is kept in the defaults and the synced settings as one word (`word`), so a word this copy does not know,
/// written by a newer one, is skipped where it is read and kept where it is stored.
nonisolated enum Place: Hashable, Sendable {
    /// The library tier.
    case library
    /// The feed tier.
    case feed
    /// A type, with its kinds unless the window leaves them out.
    case type(TypeID)
    /// The items filed in a collection through `in-collection`.
    case collection(ItemID)
    /// The items a source wrote, by its code.
    case source(String)
    /// The index of types.
    case types
    /// The index of collections.
    case collections
    /// The index of sources.
    case sources
    /// Every archived item, of both tiers.
    case archive

    /// The place as it is stored: `library`, `type:core.task`, `collection:<id>`.
    var word: String {
        switch self {
        case .library: "library"
        case .feed: "feed"
        case .type(let type): "type:" + type.rawValue
        case .collection(let id): "collection:" + id.rawValue
        case .source(let code): "source:" + code
        case .types: "types"
        case .collections: "collections"
        case .sources: "sources"
        case .archive: "archive"
        }
    }

    /// The place a stored word names, or nil for a word this copy does not know.
    init?(word: String) {
        let parts = word.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count == 2 ? parts[1] : nil) {
        case ("library", nil): self = .library
        case ("feed", nil): self = .feed
        case ("types", nil): self = .types
        case ("collections", nil): self = .collections
        case ("sources", nil): self = .sources
        case ("archive", nil): self = .archive
        case ("type", let rest?) where !rest.isEmpty: self = .type(TypeID(rest))
        case ("collection", let rest?) where !rest.isEmpty: self = .collection(ItemID(rest))
        case ("source", let rest?) where !rest.isEmpty: self = .source(rest)
        default: return nil
        }
    }

    /// Whether the place lists items, as against an index of places.
    var listsItems: Bool {
        switch self {
        case .types, .collections, .sources: false
        default: true
        }
    }

    /// Whether the place lists what it holds from both tiers, by the From the window chooses (`ListScope`).
    var takesScope: Bool {
        switch self {
        case .type, .collection, .source: true
        default: false
        }
    }
}

nonisolated extension Place: Codable {
    init(from decoder: any Decoder) throws {
        let word = try decoder.singleValueContainer().decode(String.self)
        guard let place = Place(word: word) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown place \(word)"))
        }
        self = place
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(word)
    }
}

/// Which view of a place a window shows: the place's own, the Library's Favorites, or a view saved on the server.
nonisolated enum ViewChoice: Hashable, Sendable {
    /// The place itself, as the app keeps it.
    case own
    /// The Library's second view, kept by the app: every item tagged favorite.
    case favorites
    /// A view saved on the server, whose home (`Place.home(of:catalogue:)`) is the place it belongs to.
    case saved(ItemID)

    var word: String {
        switch self {
        case .own: "own"
        case .favorites: "favorites"
        case .saved(let id): "saved:" + id.rawValue
        }
    }

    /// The choice a stored word names. A word this copy does not know reads as the place's own view.
    init(word: String) {
        self = ViewChoice(knownWord: word) ?? .own
    }

    /// The choice a stored word names, or nil for a word this copy does not know.
    init?(knownWord word: String) {
        if word == "own" { self = .own }
        else if word == "favorites" { self = .favorites }
        else if word.hasPrefix("saved:"), word.count > 6 { self = .saved(ItemID(String(word.dropFirst(6)))) }
        else { return nil }
    }

    var savedView: ItemID? {
        if case .saved(let id) = self { id } else { nil }
    }
}

nonisolated extension ViewChoice: Codable {
    init(from decoder: any Decoder) throws {
        self.init(word: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(word)
    }
}

/// What a window shows: a place, and which of its views. Everything a Mac keeps for a place (columns, density, table
/// options, the place's default view, history, window restoration, Start With) is kept for one of these.
nonisolated struct PlaceView: Hashable, Codable, Sendable {
    var place: Place
    var view: ViewChoice

    init(_ place: Place, _ view: ViewChoice = .own) {
        self.place = place
        self.view = view
    }

    init(place: Place, view: ViewChoice) {
        self.init(place, view)
    }

    static let library = PlaceView(.library)
    static let feed = PlaceView(.feed)
    static let favorites = PlaceView(.library, .favorites)
    static let types = PlaceView(.types)
    static let collections = PlaceView(.collections)
    static let sources = PlaceView(.sources)
    static let archive = PlaceView(.archive)
    static func type(_ type: TypeID) -> PlaceView { PlaceView(.type(type)) }
    static func collection(_ id: ItemID) -> PlaceView { PlaceView(.collection(id)) }
    static func source(_ code: String) -> PlaceView { PlaceView(.source(code)) }

    /// The saved view `id` as a key of what the window keeps for it, which is equal to the view at any home.
    static func saved(_ id: ItemID) -> PlaceView { PlaceView(.library, .saved(id)) }

    /// The saved view `id`, at its home in `library`, or in the Library where the copy does not hold the view.
    @MainActor static func saved(_ id: ItemID, in library: any ItemLibrary) -> PlaceView {
        let home = library.views.first { $0.id == id }.map { Place.home(of: $0.query, catalogue: library.catalogue) }
        return PlaceView(home ?? .library, .saved(id))
    }

    /// The saved view the window shows, if it shows one.
    var savedView: ItemID? { view.savedView }

    /// What a window keeps for this under (`PlaceMemory`): a saved view at the Library, since it is the same view
    /// wherever its home is, so what is kept for it outlasts a change of its filters that moves it to another place.
    var memoryKey: PlaceView { savedView.map(PlaceView.saved) ?? self }

    /// Whether the two are the same thing shown: the same place and view, or the same saved view at any home.
    func isSame(_ other: PlaceView?) -> Bool { other.map { memoryKey == $0.memoryKey } ?? false }

    /// The key the defaults keep this under: the place's word for its own view, `library|favorites` for the
    /// Favorites view, and `saved:<id>` for a saved view, whose home can change as its filters do. None starts with
    /// `{`, as the keys of earlier copies did, so the two never meet.
    var storageKey: String {
        switch view {
        case .own: place.word
        case .favorites: place.word + "|" + view.word
        case .saved: view.word
        }
    }

    /// What a stored key names, or nil for a key this copy cannot read. A saved view's key names no place; it reads
    /// at the Library until the window places it.
    init?(storageKey key: String) {
        if key.hasPrefix("saved:") {
            let view = ViewChoice(word: key)
            guard view != .own else { return nil }
            self.init(.library, view)
            return
        }
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard let place = parts.first.flatMap(Place.init(word:)) else { return nil }
        self.init(place, parts.count == 2 ? ViewChoice(word: parts[1]) : .own)
    }

    /// Whether this is the Library's Favorites view.
    var isFavorites: Bool { view == .favorites }

    /// Whether the window lists items here, as against an index of places.
    var listsItems: Bool { place.listsItems || view != .own }
}

/// What a window keeps for each place it showed, by `PlaceView.memoryKey`.
nonisolated struct PlaceMemory<Value>: ExpressibleByDictionaryLiteral {
    private var values: [PlaceView: Value] = [:]

    init(dictionaryLiteral elements: (PlaceView, Value)...) {
        for (place, value) in elements { values[place.memoryKey] = value }
    }

    subscript(place: PlaceView) -> Value? {
        get { values[place.memoryKey] }
        set { values[place.memoryKey] = newValue }
    }

    subscript(place: PlaceView, default value: @autoclosure () -> Value) -> Value {
        get { values[place.memoryKey] ?? value() }
        set { values[place.memoryKey] = newValue }
    }

    var isEmpty: Bool { values.isEmpty }
}

extension PlaceMemory: Equatable where Value: Equatable {}
extension PlaceMemory: Sendable where Value: Sendable {}

nonisolated extension Place {
    /// The place a saved view belongs to: the one type it lists; else the one collection its filter requires through
    /// `in-collection`, naming no other collection or source; else the one source it requires, naming no other source
    /// or collection; else the Feed, when it lists the feed tier and names no collection or source; else the Library.
    static func home(of query: LibraryViewQuery, catalogue: Catalogue) -> Place {
        if query.types.count == 1, let type = query.types.first { return .type(type) }
        let parsed = (try? ViewDraft.terms(of: query.filter)) ?? ViewDraft.Parsed(terms: [], join: .all)
        // A condition narrows the list only where every condition must hold.
        let required = parsed.join == .all || parsed.terms.count == 1
        var collections: [(id: ItemID, required: Bool)] = []
        var sources: [(code: String, required: Bool)] = []
        for condition in parsed.terms where condition.operator == .eq {
            guard case .text(let value)? = condition.value else { continue }
            // Membership is the item's own edge to the collection; the reverse edge is another condition.
            if case .edge(let type, .outbound) = condition.field,
               (catalogue.edgeType(named: type)?.info.id ?? type) == MarfaMapping.collectionEdge {
                collections.append((ItemID(value), required))
            } else if condition.field == .system(.source) {
                sources.append((value, required))
            }
        }
        if collections.count == 1, sources.isEmpty, let only = collections.first, only.required { return .collection(only.id) }
        if sources.count == 1, collections.isEmpty, let only = sources.first, only.required { return .source(only.code) }
        if query.tier == .feed, query.types.isEmpty, collections.isEmpty, sources.isEmpty { return .feed }
        return .library
    }
}

/// Which tiers a place lists: both, or one. A type, a collection and a source choose; the Library lists its tier and
/// the Feed its own. Kept as `all`, `library` and `feed`.
nonisolated enum ListScope: String, Codable, Hashable, Sendable, CaseIterable {
    case all, library, feed

    /// The tier a view's query names for this scope, nil for both.
    var tier: Tier? {
        switch self {
        case .all: nil
        case .library: .library
        case .feed: .feed
        }
    }

    init(tier: Tier?) {
        switch tier {
        case nil: self = .all
        case .library: self = .library
        case .feed: self = .feed
        }
    }

    /// Where Settings keeps the From a type, a collection or a source starts on: `all` or `library`.
    static let defaultScopeKey = "lists.defaultScope"

    /// The From a type, a collection or a source starts on, as Settings says: All Items unless the person chose the
    /// Library. A stored word this version does not know reads as All Items.
    static func defaultScope(in defaults: UserDefaults) -> ListScope {
        defaults.string(forKey: defaultScopeKey).flatMap(ListScope.init(rawValue:)) == .library ? .library : .all
    }

    /// Whether `tier` is listed.
    func includes(_ tier: Tier) -> Bool { self.tier.map { $0 == tier } ?? true }

    /// Whether the window offers the Library or Feed control: only at a type, a collection or a source that holds
    /// something from the Feed, never at the Library, the Feed or the Library's own lists.
    static func showsScopeControl(place: Place, counts: ScopeCounts) -> Bool {
        place.takesScope && counts.feed > 0
    }
}

/// Whether a place lists its archived items: not at all, beside the active ones, or alone. Kept as `hidden`,
/// `shown` and `only`.
nonisolated enum ArchivedItems: String, Codable, Hashable, Sendable, CaseIterable {
    case hidden, shown, only

    /// The states a view's query names for this choice, nil for every state but the bin.
    var states: Set<ItemState>? {
        switch self {
        case .hidden: [.active]
        case .shown: nil
        case .only: [.archived]
        }
    }

    /// The choice a view's states stand for. A view that names no state lists archived items beside the rest.
    init(states: Set<ItemState>?) {
        switch states?.subtracting([.trashed]) {
        case [.active]?: self = .hidden
        case [.archived]?: self = .only
        default: self = .shown
        }
    }

    /// Whether an item in `state` is listed.
    func includes(_ state: ItemState) -> Bool {
        switch self {
        case .hidden: state == .active
        case .shown: state == .active || state == .archived
        case .only: state == .archived
        }
    }
}

/// How many active items a place holds in each tier, for the Library or Feed control.
nonisolated struct ScopeCounts: Hashable, Sendable {
    var library: Int
    var feed: Int
    var all: Int { library + feed }

    init(library: Int, feed: Int) {
        self.library = library
        self.feed = feed
    }

    func count(in scope: ListScope) -> Int {
        switch scope {
        case .all: all
        case .library: library
        case .feed: feed
        }
    }
}

/// What a window lists of a place besides its filters: the From, the archived items and a type's kinds.
nonisolated struct PlaceListing: Hashable, Sendable {
    var scope: ListScope = .all
    var archived: ArchivedItems = .hidden
    var includesKinds = true
}
