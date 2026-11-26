import Foundation
import Testing
@testable import MarfaMac

/// What the app keeps on this Mac about each saved view: read without SwiftUI, and never lost to text it cannot read.
struct ViewLayoutsTests {
    private static let columns: [ItemTableColumn] = [.title, .type, .edited, .created]
    private static let view = ItemID("view-open-tasks")

    private static func defaults() -> UserDefaults {
        let defaults = ThrowawayDefaults.make("MarfaMac.ViewLayoutsTests")
        return defaults
    }

    private static func ids(_ columns: [ItemTableColumn]) -> [String] { columns.map(\.id) }

    // MARK: The store

    @Test func settingsComeBackAsTheyWereKept() {
        let defaults = Self.defaults()
        var columns = ViewProperties()
        columns.setShown(.created, true)
        ViewLayouts.update(in: defaults) {
            $0.set(ViewMacSettings(layout: .board, properties: columns, hidesEmptyGroups: true, widths: Data([1, 2])), for: Self.view)
        }
        let settings = ViewLayouts.stored(in: defaults).settings(for: Self.view)
        #expect(settings?.layout == .board)
        #expect(settings?.properties == columns)
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

    /// One view's settings this version cannot read stay where they are, beside the readable ones, through a change to
    /// another view; a change to that view sets its stored text aside first.
    @Test func oneViewThisVersionCannotReadStaysBesideTheRest() throws {
        let defaults = Self.defaults()
        defaults.set(#"{"view-a":{"layout":"board"},"view-later":"a later shape"}"#, forKey: ViewLayouts.key)
        #expect(ViewLayouts.stored(in: defaults).settings(for: ItemID("view-a"))?.layout == .board)
        ViewLayouts.update(in: defaults) { $0.set(ViewMacSettings(layout: .table), for: Self.view) }
        let text = try #require(defaults.string(forKey: ViewLayouts.key))
        #expect(text.contains(#""view-later":"a later shape""#))
        #expect(ViewLayouts.stored(in: defaults).settings(for: ItemID("view-a"))?.layout == .board)
        #expect(defaults.stringArray(forKey: ViewLayouts.setAsideKey) == nil)
        ViewLayouts.update(in: defaults) { $0.set(ViewMacSettings(layout: .list), for: ItemID("view-later")) }
        #expect(defaults.stringArray(forKey: ViewLayouts.setAsideKey) == [#""a later shape""#])
        #expect(ViewLayouts.stored(in: defaults).settings(for: ItemID("view-later"))?.layout == .list)
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
        #expect(layouts.settings(for: ItemID("view-c"))?.properties == ViewProperties())
    }

    @Test func aViewsStoredColumnsReadAsItsProperties() throws {
        let text = #"{"view-old":{"columns":{"order":["created","type"],"shown":{"created":true,"edited":false}}}}"#
        let settings = try #require(ViewLayouts(rawValue: text)?.settings(for: ItemID("view-old")))
        #expect(settings.properties == ViewProperties(order: ["created", "type"], shown: ["created": true, "edited": false]))
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

    @Test func aColumnMovesBeforeAnotherOrToTheEnd() {
        var columns = ViewProperties()
        columns.move("edited", before: "type", in: Self.columns)
        #expect(Self.ids(columns.arranged(Self.columns)) == ["title", "edited", "type", "created"])
        columns.move("edited", before: nil, in: Self.columns)
        #expect(Self.ids(columns.arranged(Self.columns)) == ["title", "type", "created", "edited"])
        // Back in the table's own order it is the same value as never having moved.
        columns.move("edited", before: "created", in: Self.columns)
        #expect(columns == ViewProperties())
    }

    @Test func movingAColumnKeepsTheSavedPlaceOfOneTheTableLacks() {
        // "gone" was arranged in a table that had it: before "edited" here, and before "type" there.
        var before = ViewProperties(order: ["gone", "edited", "type"])
        before.move("created", before: "edited", in: Self.columns)
        #expect(before.order == ["gone", "created", "edited", "type"])

        var between = ViewProperties(order: ["edited", "gone", "type"])
        between.move("created", before: "edited", in: Self.columns)
        #expect(between.order == ["created", "edited", "gone", "type"])

        // When the column comes back it is where it was left.
        let returned = Self.columns + [ItemTableColumn(id: "gone", label: "Gone", content: .created, style: .date)]
        #expect(Self.ids(between.arranged(returned)) == ["title", "created", "edited", "gone", "type"])
    }

    @Test func aColumnTheTableLacksKeepsTheOrderFromBeingForgotten() {
        var columns = ViewProperties(order: ["gone", "type", "edited", "created"])
        columns.move("created", before: "edited", in: Self.columns)
        #expect(columns.order == ["gone", "type", "created", "edited"])
        // Back in the table's own order, with the absent column still named, the order is kept.
        columns.move("edited", before: "created", in: Self.columns)
        #expect(columns.order == ["gone", "type", "edited", "created"])
    }

    @Test func aSavedColumnThatNoLongerExistsIsIgnored() {
        let columns = ViewProperties(order: ["gone", "edited", "type"], shown: ["gone": true, "created": true])
        #expect(Self.ids(columns.arranged(Self.columns)) == ["title", "edited", "type", "created"])
        #expect(Self.ids(columns.shownColumns(Self.columns)) == ["title", "edited", "type", "created"])
    }

    @Test func aColumnTheOrderNamesTwiceIsShownOnce() {
        let columns = ViewProperties(order: ["edited", "edited"])
        #expect(Self.ids(columns.arranged(Self.columns)) == ["title", "edited", "type", "created"])
    }
}
