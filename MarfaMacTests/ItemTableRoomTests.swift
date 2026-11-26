import Foundation
import Testing
@testable import MarfaMac

/// Which columns the table keeps when its width falls (`ItemTableRoom`).
struct ItemTableRoomTests {
    private static func column(_ id: String, _ width: CGFloat, isName: Bool = false) -> ItemTableRoom.Column {
        ItemTableRoom.Column(id: id, isName: isName, minimum: width, ideal: width, isKept: false)
    }

    @Test func aColumnThatIsHiddenTakesNoGapAndTheOnesBeforeItStay() {
        let columns = [Self.column("name", 100, isName: true), Self.column("a", 200), Self.column("b", 200), Self.column("c", 80)]
        // Three columns and their gaps need 506; four need 588.
        let plan = ItemTableRoom.plan(columns, available: 507, gap: 2)
        #expect(plan.map(\.id) == ["name", "a", "b"], "c is hidden whole, and its gap is not kept back from b")
        #expect(plan.map(\.width) == [100, 200, 200], "no column that stays is cut")
        #expect(ItemTableRoom.plan(columns, available: 588, gap: 2).map(\.id) == ["name", "a", "b", "c"])
        #expect(ItemTableRoom.plan(columns, available: 587, gap: 2).map(\.id) == ["name", "a", "b"])
    }
}
