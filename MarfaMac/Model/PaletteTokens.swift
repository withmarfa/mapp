import Foundation

/// What Search Items' tokens narrow its items by: the same clauses the list's search makes (`FilterClause`), joined by AND,
/// over the fields every item has. They apply to the items a palette lists, never to its commands or places.
nonisolated struct PaletteTokens: Equatable, Sendable {
    var clauses: [FilterClause] = []

    /// Every field a token of the palette can ask about: the ones every item has, and the tier.
    static let targets: [FilterTarget] = (FilterTarget.everyItem + [.tier]).filter { $0.kind != .parent }

    private static let targetsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })

    var isEmpty: Bool { clauses.isEmpty }

    /// The one type token Marfa is asked for with the search, so the search keeps its limit for what the type lets through:
    /// the first that names types.
    var typeClause: FilterClause? {
        clauses.first { $0.field == FilterTarget.type.id && ($0.op == .is || $0.op == .isNot) && !$0.values.isEmpty }
    }

    var types: Set<TypeID> { Set(typeClause?.values.map(TypeID.init) ?? []) }
    var excludesTypes: Bool { typeClause?.op == .isNot }

    /// The tokens left to apply once a search has answered.
    var afterSearch: PaletteTokens {
        guard let typeClause, let index = clauses.firstIndex(of: typeClause) else { return self }
        var rest = self
        rest.clauses.remove(at: index)
        return rest
    }

    /// The items that pass, in their order. Without tokens, the same array.
    func apply(to items: [Item], catalogue: Catalogue, now: Date, calendar: Calendar = .current) -> [Item] {
        guard !clauses.isEmpty else { return items }
        let rows = items.map { item in
            ItemTableRow(
                item: item, typeLabel: "", typeIcon: nil, parent: nil,
                collections: item.collectionIDs.map { RelatedItem(id: $0, title: "", icon: nil) })
        }
        return FilterMatching.filter(
            rows, by: FilterState(clauses: clauses), targets: Self.targetsByID, catalogue: catalogue,
            clock: FilterMatching.Clock(now: now, calendar: calendar)
        ).map(\.item)
    }

    /// The token as a chip says it, or nil where its field is not one the palette offers.
    func parts(of clause: FilterClause, calendar: Calendar = .current, titles: (String) -> String?) -> FilterWording.Parts? {
        Self.targetsByID[clause.field].map { FilterWording.tokenParts(of: clause, target: $0, calendar: calendar, titles: titles) }
    }
}
