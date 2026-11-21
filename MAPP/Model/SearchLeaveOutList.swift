import Foundation

/// What the Search page lists of what a server leaves out of search: each type and source chosen, in the order a person
/// reads them, and whether this Marfa still has it. A type or source the Marfa no longer has stays in the choice and is
/// shown as unknown, so it can be removed; it is never dropped on its own.
nonisolated enum SearchLeaveOutList {
    nonisolated struct Entry: Identifiable, Hashable, Sendable {
        nonisolated enum Kind: Hashable, Sendable {
            /// A type left out, with how many of its subtypes go with it.
            case type(TypeID)
            /// A subtype that goes with `parent`, which the person did not choose on its own.
            case subtype(TypeID, parent: TypeID)
            case source(String)
        }

        let kind: Kind
        /// The name to show: the type's plural, the source's name, or the identifier or code of one the Marfa lacks.
        let title: String
        /// The icon id of a type or source mark.
        let icon: String?
        /// Whether this Marfa still has it; false where it was answered and does not list it.
        let isKnown: Bool
        /// Items a source holds, where the server has said.
        let count: Int?

        var id: String {
            switch kind {
            case .type(let type): "type:\(type.rawValue)"
            case .subtype(let type, let parent): "subtype:\(parent.rawValue):\(type.rawValue)"
            case .source(let code): "source:\(code)"
            }
        }
    }

    /// The entries for `leaveOut`, types first and then sources, each group by name, a type's subtypes under it.
    static func entries(for leaveOut: SearchLeaveOut, catalogue: Catalogue, sources: SourceDirectory) -> [Entry] {
        var entries: [Entry] = []
        let held = !catalogue.itemTypes.isEmpty
        let types = leaveOut.types.sorted { catalogue.plural(for: $0).localizedStandardCompare(catalogue.plural(for: $1)) == .orderedAscending }
        for type in types {
            let info = catalogue.itemTypes[type]
            entries.append(Entry(kind: .type(type), title: catalogue.plural(for: type), icon: info?.icon, isKnown: info != nil || !held, count: nil))
            let below = catalogue.descendants(of: type).subtracting(leaveOut.types)
            for subtype in below.sorted(by: { catalogue.plural(for: $0).localizedStandardCompare(catalogue.plural(for: $1)) == .orderedAscending }) {
                entries.append(Entry(
                    kind: .subtype(subtype, parent: type), title: catalogue.plural(for: subtype), icon: catalogue.icon(for: subtype),
                    isKnown: true, count: nil))
            }
        }
        let codes = leaveOut.sources.sorted { sources.name($0).localizedStandardCompare(sources.name($1)) == .orderedAscending }
        for code in codes {
            let info = sources.info(code)
            let count = sources.counts?[code]
            // Once the server has answered, a source it neither names nor lists is one this Marfa no longer has.
            let isKnown = sources.counts == nil || sources.infos[code] != nil || (count ?? 0) > 0
            entries.append(Entry(kind: .source(code), title: info.name, icon: info.mark, isKnown: isKnown, count: count))
        }
        return entries
    }

    /// The types a person may still leave out: none already left out or under one that is, in the order the sidebar lists them.
    static func typesToAdd(_ counts: [ItemTypeCount], leaveOut: SearchLeaveOut, catalogue: Catalogue) -> [ItemTypeCount] {
        counts.filter { count in
            !leaveOut.types.contains(count.id) && !catalogue.ancestors(of: count.id).contains(where: leaveOut.types.contains)
        }
    }

    /// The sources a person may still leave out: the ones the library lists that are not left out.
    static func sourcesToAdd(_ counts: [SourceCount], leaveOut: SearchLeaveOut) -> [SourceCount] {
        counts.filter { !leaveOut.sources.contains($0.code) }
    }
}
