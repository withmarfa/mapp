import AppKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import MAPP

@MainActor
@Suite(.serialized, .hangLimit)
struct ItemFileViewTests {
    /// A file item whose bytes are held under a hash with no extension, as a Marfa copy holds them.
    private func fixture() throws -> (library: FakeItemLibrary, id: ItemID, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ItemFileViewTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let blob = folder.appending(path: String(repeating: "ab", count: 32))
        try Data("Milk\nEggs\n".utf8).write(to: blob)
        let now = Date.now
        let item = Item(
            id: .mint(), type: TypeID("core.file"), title: "Shopping list.txt", titleRule: .property("title"),
            content: .file(.plainText, byteCount: 10), version: ItemVersion(1), created: now, modified: now)
        let library = FakeItemLibrary(items: [item], now: now)
        library.files[item.id] = blob
        return (library, item.id, folder)
    }

    private static func spin() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }

    private func show(_ id: ItemID, in library: FakeItemLibrary) -> NSWindow {
        autoreleasepool {
            let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: NoteWindow(id: .constant(id)).environment(\.library, library))
            window.makeKeyAndOrderFront(nil)
            return window
        }
    }

    /// The file arriving changed what the view shows, and the view then fetched the file again, each time it
    /// arrived, for as long as the window stayed open: the task that fetches it was attached to the branch it
    /// replaced.
    @Test func showingAFileFetchesItOnce() async throws {
        let (library, id, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let window = show(id, in: library)
        defer { autoreleasepool { window.contentView = nil; window.close() } }

        try #require(await eventually { library.fetches > 0 })
        // The view shows the file as soon as the fetch answers; these passes lay it out and draw it, which is when
        // a task attached to the replaced branch would fetch again.
        for _ in 0..<50 {
            Self.spin()
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.displayIfNeeded()
        }
        #expect(library.fetches == 1, "the file was fetched \(library.fetches) times")
    }

    @Test func aFailedFetchIsAskedForOnceUntilTheyTryAgain() async throws {
        let (library, id, folder) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        library.fetchFails = true
        let window = show(id, in: library)
        defer { autoreleasepool { window.contentView = nil; window.close() } }

        try #require(await eventually { library.fetches > 0 })
        // Time for a fetch the failure would set off again, which nothing signals when none is made.
        try await Task.sleep(for: .seconds(1))
        #expect(library.fetches == 1, "the file was fetched \(library.fetches) times")
    }
}
