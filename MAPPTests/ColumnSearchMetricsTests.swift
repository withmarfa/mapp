import Foundation
import Testing
@testable import MAPP

struct ColumnSearchMetricsTests {
    @Test func theFieldTakesAShareOfTheRoomBesideTheOptions() {
        // 350 - 54 = 296 of room, and 85% of that.
        #expect(ColumnSearchMetrics.fieldWidth(inColumn: ColumnWidth.list.defaultWidth) == 252)
        #expect(ColumnSearchMetrics.fieldWidth(inColumn: 480) == 362)
    }

    @Test func theNarrowestColumnStillHasAUsableField() {
        #expect(ColumnSearchMetrics.fieldWidth(inColumn: 280) == 192)
        #expect(ColumnSearchMetrics.fieldWidth(inColumn: 100) == 120)
    }

    @Test func theFieldAlwaysEndsBeforeTheOptions() {
        for width in stride(from: CGFloat(280), through: 480, by: 10) {
            #expect(ColumnSearchMetrics.fieldWidth(inColumn: width) <= width - ColumnSearchMetrics.columnChrome)
        }
    }

    @Test func anItemFieldNarrowsByTheSameShare() {
        #expect(ColumnSearchMetrics.itemFieldWidth == (260 * ColumnSearchMetrics.share).rounded())
    }
}
