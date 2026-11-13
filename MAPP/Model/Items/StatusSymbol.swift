import Foundation

/// The mark a status is drawn with, wherever the app shows one: the SF Symbols Reminders uses, by the group the type
/// puts the status word in. The word stays the type's own. A status no group claims draws as not started.
nonisolated enum StatusSymbol: String, CaseIterable, Hashable, Sendable {
    case notStarted, inProgress, completed, canceled

    /// How a symbol is colored: the system blue, or one of the window's two greys for secondary and tertiary text.
    enum Tint: String, Hashable, Sendable, Encodable {
        case blue, secondary, tertiary
    }

    init(group: StatusGroup?) {
        switch group {
        case .inProgress: self = .inProgress
        case .completed: self = .completed
        case .canceled: self = .canceled
        case .notStarted, nil: self = .notStarted
        }
    }

    var systemName: String {
        switch self {
        case .notStarted: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .completed: "largecircle.fill.circle"
        case .canceled: "xmark.circle"
        }
    }

    var tint: Tint {
        switch self {
        case .notStarted: .secondary
        case .inProgress: .blue
        case .completed: .secondary
        case .canceled: .tertiary
        }
    }

    /// The four symbol names, for the page to be sent.
    static let systemNames = allCases.map(\.systemName)
}
