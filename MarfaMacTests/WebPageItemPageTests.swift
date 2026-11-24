import AppKit
import ApplicationServices
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

@MainActor
@Suite(.serialized, .hangLimit)
struct WebPageItemPageTests {
    @MainActor @Observable final class Visit {
        var item: Item
        let details = DetailsPresentation()
        /// The page's Reader or Original choice is kept here, so no other test or run sees it.
        let defaults = UserDefaults(suiteName: "WebPageItemPageTests-\(UUID().uuidString)")!
        init(_ item: Item) { self.item = item }
    }

    struct Host: View {
        let visit: Visit
        var body: some View {
            FileItemPage(item: visit.item, drafts: visit.details, open: { _ in }).defaultAppStorage(visit.defaults)
        }
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

    /// `assistive` says whether the test reads the page's accessibility elements. SwiftUI builds them only once an
    /// assistive client is attached, which also slows the analysis of a large page, so a test that reads only what the
    /// page presents hosts it with no client.
    private func host(_ visit: Visit, in library: FakeItemLibrary, assistive: Bool = true) -> (NSWindow, NSView) {
        let app = AXUIElementCreateApplication(getpid())
        let enabled = NSNumber(value: assistive)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, enabled)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, enabled)
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
    /// A page opens in Original until the person chooses Reader. The test reads what the page presents and no
    /// accessibility element, so it is hosted with no assistive client, which can push the analysis past its limit and
    /// leave a page with no article to offer.
    @Test func aPageWithAnArticleOffersTheSwitchToReader() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let item = file("A.html")
        try Data(Self.article.utf8).write(to: folder.appending(path: "a.html"))
        let library = FakeItemLibrary(items: [item], now: .now)
        library.files[item.id] = folder.appending(path: "a.html")
        let visit = Visit(item)
        let (window, view) = host(visit, in: library, assistive: false)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }

        #expect(try await settled(view) { visit.details.pageLook?.mode == .original })
        visit.details.pageLook?.choose(.reader)
        #expect(try await settled(view) { visit.details.pageLook?.mode == .reader })
    }

    /// The title's frame. The page's own identifier replaces the title's, so it is found by what it says.
    private func titleFrame(_ item: Item, in view: NSView) -> NSRect? {
        elements(of: view).first { answer($0, "accessibilityValue") as? String == item.displayTitle || answer($0, "accessibilityLabel") as? String == item.displayTitle }
            .flatMap { ($0.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue }
    }

    /// The file is held back so the page is measured while it loads, and the test does not depend on how long a large
    /// page takes to analyze, which is long enough to pass the analysis limit when an assistive client is attached.
    @Test func theTitleStaysWhereItIsWhenTheArticleArrives() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let item = file("A.html")
        try Data(Self.article.utf8).write(to: folder.appending(path: "a.html"))
        let library = FakeItemLibrary(items: [item], now: .now)
        library.files[item.id] = folder.appending(path: "a.html")
        let gate = FetchGate()
        library.fetchGates[item.id] = gate
        defer { gate.open() }
        let visit = Visit(item)
        let (window, view) = host(visit, in: library)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }

        try #require(await settled(view) { titleFrame(item, in: view) != nil })
        let whileLoading = try #require(titleFrame(item, in: view))
        try #require(visit.details.pageLook == nil, "the article has not arrived yet")
        gate.open()
        try #require(await settled(view) { visit.details.pageLook != nil })
        #expect(titleFrame(item, in: view)?.origin.y == whileLoading.origin.y)
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
        #expect(visit.details.pageLook == nil)

        // Time for the first item's article to be analyzed, which nothing signals when it is dropped. Analyzing it alone takes under a second.
        try await Task.sleep(for: .seconds(4))
        #expect(visit.details.pageLook == nil, "the first item's article is on the second item's page")
    }
}
