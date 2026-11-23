import Foundation
import Testing
@testable import MarfaMac

/// A Debug copy, a Release copy and Marfa's command line each keep their own files. The store is named for this
/// copy's bundle identifier, never `Marfa`, and every fixed temporary folder sits under that identifier too.
@Suite(.hangLimit) struct AppPathsTests {
    private var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "com.withmarfa.marfa" }

    @Test func theStoreIsNamedForThisCopyAndNotMarfasCommandLineFolder() {
        let store = MarfaStoreLocation.applicationSupport
        #expect(store.deletingLastPathComponent().standardizedFileURL == URL.applicationSupportDirectory.standardizedFileURL)
        #expect(store.lastPathComponent == bundleIdentifier)
        #expect(store.lastPathComponent != "Marfa")
    }

    @Test func keptCopiesSitUnderThisCopysTemporaryFolder() {
        let folder = MarfaSource.keptFiles
        #expect(folder.lastPathComponent == "Marfa Files")
        #expect(folder.deletingLastPathComponent().lastPathComponent == bundleIdentifier)
        #expect(folder.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == URL.temporaryDirectory.standardizedFileURL)
    }

    @Test func quickLookCopiesSitUnderThisCopysTemporaryFolder() {
        let folder = QuickLookFile.processFolder("Quick Look")
        #expect(folder.lastPathComponent == String(ProcessInfo.processInfo.processIdentifier))
        let named = folder.deletingLastPathComponent()
        #expect(named.lastPathComponent == "Quick Look")
        #expect(named.deletingLastPathComponent().lastPathComponent == bundleIdentifier)
        #expect(named.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == URL.temporaryDirectory.standardizedFileURL)
    }

    /// Another copy's folders live beside this one's, under its own identifier. Clearing this copy's leftovers
    /// leaves them, including a folder at the old shared name.
    @Test func removingLeftoversLeavesAnotherCopysFolders() throws {
        let manager = FileManager.default
        let otherRoot = URL.temporaryDirectory.appending(path: "com.withmarfa.other", directoryHint: .isDirectory)
        let other = otherRoot.appending(path: "Quick Look", directoryHint: .isDirectory).appending(path: "424242", directoryHint: .isDirectory)
        let shared = URL.temporaryDirectory.appending(path: "Quick Look", directoryHint: .isDirectory).appending(path: "424242", directoryHint: .isDirectory)
        try manager.createDirectory(at: other, withIntermediateDirectories: true)
        try manager.createDirectory(at: shared, withIntermediateDirectories: true)
        try Data("other".utf8).write(to: other.appending(path: "file.txt"))
        try Data("shared".utf8).write(to: shared.appending(path: "file.txt"))
        defer {
            try? manager.removeItem(at: otherRoot)
            try? manager.removeItem(at: shared.deletingLastPathComponent())
        }

        // The current process still holds copies other tests are reading. A dead process's folders would go.
        QuickLookFile.removeLeftovers(isRunning: { $0 == ProcessInfo.processInfo.processIdentifier })

        #expect(manager.fileExists(atPath: other.appending(path: "file.txt").path))
        #expect(manager.fileExists(atPath: shared.appending(path: "file.txt").path))
    }

    @Test func remotePicturesStayInThisCopysCache() {
        let folder = PictureCache.standardFolder
        #expect(folder.lastPathComponent == "Remote Pictures")
        #expect(folder.deletingLastPathComponent().lastPathComponent == bundleIdentifier)
        #expect(folder.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == URL.cachesDirectory.standardizedFileURL)
    }

#if DEBUG
    @Test func theGallerySampleAndThePreviewStoreSitUnderThisCopysTemporaryFolder() {
        let gallery = SampleGallery.directory
        #expect(gallery.lastPathComponent == "marfa-mac-gallery-sample")
        #expect(gallery.deletingLastPathComponent().lastPathComponent == bundleIdentifier)

        let sample = Libraries.sampleStore
        #expect(sample.lastPathComponent == "Sample Marfa")
        #expect(sample.deletingLastPathComponent().lastPathComponent == bundleIdentifier)
        #expect(Libraries.sampleDefaultsSuite.contains(bundleIdentifier))
    }

    @Test @MainActor func aPreviewLibraryKeepsItsStoreUnderThisCopy() {
        let root = ItemPreviewFixtures.libraries().host.location.root
        #expect(root.lastPathComponent == "MarfaMac.ItemPreview")
        #expect(root.deletingLastPathComponent().lastPathComponent == bundleIdentifier)
    }
#endif

    /// Two identifiers never land on one folder, and neither is Marfa's command-line folder.
    @Test func twoCopiesNeverShareAFolderWithEachOtherOrTheCommandLine() {
        let release = "com.withmarfa.marfa"
        let debug = "com.withmarfa.marfa.debug"
        #expect(AppPaths.applicationSupport(for: release).lastPathComponent == release)
        #expect(AppPaths.applicationSupport(for: debug).lastPathComponent == debug)
        #expect(AppPaths.applicationSupport(for: release) != AppPaths.applicationSupport(for: debug))
        #expect(AppPaths.applicationSupport(for: release).lastPathComponent != "Marfa")
        #expect(AppPaths.temporaryRoot(for: release) != AppPaths.temporaryRoot(for: debug))
        #expect(AppPaths.temporary("Marfa Files", for: release) != AppPaths.temporary("Marfa Files", for: debug))
    }
}
