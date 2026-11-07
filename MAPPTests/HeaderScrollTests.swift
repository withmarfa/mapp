import CoreGraphics
import Testing
@testable import MAPP

/// The toolbar names an item once its page has scrolled the header away, whichever kind of page it is. These pin what
/// counts as away, and that the window keeps the state by item, so one item's page never speaks for another's.
struct HeaderScrollTests {
    private let first = ItemID("first")
    private let second = ItemID("second")

    @Test func aHeaderIsAwayOnceThePageHasScrolledAsFarAsItIsTall() {
        #expect(!HeaderScroll.isAway(scrolled: 0, headerHeight: 120))
        #expect(!HeaderScroll.isAway(scrolled: 119.5, headerHeight: 120))
        #expect(HeaderScroll.isAway(scrolled: 120, headerHeight: 120))
        #expect(HeaderScroll.isAway(scrolled: 900, headerHeight: 120))
    }

    @Test func aPagePulledPastItsStartHasNotScrolledItsHeaderAway() {
        #expect(!HeaderScroll.isAway(scrolled: -40, headerHeight: 120))
    }

    @Test func aHeaderNotYetMeasuredIsNeverAway() {
        #expect(!HeaderScroll.isAway(scrolled: 0, headerHeight: 0))
        #expect(!HeaderScroll.isAway(scrolled: 300, headerHeight: 0))
    }

    @Test func theToolbarLineShowsOnlyWhilePageIsUnderIt() {
        #expect(!HeaderScroll.isUnderToolbar(scrolled: 0))
        #expect(!HeaderScroll.isUnderToolbar(scrolled: 1))
        #expect(!HeaderScroll.isUnderToolbar(scrolled: -30))
        #expect(HeaderScroll.isUnderToolbar(scrolled: 2))
    }

    @Test func aWindowNamesTheItemWhoseHeaderHasScrolledAway() {
        let details = DetailsPresentation()
        #expect(!details.isHeaderAway(of: first))
        details.headerScrolled(away: true, for: first)
        #expect(details.isHeaderAway(of: first))
        #expect(!details.isHeaderAway(of: second))
        details.headerScrolled(away: false, for: first)
        #expect(!details.isHeaderAway(of: first))
    }

    @Test func aPageGoingAwayAfterTheNextHasArrivedLeavesTheNextAlone() {
        let details = DetailsPresentation()
        details.headerScrolled(away: true, for: first)
        details.headerScrolled(away: true, for: second)
        details.headerScrolled(away: false, for: first)
        #expect(details.isHeaderAway(of: second))
        #expect(!details.isHeaderAway(of: first))
    }

    @Test func aPageSaysItIsAwayMoreThanOnceWithoutChangingTheState() {
        let details = DetailsPresentation()
        details.headerScrolled(away: true, for: first)
        details.headerScrolled(away: true, for: first)
        #expect(details.itemWithHeaderAway == first)
        details.headerScrolled(away: false, for: second)
        #expect(details.itemWithHeaderAway == first)
    }
}
