import Foundation
import Testing

@testable import MarfaMac

struct TextZoomTests {
    @Test func thePageHasItsOwnSettingAndEverythingElseTheInterfaces() {
        #expect(TextZoom.acting(pageFocused: true).key == PageKey.textSize)
        #expect(TextZoom.acting(pageFocused: false).key == InterfaceKey.textSize)
    }

    @Test func applyWritesOnlyTheSettingItActsOn() throws {
        let defaults = ThrowawayDefaults.make("TextZoomTests")
        TextZoom.page.apply(.bigger, in: defaults)
        #expect(defaults.integer(forKey: PageKey.textSize) == 16)
        #expect(defaults.object(forKey: InterfaceKey.textSize) == nil)
        defaults.set(24, forKey: InterfaceKey.textSize)
        TextZoom.interface.apply(.bigger, in: defaults)
        #expect(defaults.integer(forKey: InterfaceKey.textSize) == 24)
        TextZoom.interface.apply(.actual, in: defaults)
        #expect(defaults.integer(forKey: InterfaceKey.textSize) == 13)
    }

    @Test func theDefaultPageTextIs15AndASizeStoredBeforeTheStepsReadsAsTheNearest() {
        #expect(PageStyle().textSize == 15)
        #expect(PageStyle.textSizes == [13, 14, 15, 16, 18, 20, 24])
        #expect(PageStyle.nearestTextSize(11) == 13)
        #expect(PageStyle.nearestTextSize(12) == 13)
        #expect(PageStyle.nearestTextSize(17) == 16, "the smaller of two equally near")
        #expect(PageStyle.nearestTextSize(22) == 20)
        #expect(PageStyle.nearestTextSize(24) == 24)
        // A step is taken from what the page shows, and the stored size is left alone until the person takes one.
        let defaults = ThrowawayDefaults.make("TextZoomTests.stored")
        defaults.set(11, forKey: PageKey.textSize)
        #expect(TextZoom.page.size(after: .smaller, from: 11) == nil)
        #expect(TextZoom.page.size(after: .bigger, from: 11) == 14)
        #expect(defaults.integer(forKey: PageKey.textSize) == 11)
    }
}
