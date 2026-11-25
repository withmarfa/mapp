import Foundation

/// The list's search: its text and the tokens beside it. Neither is saved; they are the window's, and a change of place
/// puts both away.
extension Browser {
    /// Whether the search holds any token, which narrows the list as a filter does, with or without text.
    var hasSearchTokens: Bool { !searchTokens.isEmpty }

    /// Whether the list is narrowed by its search in any way.
    var narrowsBySearch: Bool { isSearching || hasSearchTokens }

    /// Puts the search away: its text, its tokens and the field.
    func clearSearch() {
        searchText = ""
        searchTokens = []
        isSearchExpanded = false
    }

    /// Adds a token once; the same clause twice would say nothing more.
    func addSearchToken(_ clause: FilterClause) {
        guard !searchTokens.contains(clause) else { return }
        searchTokens.append(clause)
    }

    /// Takes the last token away, as Delete does at the start of the field. Whether there was one.
    @discardableResult
    func removeLastSearchToken() -> Bool {
        guard !searchTokens.isEmpty else { return false }
        searchTokens.removeLast()
        return true
    }

    func removeSearchToken(_ clause: FilterClause) {
        searchTokens.removeAll { $0 == clause }
    }

    /// The fields the tokens ask about, found from the catalogue alone: the table's columns come from the items, which
    /// the tokens decide, so the fields cannot wait for them.
    func tokenTargets(in library: any ItemLibrary, of tokens: [FilterClause]? = nil) -> [String: FilterTarget] {
        let tokens = tokens ?? searchTokens
        guard !tokens.isEmpty else { return [:] }
        let known = Dictionary((FilterTarget.everyItem + [.tier]).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let types = listedTypes(in: library)
        var targets: [String: FilterTarget] = [:]
        for clause in tokens where targets[clause.field] == nil {
            if let target = known[clause.field] {
                targets[clause.field] = target
            } else if clause.field.hasPrefix(Self.fieldColumnPrefix),
                      let target = FilterTarget.target(
                        ofProperty: String(clause.field.dropFirst(Self.fieldColumnPrefix.count)), among: types, catalogue: library.catalogue) {
                targets[clause.field] = target
            }
        }
        return targets
    }

    /// The tokens as the filter model words them: the field, the relation where it is not the field's usual one, and the
    /// values. Nil where the field is not one the place's types have.
    func tokenParts(of clause: FilterClause, in library: any ItemLibrary) -> FilterWording.Parts? {
        guard let target = tokenTargets(in: library)[clause.field] else { return nil }
        return FilterWording.tokenParts(of: clause, target: target, calendar: .current, titles: { library.title(ofValue: $0) })
    }

    /// What the search's offers are held under between runs of the body: the words, the tokens, the place and what the
    /// library holds, which are all they are worked out from.
    struct OfferKey: Equatable {
        let text: String
        let tokens: [FilterClause]
        let shown: PlaceView
        let listing: PlaceListing
        let content: Int
        let membership: Int
    }

    struct ParentKey: Equatable {
        let types: Set<TypeID>
        let content: Int
        let membership: Int
    }

    /// The items a listed type may have as a parent, which Parent offers by title; none where no listed type can have one.
    /// Worked out once for the types and what the library holds, not for each key typed.
    private func parentOptions(of types: Set<TypeID>, in library: any ItemLibrary) -> [SearchOffers.Option] {
        let key = ParentKey(types: types, content: library.contentRevision, membership: library.membershipRevision)
        if let held = parentMemo, held.key == key { return held.options }
        let ids = (types.isEmpty ? Set(library.catalogue.itemTypes.keys) : types).filter { library.canHaveParent(typeID: $0.rawValue) }
        var seen = Set<ItemID>()
        let options = ids.sorted { $0.rawValue < $1.rawValue }
            .flatMap { library.creationParentCandidates(typeID: $0.rawValue) }
            .filter { seen.insert($0.id).inserted }
            .map { SearchOffers.Option(id: $0.id.rawValue, title: $0.displayTitle) }
        parentMemo = (key, options)
        return options
    }

    /// What the field offers for the words typed in it. The fields are those of the types the place lists, or of the whole
    /// catalogue where it lists no fixed types, so what the words found never decides them. Worked out once for a key.
    func searchOffers(in library: any ItemLibrary) -> [SearchOffer] {
        guard SearchScope.narrows(shown), isSearching else { return [] }
        let key = OfferKey(
            text: searchText, tokens: searchTokens, shown: shown, listing: listing, content: library.contentRevision,
            membership: library.membershipRevision)
        if let held = offerMemo, held.key == key { return held.offers }
        let catalogue = library.catalogue
        let types = listedTypes(in: library)
        let several = (types.isEmpty ? catalogue.itemTypes.count : types.count) > 1
        var values = library.searchOfferValues
        values.parents = parentOptions(of: types, in: library)
        let context = SearchOffers.Context(
            targets: FilterTarget.fields(among: types, catalogue: catalogue)
                + FilterTarget.everyItem.filter { $0.kind != .parent || !values.parents.isEmpty } + [.tier],
            values: values, hasSeveralTypes: several, calendar: .current, now: library.now())
        let offers = SearchOffers.make(text: searchText, in: context, existing: searchTokens)
        offerMemo = (key, offers)
        return offers
    }
}
