import Foundation
import Testing

@testable import MAPP

struct ColumnWidthTests {
    @Test func builtInDefaultsAreTheAgreedWidths() {
        #expect(ColumnWidth.sidebar.defaultWidth == 230)
        #expect(ColumnWidth.list.defaultWidth == 330)
        #expect(ColumnWidth.settings.defaultWidth == 280)
    }

    @Test func everyDefaultLiesInsideItsColumnsLimits() {
        for column in ColumnWidth.allCases {
            #expect(column.range.contains(column.defaultWidth))
        }
    }

    @Test func aMissingOrUnusableValueUsesTheDefault() {
        for column in ColumnWidth.allCases {
            #expect(column.resolved(nil) == column.defaultWidth)
            #expect(column.resolved(.nan) == column.defaultWidth)
            #expect(column.resolved(.infinity) == column.defaultWidth)
        }
    }

    @Test func aValueOutsideTheLimitsIsClamped() {
        for column in ColumnWidth.allCases {
            #expect(column.resolved(-5) == column.range.lowerBound)
            #expect(column.resolved(100_000) == column.range.upperBound)
            #expect(column.resolved(Double(column.range.lowerBound)) == column.range.lowerBound)
        }
    }

    @Test func aValueInsideTheLimitsIsKept() {
        #expect(ColumnWidth.list.resolved(400) == 400)
    }

    @Test func storedValuesAreReadFromDefaultsAndClamped() throws {
        let suite = "ColumnWidthTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ColumnWidth.sidebar.stored(in: defaults) == 230)
        defaults.set(300.0, forKey: ColumnWidth.sidebar.key)
        defaults.set(9_999.0, forKey: ColumnWidth.list.key)
        defaults.set("wide", forKey: ColumnWidth.settings.key)
        #expect(ColumnWidth.sidebar.stored(in: defaults) == 300)
        #expect(ColumnWidth.list.stored(in: defaults) == 480)
        #expect(ColumnWidth.settings.stored(in: defaults) == 280)
    }

    @Test func eachColumnHasItsOwnKeyAndResetClearsThemWithTheInterfaceKeys() {
        #expect(Set(ColumnWidth.allCases.map(\.key)).count == 3)
        for column in ColumnWidth.allCases { #expect(InterfaceKey.all.contains(column.key)) }
    }
}

@MainActor
struct ColumnWidthTrackerTests {
    private func tracker() -> ColumnWidthTracker {
        let suite = "ColumnWidthTrackerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        return ColumnWidthTracker(defaults: defaults)
    }

    @Test func aNewWindowStartsEachColumnAtItsDefault() {
        let tracker = tracker()
        for column in ColumnWidth.allCases { #expect(tracker.width(of: column) == column.defaultWidth) }
    }

    @Test func aDraggedWidthIsKeptAndOneOutsideTheLimitsIsNot() {
        let tracker = tracker()
        tracker.record(410, for: .list)
        tracker.record(12, for: .list)
        tracker.record(900, for: .list)
        tracker.record(.nan, for: .list)
        #expect(tracker.width(of: .list) == 410)
    }

    @Test func eachColumnKeepsItsOwnDraggedWidth() {
        let tracker = tracker()
        tracker.record(300, for: .settings)
        #expect(tracker.width(of: .settings) == 300)
        #expect(tracker.width(of: .list) == 330)
        #expect(tracker.width(of: .sidebar) == 230)
    }

    @Test func columnWidthsComeFromTheDividerPositions() {
        #expect(ColumnWidthTracker.columnWidths(rightEdges: [230, 580, 1700]) == [230, 350, 1120])
        #expect(ColumnWidthTracker.columnWidths(rightEdges: [-230, 350, 1700]) == [0, 350, 1350])
        #expect(ColumnWidthTracker.columnWidths(rightEdges: []).isEmpty)
    }

    @Test func dividersAreSetForTheVisibleColumnsOnly() {
        let both = DividerDragView.dividerPositions(widths: [230, 350], hidden: [false, false, false])
        #expect(both.map(\.index) == [0, 1])
        #expect(both.map(\.position) == [230, 580])
        let noSidebar = DividerDragView.dividerPositions(widths: [230, 350], hidden: [true, false, false])
        #expect(noSidebar.map(\.index) == [1])
        #expect(noSidebar.map(\.position) == [350])
        let twoColumns = DividerDragView.dividerPositions(widths: [230], hidden: [false, false])
        #expect(twoColumns.map(\.index) == [0])
        #expect(DividerDragView.dividerPositions(widths: [230, 350], hidden: [false, false]).map(\.index) == [0])
    }

    @Test func onlyTheWindowInFrontIsRead() {
        let registry = ColumnWidthRegistry()
        let first = tracker(), second = tracker()
        registry.windowBecame(active: true, tracker: first)
        registry.windowBecame(active: true, tracker: second)
        registry.windowBecame(active: false, tracker: first)
        #expect(registry.front === second)
        registry.windowBecame(active: false, tracker: second)
        #expect(registry.front == nil)
    }
}
