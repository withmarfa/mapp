import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MAPP

@MainActor
@Suite(.serialized, .hangLimit)
struct CommandPaletteTests {
    /// What an accessibility element answers to `selector`, whatever class SwiftUI made it.
    private static func answer(_ element: NSObject, _ selector: String) -> Any? {
        let selector = NSSelectorFromString(selector)
        return element.responds(to: selector) ? element.perform(selector)?.takeUnretainedValue() : nil
    }

    /// Every label the palette's rows give the accessibility tree.
    private func labels(of view: NSView) -> [String] {
        var found: [String] = []
        func walk(_ element: Any?, _ depth: Int = 0) {
            guard depth < 12, let element = element as? NSObject else { return }
            if let label = Self.answer(element, "accessibilityLabel") as? String, !label.isEmpty { found.append(label) }
            for child in Self.answer(element, "accessibilityChildren") as? [Any] ?? [] { walk(child, depth + 1) }
        }
        walk(view)
        return found
    }

    @Test func theCommandsFollowTheEditorBecomingReadyWhileTheQueryStaysTheSame() async throws {
        let page = try await EditorTests.Page()
        let note = page.library.add("Body")
        let browser = Browser()
        browser.show(.allNotes, in: page.library, order: NoteOrder())
        browser.selection = [note.id]
        browser.palette = .commands

        // SwiftUI builds its accessibility elements only once an assistive client is attached.
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 700, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: CommandPalette(browser: browser, editor: page.editor, mode: .commands).environment(\.library, page.library))
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }

        #expect(try await eventuallyAsking {
            host.layoutSubtreeIfNeeded()
            return labels(of: host).contains { $0.contains("Settings") }
        }, "the palette lists its commands: \(labels(of: host))")
        #expect(!labels(of: host).contains { $0.hasPrefix("Bold") }, "no note is on the page yet")

        try await page.show(note.id)
        #expect(try await eventuallyAsking {
            host.layoutSubtreeIfNeeded()
            return labels(of: host).contains { $0.hasPrefix("Bold") }
        }, "the formatting commands arrive once the page holds the note")
    }
}
