import CoreGraphics
import Testing
@testable import MAPP

/// When the sidebar's foot draws its band: only while rows pass under it.
struct ToolbarBandTests {
    @Test func aFootWithNothingBehindItDrawsNothing() {
        // Content ends well above the bottom edge, or just above the foot.
        #expect(!ToolbarBand.isUnderFoot(hiddenBelow: -400, footHeight: 56))
        #expect(!ToolbarBand.isUnderFoot(hiddenBelow: -56, footHeight: 56))
    }

    @Test func aFootDrawsOnceContentReachesIt() {
        #expect(ToolbarBand.isUnderFoot(hiddenBelow: -40, footHeight: 56))
        #expect(ToolbarBand.isUnderFoot(hiddenBelow: 0, footHeight: 56))
        #expect(ToolbarBand.isUnderFoot(hiddenBelow: 300, footHeight: 56))
    }

    @Test func aFootNotYetMeasuredDrawsNothing() {
        #expect(!ToolbarBand.isUnderFoot(hiddenBelow: 300, footHeight: 0))
    }
}
