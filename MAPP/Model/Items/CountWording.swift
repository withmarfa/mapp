import Foundation

/// What a count says, in words: the chip of a row or a card, the cell of a table and the help tag that splits a
/// progress into what is finished and what is not. A count that has nothing to say, because Marfa has not answered or
/// the answer is nothing to count, says nothing at all: never a zero, a dash or an old number.
nonisolated enum CountWording {
    /// The chip text, or nil where there is nothing to say. `hasStatus` is whether the item's own type has a status, whose
    /// children are then subtasks rather than items.
    static func text(of fact: CountFact, answer: ItemCountAnswer?, hasStatus: Bool) -> String? {
        guard let answer else { return nil }
        switch fact {
        case .children:
            guard answer.total > 0 else { return nil }
            return hasStatus ? String(localized: "\(answer.total) subtasks") : String(localized: "\(answer.total) items")
        case .members:
            guard answer.total > 0 else { return nil }
            return String(localized: "\(answer.total) items")
        case .progress:
            guard let groups = answer.groups, groups.withStatus > 0 else { return nil }
            return String(localized: "\(groups.finished) of \(groups.withStatus) done")
        case .rows(let table):
            guard answer.total > 0 else { return nil }
            return "\(answer.total) \(answer.total == 1 ? singular(of: table) : table)"
        }
    }

    /// What the help tag says: the children by status group, with completed and canceled apart, since both count as done.
    /// Nil for a count with no groups to split.
    static func help(of fact: CountFact, answer: ItemCountAnswer?) -> String? {
        guard let answer, let groups = answer.groups, groups.withStatus > 0 else { return nil }
        switch fact {
        case .children, .progress: break
        case .members, .rows: return nil
        }
        var parts: [String] = []
        if groups.completed > 0 { parts.append(String(localized: "\(groups.completed) completed")) }
        if groups.canceled > 0 { parts.append(String(localized: "\(groups.canceled) canceled")) }
        if groups.inProgress > 0 { parts.append(String(localized: "\(groups.inProgress) in progress")) }
        if groups.notStarted > 0 { parts.append(String(localized: "\(groups.notStarted) not started")) }
        let without = answer.total - groups.withStatus
        if without > 0 { parts.append(String(localized: "\(without) with no status")) }
        return parts.joined(separator: ", ")
    }

    /// The heading of a count's table column.
    static func heading(of fact: CountFact, hasStatus: Bool) -> String {
        switch fact {
        case .children: hasStatus ? String(localized: "Subtasks") : String(localized: "Items")
        case .progress: String(localized: "Progress")
        case .members: String(localized: "Items")
        case .rows(let table): table.prefix(1).uppercased() + table.dropFirst()
        }
    }

    /// A table's name as Marfa gives it is plural ("messages"); one row says it in the singular.
    private static func singular(of table: String) -> String {
        table.count > 1 && table.hasSuffix("s") ? String(table.dropLast()) : table
    }
}
