import AppKit
import Foundation
import SwiftUI
import Testing
import WebKit
@testable import MAPP

/// A window makes one editor, and lets go of it when it closes.
extension EditorTests {
    static func editorWebView(in view: NSView?) -> EditorWebView? {
        guard let view else { return nil }
        if let web = view as? EditorWebView { return web }
        for sub in view.subviews { if let web = editorWebView(in: sub) { return web } }
        return nil
    }

    /// What a window held, by weak references, so a test can see what outlives it.
    struct Released {
        weak var editor: EditorController?
        weak var webView: EditorWebView?
        weak var library: MarfaLibrary?
        var isEmpty: Bool { editor == nil && webView == nil && library == nil }
    }

    /// Opens the item in a window of its own, as the app's item window shows it, sets its title as `edit` says,
    /// and closes the window the way ⌘W does.
    static func openAndClose(_ library: MarfaLibrary, item: ItemID, edit: (EditorController, EditorWebView) async throws -> Void = { _, _ in }) async throws -> Released {
        try #require(await eventually { library.isLoaded })
        // The app's run loop empties its autorelease pool after every event; a test's await does not, so the
        // window's own steps are made in pools of their own.
        let window = autoreleasepool {
            let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: NoteWindow(id: .constant(item)).environment(\.library, library))
            window.makeKeyAndOrderFront(nil)
            return window
        }
        try #require(await eventually { editorWebView(in: window.contentView)?.controller?.isReady == true })
        let web = try #require(editorWebView(in: window.contentView))
        let editor = try #require(web.controller)
        try #require(try await eventuallyAsking { try await web.evaluateJavaScript("document.getElementById('ItemPageTitle')?.textContent") as? String == library.item(item)?.title })
        try await edit(editor, web)
        autoreleasepool { window.performClose(nil) }
        #expect(await eventually { !window.isVisible }, "the window closes")
        // What SwiftUI does with a window it closes.
        autoreleasepool {
            window.toolbar = nil
            window.contentView = nil
        }
        return Released(editor: editor, webView: web, library: library)
    }

    /// An item's page in a window of its own, with an editor and drafts of its own, through to its window closing.
    static func openAndCloseAPage(_ library: MarfaLibrary, item: ItemID) async throws -> Released {
        try #require(await eventually { library.isLoaded })
        let editor = EditorController(library: library)
        let drafts = DetailsPresentation()
        editor.titleDrafts = drafts
        let window = autoreleasepool {
            let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PageHost(library: library, editor: editor, drafts: drafts, shown: Shown(item))
                .environment(\.library, library))
            window.makeKeyAndOrderFront(nil)
            return window
        }
        try #require(try await eventuallyAsking { try await editor.webView.evaluateJavaScript("document.getElementById('ItemPageTitle')?.textContent") as? String == library.item(item)?.title })
        // Typing in the title goes through the window's handler, as a person's does.
        editor.onHeaderEvent(.titleInput(item, "Review the findings"))
        drafts.draft(for: item, key: "title").isDirty = false
        autoreleasepool { window.performClose(nil) }
        #expect(await eventually { !window.isVisible }, "the window closes")
        autoreleasepool { window.contentView = nil }
        return Released(editor: editor, webView: editor.webView, library: library)
    }

    @Test func aClosedWindowLetsGoOfItsEditorPageAndLibrary() async throws {
        let released = try await Self.openAndCloseAPage(ItemPreviewFixtures.library, item: ItemPreviewFixtures.ticketID)
        _ = await eventually { released.isEmpty }
        #expect(released.editor == nil, "a closed window's editor is released")
        #expect(released.webView == nil, "a closed window's web view is released")
        #expect(released.library == nil, "a library no window shows is released")
    }

    @Observable final class Ticks {
        var count = 0
    }

    /// Makes its content again whenever `ticks` changes, as a window's parent does each time its body runs.
    struct Remaking<Content: View>: View {
        let ticks: Ticks
        @ViewBuilder let content: () -> Content

        var body: some View {
            let _ = ticks.count
            content()
        }
    }

    /// Hosts `content` in a window, has its parent make it again `times` times, and returns every editor made
    /// meanwhile, held so none can go unseen, the one the window shows, and the drafts it held while shown.
    static func editorsMade<Content: View>(remaking times: Int, _ content: @escaping () -> Content) async throws -> (made: [EditorController], shown: EditorController, drafts: DetailsPresentation?) {
        let before = EditorController.open.allObjects
        var made: [EditorController] = []
        func gather() {
            for editor in EditorController.open.allObjects where !before.contains(where: { $0 === editor }) && !made.contains(where: { $0 === editor }) {
                made.append(editor)
            }
        }
        let ticks = Ticks()
        let window = autoreleasepool {
            let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 1100, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: Remaking(ticks: ticks, content: content))
            window.makeKeyAndOrderFront(nil)
            return window
        }
        try #require(await eventually { editorWebView(in: window.contentView)?.controller?.isReady == true })
        gather()
        for _ in 0..<times {
            ticks.count += 1
            // Lets each change reach the page before the next, as a person's edits arrive spaced apart.
            try await Task.sleep(for: .milliseconds(100))
            gather()
        }
        let shown = try #require(editorWebView(in: window.contentView)?.controller)
        let drafts = shown.titleDrafts
        autoreleasepool { window.performClose(nil) }
        try #require(await eventually { !window.isVisible })
        autoreleasepool {
            window.toolbar = nil
            window.contentView = nil
        }
        return (made, shown, drafts)
    }

    /// An editor is a web view with a page process of its own, so a window makes one, however often SwiftUI makes
    /// the window's view again.
    @Test func aMainWindowMakesOneEditorHoweverOftenItsViewIsMadeAgain() async throws {
        let library = ItemPreviewFixtures.library
        let browser = ItemPreviewFixtures.browser
        let details = DetailsPresentation()
        let libraries = ItemPreviewFixtures.libraries(named: "MAPP.EditorTests")
        let (made, shown, drafts) = try await Self.editorsMade(remaking: 5) {
            MainView(browser: browser, details: details, restoresWindow: false)
                .environment(\.library, library)
                .environment(libraries)
        }
        #expect(made.count == 1, "one editor for the window, not one for each time its view is made")
        #expect(made.first === shown)
        #expect(drafts === details, "the editor holds the window's drafts")
        #expect(shown.titleDrafts == nil, "the window's drafts leave with it")
        withExtendedLifetime(library) {}
    }

    @Test func anItemWindowMakesOneEditorHoweverOftenItsViewIsMadeAgain() async throws {
        let library = ItemPreviewFixtures.library
        let (made, shown, drafts) = try await Self.editorsMade(remaking: 5) {
            NoteWindow(id: .constant(ItemPreviewFixtures.ticketID))
                .environment(\.library, library)
        }
        #expect(made.count == 1, "one editor for the window, not one for each time its view is made")
        #expect(made.first === shown)
        #expect(drafts != nil, "the editor holds the window's drafts")
        #expect(shown.titleDrafts == nil, "the window's drafts leave with it")
        withExtendedLifetime(library) {}
    }
}
