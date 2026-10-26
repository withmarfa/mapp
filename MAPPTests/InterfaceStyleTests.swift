import AppKit
import Testing
@testable import MAPP

struct InterfaceStyleTests {
    @Test func invalidStoredSizesStayReadable() {
        #expect(InterfaceStyle.font(.body, textSize: -100).pointSize > 0)
        #expect(InterfaceStyle.font(.body, textSize: Int.max).pointSize == InterfaceStyle.font(.body, textSize: 24).pointSize)
    }
}
