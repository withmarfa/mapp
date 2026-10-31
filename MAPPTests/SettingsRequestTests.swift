import AppKit
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

    @Test func aMainWindowThatWasClosedIsNotUsed() {
        let request = SettingsRequest()
        let browser = Browser()
        let window = Self.window()
        request.register(browser, in: window)
        window.close()
        var opened = 0
        request.show(nil, in: nil) { opened += 1 }

        #expect(opened == 1)
        #expect(request.isPending)
        #expect(!browser.showsSettings)
    }

    @Test func aMainWindowThatIsOnlyHiddenIsStillUsed() {
        let request = SettingsRequest()
        let browser = Browser()
        // Never ordered in, it is not visible, as a window of a hidden app is not.
        let window = Self.window()
        defer { window.close() }
        request.register(browser, in: window)
        var opened = 0
        request.show(nil, in: nil) { opened += 1 }

        #expect(opened == 0)
        #expect(browser.showsSettings)
    }

    /// Borderless and far off screen, so bringing it forward shows the person nothing.
    private static func window() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 10, height: 10), styleMask: [.borderless],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
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
