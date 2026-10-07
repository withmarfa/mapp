import AppKit
import Testing
@testable import MAPP

struct InterfaceStyleTests {
    @Test func semanticFontsScaleWithoutChangingTheirTraits() {
        for style in [NSFont.TextStyle.body, .headline, .subheadline, .caption1, .title1] {
            let normal = InterfaceStyle.font(style, textSize: 13)
            let enlarged = InterfaceStyle.font(style, textSize: 18)
            #expect(abs(enlarged.pointSize / normal.pointSize - 18.0 / 13.0) < 0.01)
            #expect(enlarged.fontDescriptor.symbolicTraits == normal.fontDescriptor.symbolicTraits)
        }
    }

    @Test func invalidStoredSizesStayReadable() {
        #expect(InterfaceStyle.font(.body, textSize: -100).pointSize > 0)
        #expect(InterfaceStyle.font(.body, textSize: Int.max).pointSize == InterfaceStyle.font(.body, textSize: 24).pointSize)
    }
}
