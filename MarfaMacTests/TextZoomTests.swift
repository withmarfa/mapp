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
}
