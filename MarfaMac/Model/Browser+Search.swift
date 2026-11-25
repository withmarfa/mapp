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
    func tokenTargets(in library: any ItemLibrary) -> [String: FilterTarget] {
        guard hasSearchTokens else { return [:] }
        let known = Dictionary((FilterTarget.everyItem + [.tier]).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let types = listedTypes(in: library)
        var targets: [String: FilterTarget] = [:]
        for clause in searchTokens where targets[clause.field] == nil {
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
        var parts = FilterWording.parts(of: clause, target: target, calendar: .current, titles: { Self.title(ofValue: $0, in: library) })
        if clause.op == target.kind.startingOperator || (clause.op == .includes && target.kind == .tags) { parts.relation = "" }
        return parts
    }

    private static func title(ofValue id: String, in library: any ItemLibrary) -> String? {
        if let type = library.itemTypeCounts.first(where: { $0.id.rawValue == id }) { return type.label }
        return library.item(ItemID(rawValue: id))?.displayTitle
    }

    /// What the field offers for the words typed in it, worked out from the place's own fields.
    func searchOffers(in library: any ItemLibrary) -> [SearchOffer] {
        guard SearchScope.narrows(shown), isSearching else { return [] }
        let offer = tableContent(in: library).filterOffer
        var values = SearchOffers.Values()
        values.types = library.itemTypeCounts.map { SearchOffers.Option(id: $0.id.rawValue, title: $0.label) }
        values.sources = library.sources.infos.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { SearchOffers.Option(id: $0.code, title: $0.name) }
        values.tags = library.knownTags
        values.collections = library.collections.map { SearchOffers.Option(id: $0.id.rawValue, title: $0.displayTitle) }
        let targets = offer.placeFields + offer.everyItem.filter { $0.kind != .parent } + [.tier]
        let context = SearchOffers.Context(
            targets: targets, values: values, hasSeveralTypes: offer.hasSeveralTypes, calendar: .current, now: library.now())
        return SearchOffers.make(text: searchText, in: context, existing: searchTokens)
    }
}
