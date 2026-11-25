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
        #expect(defaults.integer(forKey: PageKey.textSize) == 14)
        #expect(defaults.object(forKey: InterfaceKey.textSize) == nil)
        defaults.set(24, forKey: InterfaceKey.textSize)
        TextZoom.interface.apply(.bigger, in: defaults)
        #expect(defaults.integer(forKey: InterfaceKey.textSize) == 24)
        TextZoom.interface.apply(.actual, in: defaults)
        #expect(defaults.integer(forKey: InterfaceKey.textSize) == 13)
    }

    @Test func pageRolesAndReadingWidthScaleFromActualSize() {
        let actual = PageStyle()
        #expect(abs(actual.titleSize - 24.7) < 0.001)
        #expect(Typography.headingSize(2) == 17.5)
        #expect(Typography.headingSize(3) == 15)
        #expect(abs(actual.readingEms * Double(actual.textSize) - 680) < 0.001)
        #expect(abs(actual.horizontalInset(for: 900) - 110) < 0.001)
        let larger = PageStyle(textSize: 18)
        #expect(larger.titleSize > actual.titleSize)
        #expect(larger.horizontalInset(for: 1_000) < actual.horizontalInset(for: 1_000))
    }

    @Test func theDefaultPageTextIs13AndASizeStoredBeforeTheStepsReadsAsTheNearest() {
        #expect(PageStyle().textSize == 13)
        #expect(PageStyle.textSizes == [13, 14, 15, 16, 18, 20, 24])
        #expect(PageStyle.nearestTextSize(11) == 13)
        #expect(PageStyle.nearestTextSize(12) == 13)
        #expect(PageStyle.nearestTextSize(15) == 15)
        #expect(TextZoom.page.size(after: .actual, from: 15) == 13)
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
