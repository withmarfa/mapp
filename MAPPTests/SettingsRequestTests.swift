import Foundation
import Testing
@testable import MAPP

/// Settings asked for from a window that has no browser, as an item's window has none, goes to a main window that is
/// already open, and opens one only when none is.
@MainActor
struct SettingsRequestTests {
    @Test func withOnlyAnItemWindowOpenAMainWindowIsOpenedForIt() {
        let request = SettingsRequest()
        var opened = 0
        request.show(.library, in: nil) { opened += 1 }

        #expect(opened == 1)
        #expect(request.isPending)
        #expect(request.page == .library)
    }

    @Test func anOpenMainWindowShowsSettingsInsteadOfAnotherOne() {
        let request = SettingsRequest()
        let browser = Browser()
        request.register(browser, in: nil)
        var opened = 0
        request.show(nil, in: nil) { opened += 1 }
        request.show(nil, in: nil) { opened += 1 }

        #expect(opened == 0)
        #expect(!request.isPending)
        #expect(browser.showsSettings)
    }

    @Test func aMainWindowThatIsGoneIsNotUsed() {
        let request = SettingsRequest()
        var browser: Browser? = Browser()
        request.register(browser!, in: nil)
        browser = nil
        var opened = 0
        request.show(nil, in: nil) { opened += 1 }

        #expect(opened == 1)
    }

    @Test func aWindowWithABrowserShowsSettingsInItself() {
        let request = SettingsRequest()
        let other = Browser()
        request.register(other, in: nil)
        let own = Browser()
        request.show(nil, in: own) { Issue.record("no window should open") }

        #expect(own.showsSettings)
        #expect(!other.showsSettings)
    }
}
