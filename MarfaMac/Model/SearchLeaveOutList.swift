import Foundation

/// What the Search page lists of what a server leaves out of search: each type and source chosen, in the order a person
/// reads them, and whether this Marfa still has it. A type or source the Marfa no longer has stays in the choice and is
/// marked missing so the person can remove it.
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
        /// The type's plural or source's name, including the last known name of a missing choice.
        let title: String
        /// The icon id of a type or source mark.
        let icon: String?
        /// Whether this Marfa still has it; false where it was answered and does not list it.
        let isKnown: Bool
        /// Items a source holds, where the server has said.
        let count: Int?

        var id: String {
            switch kind {
            case .type(let type): Addition.type(type).id
            case .subtype(let type, let parent): "subtype:\(parent.rawValue):\(type.rawValue)"
            case .source(let code): Addition.source(code).id
            }
        }
    }

    /// The name each type goes by in the list and the Add sheet: its plural, with its parent's in parentheses,
    /// "Tasks (Tickets)", where another type shown has the same one. `offered` are the types the sheet offers; the list's
    /// own types and the subtypes under them are told apart from those and from each other.
    static func labels(offered: [TypeID], leaveOut: SearchLeaveOut, catalogue: Catalogue) -> [TypeID: String] {
        var shown = Set(offered).union(leaveOut.types)
        for type in leaveOut.types { shown.formUnion(catalogue.descendants(of: type)) }
        return catalogue.displayLabels(for: shown, as: .many)
    }

    /// Types and sources by display name, with the subtypes excluded by a parent directly below it.
    /// `labels` are the names `labels(offered:leaveOut:catalogue:)` gave.
    static func entries(for leaveOut: SearchLeaveOut, catalogue: Catalogue, typesLoaded: Bool, sources: SourceDirectory, labels: [TypeID: String]) -> [Entry] {
        var groups: [(root: Entry, children: [Entry])] = []
        func name(_ type: TypeID) -> String {
            if catalogue.itemTypes[type] == nil {
                return leaveOut.names[Addition.type(type).id] ?? MissingChoice.typeName(type.rawValue)
            }
            return labels[type] ?? catalogue.plural(for: type)
        }
        func ascending(_ lhs: TypeID, _ rhs: TypeID) -> Bool { name(lhs).localizedStandardCompare(name(rhs)) == .orderedAscending }
        for type in leaveOut.types {
            let info = catalogue.itemTypes[type]
            let root = Entry(kind: .type(type), title: name(type), icon: info?.icon, isKnown: info != nil || !typesLoaded, count: nil)
            let below = catalogue.descendants(of: type).subtracting(leaveOut.types)
            let children = below.sorted(by: ascending).map { subtype in
                Entry(kind: .subtype(subtype, parent: type), title: name(subtype), icon: catalogue.icon(for: subtype), isKnown: true, count: nil)
            }
            groups.append((root, children))
        }
        for code in leaveOut.sources {
            let info = sources.info(code)
            let count = sources.counts?[code]
            // Once the server has answered, a source it neither names nor lists is one this Marfa no longer has.
            let isKnown = sources.counts == nil || sources.infos[code] != nil || (count ?? 0) > 0
            let name = sources.infos[code]?.name ?? leaveOut.names[Addition.source(code).id] ?? info.name
            groups.append((Entry(kind: .source(code), title: name, icon: info.mark, isKnown: isKnown, count: count), []))
        }
        return groups.sorted {
            let order = $0.root.title.localizedStandardCompare($1.root.title)
            return order == .orderedSame ? $0.root.id < $1.root.id : order == .orderedAscending
        }.flatMap { [$0.root] + $0.children }
    }

    /// A type offered in the Add sheet.
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

        var id: String {
            switch self {
            case .type(let type): "type:\(type.rawValue)"
            case .source(let code): "source:\(code)"
            }
        }
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
