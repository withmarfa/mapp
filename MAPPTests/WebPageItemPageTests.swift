import AppKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import MAPP

@MainActor
@Suite(.serialized, .hangLimit)
struct WebPageItemPageTests {
    @MainActor @Observable final class Visit {
        var item: Item
        init(_ item: Item) { self.item = item }
    }

    struct Host: View {
        let visit: Visit
        var body: some View { FileItemPage(item: visit.item, drafts: DetailsPresentation(), open: { _ in }) }
    }

    private static let article = "<html><head><title>The cliff path</title></head><body><article><h1>The cliff path</h1>"
        + (1...12).map { "<p>Paragraph \($0) walks along the cliff, past the gorse and the old coastguard hut, and down to the cove where the boats lie.</p>" }.joined()
        + "</article></body></html>"
    private static let longParagraphs = 28_000
    private static let note = "<html><body><p>Hello.</p></body></html>"

    private func file(_ name: String) -> Item {
        let now = Date.now
        return Item(
            id: .mint(), type: TypeID("core.file"), title: name, titleRule: .property("title"),
            content: .file(.html, byteCount: 100), version: ItemVersion(1), created: now, modified: now)
    }

    private func answer(_ element: NSObject, _ selector: String) -> Any? {
        let selector = NSSelectorFromString(selector)
        return element.responds(to: selector) ? element.perform(selector)?.takeUnretainedValue() : nil
    }

    /// Every accessibility element under the view.
    private func elements(of view: NSView) -> [NSObject] {
        var found: [NSObject] = []
        func walk(_ element: Any?, _ depth: Int) {
            guard depth < 40, let element = element as? NSObject else { return }
            found.append(element)
            for child in answer(element, "accessibilityChildren") as? [Any] ?? [] { walk(child, depth + 1) }
        }
        walk(view, 0)
        return found
    }

    private func has(identifier: String, in view: NSView) -> Bool {
        elements(of: view).contains { answer($0, "accessibilityIdentifier") as? String == identifier }
    }

    private func button(labelled label: String, in view: NSView) -> NSObject? {
        elements(of: view).first { answer($0, "accessibilityRole") as? String == "AXButton" && answer($0, "accessibilityLabel") as? String == label }
    }

    private func host(_ visit: Visit, in library: FakeItemLibrary) -> (NSWindow, NSView) {
        // SwiftUI builds its accessibility elements only once an assistive client is attached.
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 700), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: Host(visit: visit).environment(\.library, library))
        window.contentView = view
        window.orderFrontRegardless()
        return (window, view)
    }

    private func settled(_ view: NSView, _ done: () -> Bool) async throws -> Bool {
        try await eventuallyAsking {
            view.layoutSubtreeIfNeeded()
            return done()
        }
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "WebPageItemPageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The check below can only show an article on the wrong page if an article does show on a page that has one.
    @Test func aPageWithAnArticleOffersTheSwitchToReader() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let item = file("A.html")
        try Data(Self.article.utf8).write(to: folder.appending(path: "a.html"))
        let library = FakeItemLibrary(items: [item], now: .now)
        library.files[item.id] = folder.appending(path: "a.html")
        let (window, view) = host(Visit(item), in: library)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }

        #expect(try await settled(view) { has(identifier: "SourceViewMode", in: view) })
    }

    /// Try Again ran on a task of its own, which the window moving on to another item did not cancel. Its file was
    /// still being analyzed when the other item's page appeared, and when it finished it put its article on that page.
    @Test func aRetryStartedForOneItemNeverShowsItsArticleOnTheNext() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // An article long enough that analyzing it takes a couple of seconds, the time to move on to the other item.
        let long = "<html><head><title>The cliff path</title></head><body><article><h1>The cliff path</h1>"
            + (1...Self.longParagraphs).map { "<p>Paragraph \($0) walks along the cliff, past the gorse and the old coastguard hut, and down to the cove where the boats lie.</p>" }.joined()
            + "</article></body></html>"
        try Data(long.utf8).write(to: folder.appending(path: "a.html"))
        try Data(Self.note.utf8).write(to: folder.appending(path: "b.html"))
        let (first, second) = (file("A.html"), file("B.html"))
        let library = FakeItemLibrary(items: [first, second], now: .now)
        library.files[first.id] = folder.appending(path: "a.html")
        library.files[second.id] = folder.appending(path: "b.html")
        library.fetchFails = true

        let visit = Visit(first)
        let (window, view) = host(visit, in: library)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }

        try #require(await settled(view) { button(labelled: "Try Again", in: view) != nil })
        library.fetchFails = false
        let retry = try #require(button(labelled: "Try Again", in: view))
        _ = retry.perform(NSSelectorFromString("accessibilityPerformPress"))
        try #require(await eventually { library.fetches == 2 })
        // The retry's fetch answers at once. Nothing signals when it has, and the other item's load would otherwise reach
        // the loader first, which drops the retry's answer there instead.
        try await Task.sleep(for: .milliseconds(300))

        visit.item = second
        try #require(await eventually { library.fetches == 3 })
        // The second item has no article, so its page is complete once nothing is loading.
        try #require(await settled(view) { !elements(of: view).contains { answer($0, "accessibilityRole") as? String == "AXProgressIndicator" } })
        #expect(!has(identifier: "SourceViewMode", in: view))

        // Time for the first item's article to be analyzed, which nothing signals when it is dropped.
        try await Task.sleep(for: .seconds(8))
        #expect(!has(identifier: "SourceViewMode", in: view), "the first item's article is on the second item's page")
    }
}
