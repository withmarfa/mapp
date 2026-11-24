import Foundation
import Testing

@testable import MarfaMac

struct ColumnWidthTests {
    @Test func eachColumnHasItsOwnKeyAndResetClearsThemWithTheInterfaceKeys() {
        #expect(Set(ColumnWidth.allCases.map(\.key)).count == 2)
        for column in ColumnWidth.allCases { #expect(InterfaceKey.all.contains(column.key)) }
    }
}

@MainActor
struct ColumnWidthTrackerTests {
    private func tracker() -> ColumnWidthTracker {
        let defaults = ThrowawayDefaults.make("ColumnWidthTrackerTests")
        return ColumnWidthTracker(defaults: defaults)
    }

    @Test func eachColumnKeepsItsOwnDraggedWidth() {
        let tracker = tracker()
        tracker.record(300, for: .sidebar)
        #expect(tracker.width(of: .sidebar) == 300)
        #expect(tracker.width(of: .list) == 330)
    }
}
