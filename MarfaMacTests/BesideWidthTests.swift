import Foundation
import Testing

@testable import MarfaMac

struct BesideWidthTests {
    @Test func theColumnStartsAtTheStandardWidthAndKeepsWhatThePersonChose() {
        let defaults = ThrowawayDefaults.make("BesideWidthTests.keeps")
        #expect(BesideWidth.stored(in: defaults) == BesideWidth.standard)
        BesideWidth.store(520, in: defaults)
        #expect(BesideWidth.stored(in: defaults) == 520)
    }

    @Test func aWidthOutsideTheRangeOrNotANumberIsBroughtBackIn() {
        let defaults = ThrowawayDefaults.make("BesideWidthTests.range")
        defaults.set(40.0, forKey: BesideWidth.key)
        #expect(BesideWidth.stored(in: defaults) == BesideWidth.narrowest)
        defaults.set(5000.0, forKey: BesideWidth.key)
        #expect(BesideWidth.stored(in: defaults) == BesideWidth.widest)
        defaults.set("wide", forKey: BesideWidth.key)
        #expect(BesideWidth.stored(in: defaults) == BesideWidth.standard)
        defaults.set(Double.nan, forKey: BesideWidth.key)
        #expect(BesideWidth.stored(in: defaults) == BesideWidth.standard)
    }

    @Test func draggingTheDividerTowardTheListWidensThePage() {
        #expect(BesideWidth.dragged(from: 440, by: -60) == 500)
        #expect(BesideWidth.dragged(from: 440, by: 60) == 380)
        #expect(BesideWidth.dragged(from: 440, by: 900) == BesideWidth.narrowest)
        #expect(BesideWidth.dragged(from: 440, by: -900) == BesideWidth.widest)
    }

    @Test func theLayoutKeepsItsLeastBeforeThePageGivesWay() {
        let keeps = BesideColumn.layoutKeeps
        // Plenty of room: the page has the width chosen.
        #expect(BesideColumn.pageWidth(in: 1600, chosen: 500) == 500)
        // Less room than the layout and the chosen page need: the page gives way, down to its narrowest.
        #expect(BesideColumn.pageWidth(in: keeps + 400, chosen: 500) == 400)
        #expect(BesideColumn.pageWidth(in: keeps + 100, chosen: 500) == BesideColumn.narrowest)
        // A shared width under twice the narrowest is split in half.
        #expect(BesideColumn.pageWidth(in: 500, chosen: 500) == 250)
        // Not yet measured: the chosen width, kept inside the range.
        #expect(BesideColumn.pageWidth(in: 0, chosen: 500) == 500)
        #expect(BesideColumn.pageWidth(in: 0, chosen: 10) == BesideWidth.narrowest)
    }

    @Test func aNarrowWindowLimitsWhatShowsAndNotWhatThePersonChose() {
        let defaults = ThrowawayDefaults.make("BesideWidthTests.narrow")
        BesideWidth.store(560, in: defaults)
        let chosen = BesideWidth.stored(in: defaults)
        #expect(chosen == 560)
        // In a window of 1000 the page shows at 400, but a drag of one point moves the choice from 560, not from 400.
        #expect(BesideColumn.pageWidth(in: 1000, chosen: chosen) == 400)
        let dragged = BesideWidth.clamped(BesideWidth.dragged(from: chosen, by: 1))
        #expect(dragged == 559)
        BesideWidth.store(dragged, in: defaults)
        #expect(BesideWidth.stored(in: defaults) == 559)
        #expect(BesideColumn.pageWidth(in: 1600, chosen: BesideWidth.stored(in: defaults)) == 559)
        // A double-click stores the standard width, whatever room the window has.
        BesideWidth.store(BesideWidth.clamped(BesideWidth.standard), in: defaults)
        #expect(BesideWidth.stored(in: defaults) == 440)
    }

    @Test func theWidthIsAMacOnlySettingTheAppKnows() {
        #expect(BesideWidth.key == InterfaceKey.besideWidth)
        #expect(InterfaceKey.all.contains(InterfaceKey.besideWidth))
        #expect(PreferencesMap.staysOnMac.contains(InterfaceKey.besideWidth))
        #expect(MacSettings.keys.contains(InterfaceKey.besideWidth))
    }
}

struct RowLinkLimitTests {
    private func links(_ count: Int) -> [Int] { Array(0..<count) }

    @Test func aRowShowsAtMostThreeLinksThenHowManyAreLeft() {
        let few = PageHead.linksShown(links(3), isOpen: false)
        #expect(few.shown == [0, 1, 2] && few.hidden == 0)
        let many = PageHead.linksShown(links(28), isOpen: false)
        #expect(many.shown == [0, 1, 2] && many.hidden == 25)
    }

    @Test func openingTheRowShowsEveryLink() {
        let all = PageHead.linksShown(links(28), isOpen: true)
        #expect(all.shown.count == 28 && all.hidden == 0)
    }

    @Test func theEditorsPageIsToldWhereTheRowFoldsAndWhatItSays() throws {
        let targets = (0..<5).map { PropertyRow.Target(title: "Item \($0)", item: ItemID("i\($0)")) }
        let row = PropertyRow(id: "references", label: "References", value: .items(targets))
        let json = try #require(String(data: JSONEncoder().encode(row), encoding: .utf8))
        #expect(json.contains(#""itemsAfter":3"#))
        #expect(json.contains(PageHead.moreLinksText(2)))
    }
}
