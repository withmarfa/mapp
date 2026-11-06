import Foundation
import Testing
@testable import MAPP

/// What a pinned address or number opens on a saved web page, as it does on a note page.
struct PagePinLinksTests {
    @Test func onlyAWebAddressOpensInTheBrowser() {
        #expect(PagePinsView.webAddress("https://example.com/a")?.absoluteString == "https://example.com/a")
        #expect(PagePinsView.webAddress("HTTP://example.com")?.host() == "example.com")
        #expect(PagePinsView.webAddress("javascript:alert(1)") == nil)
        #expect(PagePinsView.webAddress("example.com") == nil)
    }

    @Test func aNumberIsDialedAsItsDigitsAndALeadingPlus() {
        #expect(PagePinsView.dialAddress("+44 (0)20 7946 0958")?.absoluteString == "tel:+4402079460958")
        #expect(PagePinsView.dialAddress("020-7946-0958")?.absoluteString == "tel:02079460958")
        #expect(PagePinsView.dialAddress("ext. +1")?.absoluteString == "tel:1", "a plus that does not lead is dropped")
        #expect(PagePinsView.dialAddress("call me") == nil)
    }
}
