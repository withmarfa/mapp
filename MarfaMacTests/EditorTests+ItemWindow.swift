import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
import WebKit
@testable import MarfaMac

/// An item's window changes its item, head and history only once the text on its page is handed over, so typing never
/// lands in an item other than the one the window shows.
extension EditorTests {
    private final class WindowItem {
        var id: ItemID?
        var binding: Binding<ItemID?> { Binding { self.id } set: { self.id = $0 } }
    }

    /// An item window's editor showing `item`, saving its edits to `library`.
    private static func window(
        showing item: Item, in library: FakeItemLibrary, history: ItemWindowHistory
    ) async throws -> (EditorController, WindowItem) {
        let shown = WindowItem()
        shown.id = item.id
        let editor = ItemWindow.makeEditor(library: library, details: DetailsPresentation(), showing: shown.binding, history: history)
        try #require(await eventually { editor.isReady })
        editor.load(item)
        try #require(await eventually { editor.pageItemID == item.id })
        _ = try await editor.webView.evaluateJavaScript("1")
        return (editor, shown)
    }

    /// The page holds `typed` for its item until `window.held` is false, refusing as a composition does meanwhile;
    /// with `window.broken` it fails as a page in trouble does.
    private static func holding(_ typed: String, in editor: EditorController) async throws {
        let leaving = editor.generation
        _ = try await editor.webView.evaluateJavaScript("""
            window.held = true
            window.broken = false
            const flush = window.editor.flush.bind(window.editor)
            window.editor.flush = generation => {
                if (window.broken) throw new Error('broken')
                if (window.held) return { commandError: 'composition', message: 'Text composition is in progress' }
                return generation === \(leaving) ? \(String(reflecting: typed)) : flush(generation)
            }
            0
            """)
    }

    @Test @MainActor func aLinkFollowedInAnItemWindowWhileComposingMovesTheWindowOnlyOnceTheTypingIsIn() async throws {
        let library = FakeItemLibrary()
        let plan = library.add("Plan\n")
        let reader = library.add("Reader\n")
        let history = ItemWindowHistory()
        let (editor, shown) = try await Self.window(showing: reader, in: library, history: history)
        defer { editor.windowWent() }
        try await Self.holding("Reader, typed\n", in: editor)

        editor.onOpenItem(plan.id)
        // Several of the page's refusals, so the window would have moved by now if it did not wait.
        try await Task.sleep(for: .milliseconds(300))
        #expect(shown.id == reader.id && history.back.isEmpty, "the window, its head and its history stay while the page composes")
        #expect(editor.pageItemID == reader.id)

        _ = try await editor.webView.evaluateJavaScript("window.held = false; 0")
        try #require(await eventually { shown.id == plan.id })
        #expect(editor.pageItemID == plan.id, "the page held the linked item before the window showed it")
        #expect(library.body(of: reader.id)?.text == "Reader, typed\n", "the typing went to the item it was typed in")
        #expect(library.body(of: plan.id)?.text == "Plan\n")
        #expect(history.back == [reader.id])
    }

    @Test @MainActor func aHandOverThatFailsInAnItemWindowLeavesItOnItsItemAndTellsThePerson() async throws {
        let library = FakeItemLibrary()
        let plan = library.add("Plan\n")
        let reader = library.add("Reader\n")
        let history = ItemWindowHistory()
        let (editor, shown) = try await Self.window(showing: reader, in: library, history: history)
        defer { editor.windowWent() }
        try await Self.holding("Reader, typed\n", in: editor)
        _ = try await editor.webView.evaluateJavaScript("window.broken = true; 0")

        editor.onOpenItem(plan.id)
        try #require(await eventually { library.notices.told == 1 })
        // Time for a move the failure should not have made.
        try await Task.sleep(for: .milliseconds(100))
        #expect(shown.id == reader.id && history.back.isEmpty, "the window stays on the item whose typing was not saved")
        #expect(editor.pageItemID == reader.id)
        #expect(editor.isShowing(reader.id), "the head's events and outside changes still reach the item on the page")
    }

    @Test @MainActor func twoLinksFollowedWhileComposingThatBothFailLeaveTheWindowOnTheItemItsPageHolds() async throws {
        let library = FakeItemLibrary()
        let plan = library.add("Plan\n")
        let notes = library.add("Notes\n")
        let reader = library.add("Reader\n")
        let history = ItemWindowHistory()
        let (editor, shown) = try await Self.window(showing: reader, in: library, history: history)
        defer { editor.windowWent() }
        editor.flushLimit = .milliseconds(300)
        try await Self.holding("Reader, typed\n", in: editor)

        // The second link is followed while the first one's hand-over waits; the page never hands over.
        editor.onOpenItem(plan.id)
        editor.onOpenItem(notes.id)
        try #require(await eventually { library.notices.told == 1 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(shown.id == reader.id && history.back.isEmpty)
        #expect(editor.heldItemID == reader.id && editor.pageItemID == reader.id)
        #expect(editor.isShowing(reader.id), "the request is the item on the page, never the one asked for in between")

        // A change made elsewhere to the item the window shows still reaches its page.
        library.updateBody(of: reader.id, to: "Reader, elsewhere\n", readAt: reader.version)
        editor.itemChanged(try #require(library.item(reader.id)))
        #expect(editor.markdown == "Reader, elsewhere\n")
    }

    @Test @MainActor func backInAnItemWindowWaitsForTheHandOverAndAFileIsShownOnlyOnceTheTextIsIn() async throws {
        let library = FakeItemLibrary()
        let reader = library.add("Reader\n")
        let file = ItemID.mint()
        library.items.append(Item(
            id: file, type: TypeID("core.file"), title: "Plan.pdf", titleRule: .property("title"), content: .file(.pdf, byteCount: 1),
            version: ItemVersion(1), created: .now, modified: .now))
        let history = ItemWindowHistory()
        history.followed(from: file, to: reader.id)
        let (editor, shown) = try await Self.window(showing: reader, in: library, history: history)
        defer { editor.windowWent() }
        try await Self.holding("Reader, typed\n", in: editor)

        let target = try #require(history.target(.back, isAvailable: { library.item($0) != nil }))
        ItemWindow.go(to: target, in: library, editor: editor, showing: shown.binding) {
            history.went(.back, from: reader.id, to: target)
        }
        // Several of the page's refusals, as above.
        try await Task.sleep(for: .milliseconds(300))
        #expect(shown.id == reader.id && history.forward.isEmpty, "Back waits for the text on the page")

        _ = try await editor.webView.evaluateJavaScript("window.held = false; 0")
        try #require(await eventually { shown.id == file })
        #expect(library.body(of: reader.id)?.text == "Reader, typed\n", "the text was handed over before the file's page")
        #expect(history.back.isEmpty && history.forward == [reader.id])
    }
}
