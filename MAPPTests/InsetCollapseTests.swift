import CoreGraphics
import Testing
@testable import MAPP

/// The space a web page leaves for the item's header shrinks as the header scrolls away, so a fixed header the page draws
/// meets the toolbar.
struct InsetCollapseTests {
    private var collapse = InsetCollapse()

    @Test func aPageAtRestHasGivenUpNothingAndHasNotMoved() {
        #expect(collapse.consumed == 0)
        #expect(collapse.offset(scrollY: 0) == 0)
    }

    @Test mutating func scrollingGivesUpTheSpaceAsFarAsTheScrollGoesAndLowersTheScrollByTheSame() {
        let adjustment = collapse.scrolled(to: 30, space: 100)
        #expect(adjustment == .init(consumed: 30, scrollY: 0))
        #expect(collapse.consumed == 30)
        // The header follows the distance the person scrolled, not what is left of the page's own scroll.
        #expect(collapse.offset(scrollY: 0) == 30)
        #expect(collapse.distance == 30)
    }

    @Test mutating func theSpaceGivenUpNeverPassesTheSpaceThereWas() {
        _ = collapse.scrolled(to: 80, space: 100)
        let adjustment = collapse.scrolled(to: 60, space: 100)
        #expect(adjustment == .init(consumed: 100, scrollY: 40))
        #expect(collapse.offset(scrollY: 40) == 140)
        // Further scrolling is the page's own.
        #expect(collapse.scrolled(to: 90, space: 100) == nil)
        #expect(collapse.offset(scrollY: 90) == 190)
    }

    @Test mutating func scrollingBackUpTakesTheSpaceBack() {
        _ = collapse.scrolled(to: 100, space: 100)
        _ = collapse.scrolled(to: 50, space: 100)
        #expect(collapse.consumed == 100)
        // The page cannot scroll up from its start, so the person's pull shows as a negative offset.
        let adjustment = collapse.scrolled(to: -25, space: 100)
        #expect(adjustment == .init(consumed: 75, scrollY: 0))
        #expect(collapse.offset(scrollY: 0) == 75)
    }

    @Test mutating func aPageNoLongerOffsetByAScrollIsNotAdjustedAgain() {
        #expect(collapse.scrolled(to: 0, space: 100) == nil)
        #expect(collapse.scrolled(to: 0, space: 0) == nil)
    }

    @Test mutating func aSpaceThatShrinksTakesBackWhatIsNoLongerThere() {
        _ = collapse.scrolled(to: 100, space: 100)
        let adjustment = collapse.scrolled(to: 0, space: 60)
        #expect(adjustment == .init(consumed: 60, scrollY: 40))
    }

    @Test mutating func aNotificationThatReportsTheOffsetBeforeAnAdjustmentIsIgnored() {
        _ = collapse.scrolled(to: 30, space: 100)
        // The page still reports the 30 it had before it was moved to 0, once.
        #expect(collapse.scrolled(to: 30, space: 100) == nil)
        #expect(collapse.consumed == 30)
        // The next one is real.
        #expect(collapse.scrolled(to: 10, space: 100) == .init(consumed: 40, scrollY: 0))
    }

    @Test mutating func aNewPageStartsAgain() {
        _ = collapse.scrolled(to: 70, space: 100)
        collapse.reset()
        #expect(collapse.consumed == 0)
    }
}
