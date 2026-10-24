import Foundation
import Marfa

nonisolated struct LibraryFill: Hashable, Sendable {
    enum State: Hashable, Sendable { case filling, updating, complete }
    var state: State
    var listed: UInt64?
    var expected: UInt64?

    init(state: State, listed: UInt64? = nil, expected: UInt64? = nil) {
        self.state = state
        self.listed = listed
        self.expected = expected
    }

    init(_ status: Status, completeness: Completeness) {
        state = switch completeness {
        case .partial: .filling
        case .stale: .updating
        case .complete: status.hydration == .complete ? .complete : .filling
        }
        listed = status.itemsListed
        expected = status.itemsExpected
    }
}

nonisolated enum FillWording {
    static func line(_ fill: LibraryFill) -> String {
        if let listed = fill.listed, let expected = fill.expected {
            return String(localized: "\(listed) of \(expected) items listed")
        }
        if let listed = fill.listed { return String(localized: "Items listed: \(listed)") }
        return String(localized: "Listing items…")
    }
}
