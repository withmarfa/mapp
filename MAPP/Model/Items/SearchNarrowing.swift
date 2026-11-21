import Foundation
import Marfa

/// The types and sources a person leaves out of search. A type left out takes its subtypes with it.
nonisolated struct SearchLeaveOut: Codable, Hashable, Sendable {
    var types: Set<TypeID> = []
    var sources: Set<String> = []

    var isEmpty: Bool { types.isEmpty && sources.isEmpty }

    init(types: Set<TypeID> = [], sources: Set<String> = []) {
        self.types = types
        self.sources = sources
    }

    /// A value stored before a field existed still reads.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        types = try values.decodeIfPresent(Set<TypeID>.self, forKey: .types) ?? []
        sources = try values.decodeIfPresent(Set<String>.self, forKey: .sources) ?? []
    }
}

/// What a search over every item keeps and leaves out, applied by the copy inside the one search call, so the most it
/// lists is counted after them. Nothing here matches an item: it only words the types and sources as the copy's filter
/// grammar takes them (`search-and-filters.md`).
///
/// The grammar's `types` key takes each type with its subtypes and its `type` field compares one identifier alone. One
/// type kept without its subtypes is therefore one `type eq` condition, and several, or a type left out with its own,
/// are `type neq` conditions for the types below them. A filter joins its conditions with one of `AND` or `OR` and
/// holds at most ten.
nonisolated struct SearchNarrowing: Hashable, Sendable {
    /// The types a search is limited to, or, with `excludesTypes`, the types it skips.
    var types: Set<TypeID> = []
    /// The types of `types` whose subtypes count too (Include Subtypes).
    var typesWithSubtypes: Set<TypeID> = []
    var excludesTypes = false
    var leaveOut = SearchLeaveOut()
    /// Whether archived items are searched (Include Archived Items).
    var includesArchived = true
    /// Whether Inbox items, the feed tier, are searched (Include Inbox Items).
    var includesInbox = true

    static let none = SearchNarrowing()

    var isEmpty: Bool { types.isEmpty && leaveOut.isEmpty && includesArchived && includesInbox }

    /// The states a search over every item keeps, and the tier it is limited to: asked of the copy in the search call
    /// itself (`ItemQuery.states`, `ItemQuery.tier`), so the most a search lists is counted after them.
    var searchedStates: Set<ItemState> { includesArchived ? [.active, .archived] : [.active] }
    var searchedTier: Tier? { includesInbox ? nil : .library }

    /// The most conditions a filter holds, and the most types the `types` key takes.
    static let maxConditions = 10
    static let maxTypes = 10

    /// What the copy is asked: the types to keep (with their subtypes), and the filter text.
    struct Expression: Equatable, Sendable {
        var types: Set<TypeID> = []
        var filter: String?
        /// The narrowing admits no item, so the copy need not be asked.
        var matchesNothing = false
    }

    enum Refusal: Error, Equatable, Sendable {
        case tooManyTypes
        case tooManyConditions
        case refused(String)

        var message: String {
            switch self {
            case .tooManyTypes: String(localized: "A search can limit itself to ten types at most.")
            case .tooManyConditions: String(localized: "The types and sources chosen and left out make more conditions than one search can hold.")
            case .refused(let message): message
            }
        }
    }

    /// How many conditions a search over every item holds for the leave-out alone: one for each type left out and each
    /// type below it that the copy holds, and one for each source. At `maxConditions` the next addition makes every
    /// search fail, so the Search page counts them as a person adds.
    func leaveOutConditionCount(in catalogue: Catalogue) -> Int {
        leftOutTypes(in: catalogue).intersection(catalogue.itemTypes.keys).count + leaveOut.sources.count
    }

    // MARK: Asking the copy

    /// The search for what is kept: the chosen types, without what is left out.
    func kept(in catalogue: Catalogue) throws -> Expression {
        var excluded = leftOutTypes(in: catalogue)
        var included: Set<TypeID> = []
        var reached: Set<TypeID>?
        if excludesTypes {
            for type in types { excluded.formUnion(typesWithSubtypes.contains(type) ? Self.subtree(of: type, in: catalogue) : [type]) }
        } else if !types.isEmpty {
            included = types.intersection(catalogue.itemTypes.keys)
            guard !included.isEmpty else { return Expression(matchesNothing: true) }
            guard included.count <= Self.maxTypes else { throw Refusal.tooManyTypes }
            if let only = exactType(in: catalogue) {
                // One `type eq` condition however many subtypes it has; the `types` key would take them too.
                guard !excluded.contains(only) else { return Expression(matchesNothing: true) }
                let conditions = [Self.condition(.type, .eq, only.rawValue)] + leaveOut.sources.sorted().map { Self.condition(.source, .neq, $0) }
                return Expression(filter: try Self.text(of: conditions, join: .all))
            }
            let below = included.reduce(into: Set<TypeID>()) { $0.formUnion(Self.subtree(of: $1, in: catalogue)) }
            let admitted = included.reduce(into: included) { held, type in
                if typesWithSubtypes.contains(type) { held.formUnion(catalogue.descendants(of: type)) }
            }
            excluded.formUnion(below.subtracting(admitted))
            reached = below
        }
        // A type the copy holds no items of cannot match, so it needs no condition.
        excluded.formIntersection(reached ?? Set(catalogue.itemTypes.keys))
        let conditions =
            excluded.map(\.rawValue).sorted().map { Self.condition(.type, .neq, $0) }
            + leaveOut.sources.sorted().map { Self.condition(.source, .neq, $0) }
        return Expression(types: included, filter: try Self.text(of: conditions, join: .all))
    }

    /// The search for what is left out: every item the leave-out holds, of the chosen types. The filter joins with
    /// `OR`, which cannot hold the exact-type conditions, so a result is checked with `admitsType` afterwards.
    func leftOutOfSearch(in catalogue: Catalogue) throws -> Expression {
        var included: Set<TypeID> = []
        var reached: Set<TypeID>?
        if !excludesTypes, !types.isEmpty {
            included = types.intersection(catalogue.itemTypes.keys)
            guard !included.isEmpty else { return Expression(matchesNothing: true) }
            guard included.count <= Self.maxTypes else { throw Refusal.tooManyTypes }
            if let only = exactType(in: catalogue) {
                // The filter joins with `OR`, so the type's own items are asked for by `AND` where one condition
                // says what is left out: the type itself, or a single source. Several sources fall through to the
                // `types` key and `admitsType`.
                if leftOutTypes(in: catalogue).contains(only) {
                    return Expression(filter: try Self.text(of: [Self.condition(.type, .eq, only.rawValue)], join: .all))
                }
                guard !leaveOut.sources.isEmpty else { return Expression(matchesNothing: true) }
                if leaveOut.sources.count == 1, let source = leaveOut.sources.first {
                    let conditions = [Self.condition(.type, .eq, only.rawValue), Self.condition(.source, .eq, source)]
                    return Expression(filter: try Self.text(of: conditions, join: .all))
                }
            }
            reached = included.reduce(into: Set<TypeID>()) { $0.formUnion(Self.subtree(of: $1, in: catalogue)) }
        }
        let leftOut = leftOutTypes(in: catalogue).intersection(reached ?? Set(catalogue.itemTypes.keys))
        let conditions =
            leftOut.map(\.rawValue).sorted().map { Self.condition(.type, .eq, $0) }
            + leaveOut.sources.sorted().map { Self.condition(.source, .eq, $0) }
        guard !conditions.isEmpty else { return Expression(matchesNothing: true) }
        return Expression(types: included, filter: try Self.text(of: conditions, join: .any))
    }

    // MARK: Judging an item

    /// Whether the search keeps `item`: its type is chosen, it is not left out, and it is not archived or in the Inbox
    /// where those are turned off. The copy decides the same inside its call; this is for a list held locally.
    func admits(_ item: Item, in catalogue: Catalogue) -> Bool {
        admitsType(item.type, in: catalogue) && leftOutBy(item, in: catalogue) == nil && admitsOptions(item)
    }

    /// `items` as a typed search over the whole library keeps and leaves out: the items it keeps, and those the person's
    /// leave-out holds that an archived or Inbox choice does not already take away. An item of a type the chosen types
    /// do not take is in neither.
    func split(_ items: [Item], in catalogue: Catalogue) -> (kept: [Item], leftOut: [Item]) {
        var kept: [Item] = []
        var out: [Item] = []
        for item in items where admitsType(item.type, in: catalogue) && admitsOptions(item) {
            if leftOutBy(item, in: catalogue) == nil { kept.append(item) } else { out.append(item) }
        }
        return (kept, out)
    }

    /// Whether `item` is one Include Archived Items and Include Inbox Items let through.
    func admitsOptions(_ item: Item) -> Bool {
        (includesArchived || item.state != .archived) && (includesInbox || item.tier != .feed)
    }

    /// Whether an item of `type` is one the chosen types let through.
    func admitsType(_ type: TypeID, in catalogue: Catalogue) -> Bool {
        guard !types.isEmpty else { return true }
        let named = types.contains(type)
            || catalogue.ancestors(of: type).contains { types.contains($0) && typesWithSubtypes.contains($0) }
        return named != excludesTypes
    }

    /// Why the person's leave-out holds `item`: its source, else the type left out that it is or sits under. Nil for an
    /// item the leave-out does not hold.
    func leftOutBy(_ item: Item, in catalogue: Catalogue) -> LeftOutReason? {
        if let source = item.source, leaveOut.sources.contains(source) { return .source(source) }
        if leaveOut.types.contains(item.type) { return .type(item.type) }
        return catalogue.ancestors(of: item.type).first { leaveOut.types.contains($0) }.map(LeftOutReason.type)
    }

    enum LeftOutReason: Hashable, Sendable {
        case source(String)
        case type(TypeID)
    }

    // MARK: Writing the grammar

    /// The types left out with every type below them.
    private func leftOutTypes(in catalogue: Catalogue) -> Set<TypeID> {
        leaveOut.types.reduce(into: Set<TypeID>()) { $0.formUnion(Self.subtree(of: $1, in: catalogue)) }
    }

    /// The one type a search is limited to, taken without its subtypes and with subtypes below it to skip, or nil.
    private func exactType(in catalogue: Catalogue) -> TypeID? {
        guard !excludesTypes, types.count == 1, let only = types.first, catalogue.itemTypes[only] != nil,
            !typesWithSubtypes.contains(only), !catalogue.descendants(of: only).isEmpty
        else { return nil }
        return only
    }

    private static func subtree(of type: TypeID, in catalogue: Catalogue) -> Set<TypeID> {
        catalogue.descendants(of: type).union([type])
    }

    private static func condition(_ field: SystemField, _ op: FilterOperator, _ value: String) -> FilterCondition {
        FilterCondition(field: .system(field), operator: op, value: .text(value))
    }

    private static func text(of conditions: [FilterCondition], join: FilterJoin) throws -> String? {
        guard !conditions.isEmpty else { return nil }
        guard conditions.count <= maxConditions else { throw Refusal.tooManyConditions }
        do {
            return try FilterExpression(join: join, conditions: conditions).encoded()
        } catch {
            throw Refusal.refused(ViewDraft.message(of: error))
        }
    }
}
