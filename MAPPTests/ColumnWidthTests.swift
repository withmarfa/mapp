import Foundation
import Testing

@testable import MAPP

struct ColumnWidthTests {
    @Test func builtInDefaultsAreTheAgreedWidths() {
        #expect(ColumnWidth.sidebar.defaultWidth == 230)
        #expect(ColumnWidth.list.defaultWidth == 350)
        #expect(ColumnWidth.settings.defaultWidth == 290)
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
        #expect(ColumnWidth.settings.stored(in: defaults) == 290)
    }

    @Test func eachColumnHasItsOwnKeyAndResetClearsThemWithTheInterfaceKeys() {
        #expect(Set(ColumnWidth.allCases.map(\.key)).count == 3)
        for column in ColumnWidth.allCases { #expect(InterfaceKey.all.contains(column.key)) }
    }
}
