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

    /// The name each type goes by in the list and in the add menu: its plural, with its parent's in parentheses,
    /// "Tasks (Tickets)", where another type shown has the same one. `offered` are the types the menu offers; the list's
    /// own types and the subtypes under them are told apart from those and from each other.
    static func labels(offered: [TypeID], leaveOut: SearchLeaveOut, catalogue: Catalogue) -> [TypeID: String] {
        var shown = Set(offered).union(leaveOut.types)
        for type in leaveOut.types { shown.formUnion(catalogue.descendants(of: type)) }
        return catalogue.displayLabels(for: shown, as: .many)
    }

    /// The entries for `leaveOut`, types first and then sources, each group by name, a type's subtypes under it.
    /// `labels` are the names `labels(offered:leaveOut:catalogue:)` gave.
    static func entries(for leaveOut: SearchLeaveOut, catalogue: Catalogue, sources: SourceDirectory, labels: [TypeID: String]) -> [Entry] {
        var entries: [Entry] = []
        let held = !catalogue.itemTypes.isEmpty
        func name(_ type: TypeID) -> String { labels[type] ?? catalogue.plural(for: type) }
        func ascending(_ lhs: TypeID, _ rhs: TypeID) -> Bool { name(lhs).localizedStandardCompare(name(rhs)) == .orderedAscending }
        for type in leaveOut.types.sorted(by: ascending) {
            let info = catalogue.itemTypes[type]
            entries.append(Entry(kind: .type(type), title: name(type), icon: info?.icon, isKnown: info != nil || !held, count: nil))
            let below = catalogue.descendants(of: type).subtracting(leaveOut.types)
            for subtype in below.sorted(by: ascending) {
                entries.append(Entry(
                    kind: .subtype(subtype, parent: type), title: name(subtype), icon: catalogue.icon(for: subtype), isKnown: true, count: nil))
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

    /// A type the add menu offers.
    nonisolated struct TypeChoice: Identifiable, Hashable, Sendable {
        let id: TypeID
        /// The name in the list, which the menu repeats.
        let label: String
        /// The subtypes that would be left out with it.
        let subtypes: Int

        /// What the menu says: "Notes, with 2 subtypes", so the person sees that more than one type goes.
        var title: String {
            subtypes == 0 ? label : String(localized: "\(label), with \(subtypes) subtypes")
        }
    }

    /// The types a person may still leave out: none already left out or under one that is, A to Z as the list is.
    static func typesToAdd(_ counts: [ItemTypeCount], leaveOut: SearchLeaveOut, catalogue: Catalogue, labels: [TypeID: String]) -> [TypeChoice] {
        counts
            .filter { !leaveOut.types.contains($0.id) && !catalogue.ancestors(of: $0.id).contains(where: leaveOut.types.contains) }
            .map { TypeChoice(id: $0.id, label: labels[$0.id] ?? $0.label, subtypes: catalogue.descendants(of: $0.id).count) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    /// The sources a person may still leave out: the ones the library lists that are not left out, A to Z.
    static func sourcesToAdd(_ counts: [SourceCount], leaveOut: SearchLeaveOut) -> [SourceCount] {
        counts.filter { !leaveOut.sources.contains($0.code) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// What a person may add to the leave-out.
    nonisolated enum Addition: Hashable, Sendable {
        case type(TypeID)
        case source(String)
    }

    /// Whether `addition` still lets a search be asked: the leave-out with it makes no more conditions than one filter
    /// holds (`SearchNarrowing.maxConditions`). A type counts for each of its subtypes the copy holds, since each is
    /// left out with it.
    static func fits(_ addition: Addition, in leaveOut: SearchLeaveOut, catalogue: Catalogue) -> Bool {
        var next = leaveOut
        switch addition {
        case .type(let type): next.types.insert(type)
        case .source(let code): next.sources.insert(code)
        }
        return SearchNarrowing(leaveOut: next).leaveOutConditionCount(in: catalogue) <= SearchNarrowing.maxConditions
    }
}
