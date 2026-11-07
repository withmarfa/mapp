import Foundation
import Testing
@testable import MAPP

/// What MAPP keeps on this Mac about each saved view: read without SwiftUI, and never lost to text it cannot read.
struct ViewLayoutsTests {
    private static let columns: [ItemTableColumn] = [.title, .type, .edited, .created]
    private static let view = ItemID("view-open-tasks")

    private static func defaults() -> UserDefaults {
        let suite = "MAPP.ViewLayoutsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func ids(_ columns: [ItemTableColumn]) -> [String] { columns.map(\.id) }

    // MARK: The store

    @Test func settingsComeBackAsTheyWereKept() {
        let defaults = Self.defaults()
        var columns = ViewColumns()
        columns.setShown(.created, true)
        ViewLayouts.update(in: defaults) {
            $0.set(ViewMacSettings(layout: .board, columns: columns, hidesEmptyGroups: true, widths: Data([1, 2])), for: Self.view)
        }
        let settings = ViewLayouts.stored(in: defaults).settings(for: Self.view)
        #expect(settings?.layout == .board)
        #expect(settings?.columns == columns)
        #expect(settings?.hidesEmptyGroups == true)
        #expect(settings?.widths == Data([1, 2]))
        #expect(ViewLayouts.stored(in: defaults).settings(for: ItemID("view-other")) == nil)
    }

    @Test func textThatCannotBeReadIsNoSettingsAndIsKeptAside() {
        let defaults = Self.defaults()
        defaults.set("{not json", forKey: ViewLayouts.key)
        #expect(ViewLayouts.stored(in: defaults).views.isEmpty)
        ViewLayouts.update(in: defaults) { $0.set(ViewMacSettings(layout: .table), for: Self.view) }
        #expect(defaults.stringArray(forKey: ViewLayouts.setAsideKey) == ["{not json"])
        #expect(ViewLayouts.stored(in: defaults).settings(for: Self.view)?.layout == .table)
    }

    @Test func nothingStoredIsNothingToSetAside() {
        let defaults = Self.defaults()
        ViewLayouts.update(in: defaults) { $0.set(ViewMacSettings(), for: Self.view) }
        #expect(defaults.stringArray(forKey: ViewLayouts.setAsideKey) == nil)
    }

    @Test func aFieldThisVersionDoesNotReadNeverVoidsTheRest() throws {
        let text = #"{"view-a":{"layout":"board","hidesEmptyGroups":true,"cards":{"size":"large"}},"view-b":{"layout":"cinema"},"view-c":{"columns":5}}"#
        let layouts = try #require(ViewLayouts(rawValue: text))
        #expect(layouts.settings(for: ItemID("view-a"))?.layout == .board)
        #expect(layouts.settings(for: ItemID("view-a"))?.hidesEmptyGroups == true)
        // A layout this version lacks reads as the list, as everywhere else.
        #expect(layouts.settings(for: ItemID("view-b"))?.layout == .list)
        #expect(layouts.settings(for: ItemID("view-c"))?.columns == ViewColumns())
    }

    @Test func aDeletedViewIsForgotten() {
        let defaults = Self.defaults()
        ViewLayouts.update(in: defaults) {
            $0.set(ViewMacSettings(layout: .table), for: Self.view)
            $0.set(ViewMacSettings(layout: .board), for: ItemID("view-b"))
        }
        ViewLayouts.update(in: defaults) { $0.forget(Self.view) }
        #expect(ViewLayouts.stored(in: defaults).settings(for: Self.view) == nil)
        #expect(ViewLayouts.stored(in: defaults).settings(for: ItemID("view-b"))?.layout == .board)
    }

    @Test func widthsAreNotAChoiceASaveKeeps() {
        let a = ViewMacSettings(layout: .table, widths: Data([1]))
        let b = ViewMacSettings(layout: .table, widths: Data([2]))
        #expect(a != b)
        #expect(a.sameChoices(as: b))
        #expect(!a.sameChoices(as: ViewMacSettings(layout: .board)))
    }

    // MARK: Columns

    @Test func theColumnsStartAsTheTableLaysThemOut() {
        let columns = ViewColumns()
        #expect(Self.ids(columns.arranged(Self.columns)) == ["title", "type", "edited", "created"])
        #expect(Self.ids(columns.shownColumns(Self.columns)) == ["title", "type", "edited"])
    }

    @Test func aColumnIsShownOrHiddenAndTheSameArrangementIsTheSameValue() {
        var columns = ViewColumns()
        columns.setShown(.created, true)
        #expect(Self.ids(columns.shownColumns(Self.columns)).contains("created"))
        columns.setShown(.created, false)
        #expect(columns == ViewColumns())
        columns.setShown(.type, false)
        #expect(!Self.ids(columns.shownColumns(Self.columns)).contains("type"))
    }

    @Test func theNameIsAlwaysShownAndFirst() {
        var columns = ViewColumns()
        columns.setShown(.title, false)
        columns.move("edited", before: "title", in: Self.columns)
        #expect(Self.ids(columns.shownColumns(Self.columns)).first == "title")
        #expect(Self.ids(columns.arranged(Self.columns)).first == "title")
    }

    @Test func aColumnMovesBeforeAnotherOrToTheEnd() {
        var columns = ViewColumns()
        columns.move("edited", before: "type", in: Self.columns)
        #expect(Self.ids(columns.arranged(Self.columns)) == ["title", "edited", "type", "created"])
        columns.move("edited", before: nil, in: Self.columns)
        #expect(Self.ids(columns.arranged(Self.columns)) == ["title", "type", "created", "edited"])
        // Back in the table's own order it is the same value as never having moved.
        columns.move("edited", before: "created", in: Self.columns)
        #expect(columns == ViewColumns())
    }

    @Test func aSavedColumnThatNoLongerExistsIsIgnored() {
        let columns = ViewColumns(order: ["gone", "edited", "type"], shown: ["gone": true, "created": true])
        #expect(Self.ids(columns.arranged(Self.columns)) == ["title", "edited", "type", "created"])
        #expect(Self.ids(columns.shownColumns(Self.columns)) == ["title", "edited", "type", "created"])
    }

    @Test func aColumnTheOrderNamesTwiceIsShownOnce() {
        let columns = ViewColumns(order: ["edited", "edited"])
        #expect(Self.ids(columns.arranged(Self.columns)) == ["title", "edited", "type", "created"])
    }
}
