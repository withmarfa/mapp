import Foundation

/// Where an item stands, as every type with a status field puts it. The four groups are the same for every type, so
/// the app can tell what is open, active or finished without knowing a type's own words.
nonisolated enum StatusGroup: String, Hashable, Sendable, CaseIterable, Comparable {
    case inProgress = "in_progress"
    case notStarted = "not_started"
    case completed
    case canceled

    /// Whether the work is over, so its group starts folded away.
    var isFinished: Bool { self == .completed || self == .canceled }

    /// The order groups are listed and sorted in: what is under way leads, finished work follows.
    static func < (lhs: StatusGroup, rhs: StatusGroup) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// One word a type's status field takes, with the group the type puts it in.
nonisolated struct StatusWord: Hashable, Sendable {
    let value: String
    let group: StatusGroup
}

/// Where a table lists a status that no group claims: a word its type does not declare.
nonisolated enum StatusBucket: Hashable, Sendable {
    case group(StatusGroup)
    case other

    /// The identifier of the table group it makes.
    var id: String {
        switch self {
        case .group(let group): group.rawValue
        case .other: "other"
        }
    }

    init?(id: String) {
        if id == "other" { self = .other } else if let group = StatusGroup(rawValue: id) { self = .group(group) } else { return nil }
    }

    /// The position among the groups of a table: the four in their order, then the words nobody declares.
    var rank: Int {
        switch self {
        case .group(let group): StatusGroup.allCases.firstIndex(of: group)!
        case .other: StatusGroup.allCases.count
        }
    }

    var isFinished: Bool {
        if case .group(let group) = self { group.isFinished } else { false }
    }

    var title: String {
        switch self {
        case .group(.inProgress): String(localized: "In Progress")
        case .group(.notStarted): String(localized: "Not Started")
        case .group(.completed): String(localized: "Completed")
        case .group(.canceled): String(localized: "Canceled")
        case .other: String(localized: "Other")
        }
    }
}
