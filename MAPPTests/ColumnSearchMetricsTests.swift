import Foundation
import Testing
@testable import MAPP

struct ColumnSearchMetricsTests {
    @Test func theFieldFillsTheColumnButForTheMarginsAndTheOptions() {
        #expect(ColumnSearchMetrics.fieldWidth(inColumn: ColumnWidth.list.defaultWidth) == 241)
        #expect(ColumnSearchMetrics.fieldWidth(inColumn: 480) == 391)
    }

    @Test func theNarrowestColumnStillHasAUsableField() {
        #expect(ColumnSearchMetrics.fieldWidth(inColumn: 280) == 191)
        #expect(ColumnSearchMetrics.fieldWidth(inColumn: 100) == 120)
    }

    @Test func theFieldAlwaysEndsBeforeTheOptions() {
        for width in stride(from: CGFloat(280), through: 480, by: 10) {
            #expect(ColumnSearchMetrics.fieldWidth(inColumn: width) <= width - ColumnSearchMetrics.columnChrome)
        }
    }

    @Test func anItemFieldTakesAShareOfItsRoom() {
        #expect(ColumnSearchMetrics.itemFieldWidth == (260 * ColumnSearchMetrics.share).rounded())
    }
}
