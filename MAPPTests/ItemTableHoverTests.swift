import Foundation
import Testing
@testable import MAPP

struct ItemTableHoverTests {
    private let a = ItemID("a")
    private let b = ItemID("b")

    @Test func aRowStaysHoveredWhileTheMouseMovesBetweenItsCells() async {
        let hover = ItemTableHover(grace: .milliseconds(20))
        hover.enter(a)
        hover.enter(a)
        hover.exit(a)
        #expect(hover.row == a)
        // Gives the release time it would take, to show it does not clear a row a cell still holds.
        try? await Task.sleep(for: .milliseconds(80))
        #expect(hover.row == a)
    }

    @Test func aRowIsReleasedOnceTheMouseHasLeftAllItsCells() async {
        let hover = ItemTableHover(grace: .milliseconds(20))
        hover.enter(a)
        hover.exit(a)
        #expect(await eventually { hover.row == nil })
    }

    @Test func movingToTheNextRowIsNotUndoneByTheLastRowsRelease() async {
        let hover = ItemTableHover(grace: .milliseconds(20))
        hover.enter(a)
        hover.exit(a)
        hover.enter(b)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(hover.row == b)
    }
}
