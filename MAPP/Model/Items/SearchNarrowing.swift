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
/// The grammar's `types` key takes each type with its subtypes and its `type` field compares one identifier alone, so a
/// type kept without its subtypes, and a type left out with its own, are written as `type neq` conditions for the
/// types below it. A filter joins its conditions with one of `AND` or `OR` and holds at most ten.
nonisolated struct SearchNarrowing: Hashable, Sendable {
    /// The types a search is limited to, or, with `excludesTypes`, the types it skips.
    var types: Set<TypeID> = []
    /// The types of `types` whose subtypes count too (Include Subtypes).
    var typesWithSubtypes: Set<TypeID> = []
    var excludesTypes = false
    var leaveOut = SearchLeaveOut()

    static let none = SearchNarrowing()

    var isEmpty: Bool { types.isEmpty && leaveOut.isEmpty }

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
            case .tooManyConditions: String(localized: "More types and sources are left out of search than one search can skip.")
            case .refused(let message): message
            }
        }
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
