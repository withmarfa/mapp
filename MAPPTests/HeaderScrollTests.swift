import AppKit
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

    @Test func aPageThatIsNotShownHasNotScrolled() {
        let scroll = HeaderScroll()
        scroll.scrolled(to: 300, isShowingPage: true)
        #expect(scroll.offset == 300)
        #expect(scroll.isAway(headerHeight: 120))
        // A document on its way out can still report after an error has replaced it.
        scroll.scrolled(to: 300, isShowingPage: false)
        #expect(scroll.offset == 0)
        #expect(!scroll.isAway(headerHeight: 120))
    }

    @Test func aResetPutsTheHeaderBackAtTheStart() {
        let scroll = HeaderScroll()
        scroll.scrolled(to: 300, isShowingPage: true)
        scroll.reset()
        #expect(scroll.offset == 0)
        #expect(!HeaderScroll.isUnderToolbar(scrolled: scroll.offset))
    }

    @Test func aNoteWithNoTitleThatHasScrolledAwayStillBringsItsToolbarItem() {
        let library = FakeItemLibrary()
        let untitled = FakeItemLibrary.note("", modified: .now)
        library.items = [untitled]
        let details = DetailsPresentation()
        let tools = { ItemToolbarActions(library: library, browser: nil, items: [untitled], editor: nil, details: details) }
        #expect(tools().hasScrollingHeader)
        #expect(!tools().hasHeaderAway)
        details.headerScrolled(away: true, for: untitled.id)
        #expect(tools().hasHeaderAway)
        #expect(tools().scrolledTitle.isEmpty)
    }

    @Test func aNotesToolbarTitleIsItsTextOnceItsHeaderHasScrolledAway() {
        let library = FakeItemLibrary()
        let note = FakeItemLibrary.note("Cliff path", modified: .now)
        library.items = [note]
        let details = DetailsPresentation()
        let tools = { ItemToolbarActions(library: library, browser: nil, items: [note], editor: nil, details: details) }
        #expect(tools().scrolledTitle.isEmpty)
        details.headerScrolled(away: true, for: note.id)
        #expect(tools().scrolledTitle == "Cliff path")
        details.headerScrolled(away: true, for: ItemID("other"))
        #expect(tools().scrolledTitle.isEmpty)
    }
}

/// The header takes the wheel over the top of a web page, which the page then gets through the window's monitor.
final class WheelGestureTests {
    private var gesture = WheelGesture()

    private func forwards(_ phase: NSEvent.Phase, _ momentum: NSEvent.Phase = [], overHeader: Bool) -> Bool {
        gesture.forwards(phase: phase, momentumPhase: momentum, overHeader: overHeader)
    }

    @Test func aMouseWheelGoesWhereThePointerIs() {
        #expect(forwards([], overHeader: true))
        #expect(!forwards([], overHeader: false))
        #expect(forwards([], overHeader: true))
    }

    @Test func aTrackpadGestureThatBeganOverTheHeaderStaysWithThePageToItsEndAndItsMomentum() {
        #expect(forwards(.mayBegin, overHeader: true))
        #expect(forwards(.began, overHeader: true))
        // The page scrolls under the pointer, so the pointer is soon over the page.
        #expect(forwards(.changed, overHeader: false))
        #expect(forwards(.ended, overHeader: false))
        #expect(forwards([], .began, overHeader: false))
        #expect(forwards([], .changed, overHeader: false))
        #expect(forwards([], .ended, overHeader: false))
        // The gesture is over, and the next one began over the page.
        #expect(!forwards(.began, overHeader: false))
    }

    @Test func aGestureThatBeganOverThePageIsLeftToTheWindowUntilItMovesOverTheHeader() {
        #expect(!forwards(.began, overHeader: false))
        #expect(!forwards(.changed, overHeader: false))
        #expect(forwards(.changed, overHeader: true))
        #expect(!forwards(.changed, overHeader: false))
        #expect(!forwards([], .changed, overHeader: false))
    }

    @Test func aNewGestureDuringMomentumDecidesForItself() {
        #expect(forwards(.began, overHeader: true))
        #expect(forwards([], .changed, overHeader: false))
        #expect(!forwards(.began, overHeader: false))
        #expect(!forwards(.changed, overHeader: false))
    }

    @Test func aCancelledMomentumEndsTheGesture() {
        #expect(forwards(.began, overHeader: true))
        #expect(forwards([], .cancelled, overHeader: false))
        #expect(!forwards([], .changed, overHeader: false))
    }
}
