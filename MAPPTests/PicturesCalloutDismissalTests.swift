import Testing
@testable import MAPP

struct PicturesCalloutDismissalTests {
    @Test func theCalloutShowsUntilItIsClosed() {
        let item = ItemID.mint()
        var dismissal = PicturesCalloutDismissal()
        #expect(!dismissal.isClosed(for: item))
        dismissal.close(for: item)
        #expect(dismissal.isClosed(for: item))
    }

    @Test func aDifferentItemNeverInheritsTheClosing() {
        let first = ItemID.mint()
        let second = ItemID.mint()
        var dismissal = PicturesCalloutDismissal()
        dismissal.close(for: first)
        #expect(!dismissal.isClosed(for: second))
    }

    @Test func openingThePageAgainBringsTheCalloutBack() {
        let item = ItemID.mint()
        var dismissal = PicturesCalloutDismissal()
        dismissal.close(for: item)
        dismissal.reopen()
        #expect(!dismissal.isClosed(for: item))
    }
}
