import Foundation
import Observation
import OSLog

private let log = Logger(subsystem: "com.withmarfa.mapp", category: "store")

/// The folder of notes a person chose, remembered across launches, and the library read from it. The trash
/// lives in the app's own storage, apart from the folder.
@Observable
final class NotesFolder {
    private(set) var url: URL?
    private(set) var library: NoteLibrary?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var watcher: FolderWatcher?
    private static let bookmarkKey = "notesFolder"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        // The UI tests and screenshots open a fresh sample folder of the app's own, which needs no bookmark.
        if ProcessInfo.processInfo.arguments.contains("-MAPPSampleFolder") {
            openSample()
            return
        }
        #endif
        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
            open(url)
            if isStale { remember(url) }
        } catch {
            log.error("the notes folder could not be found: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Opens the folder a person chose and remembers it.
    func choose(_ url: URL) {
        open(url)
        remember(url)
    }

    private func open(_ url: URL) {
        library?.finish()
        self.url?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        self.url = url
        let store = FolderStore(root: url, bin: Self.bin(for: url))
        start(NoteLibrary(loadingFrom: store, defaults: defaults), watching: url)
    }

    /// Reads the folder, then keeps reading it whenever anything in it changes.
    private func start(_ library: NoteLibrary, watching url: URL) {
        self.library = library
        // Watching starts before the folder is read, so a change made while it is read is taken in after.
        watcher = FolderWatcher(url) { library.refresh() }
        Task { await library.load() }
    }

    private func remember(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Self.bookmarkKey)
        } catch {
            log.error("the notes folder could not be remembered: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Where a folder's trashed notes wait, in the app's own storage, outside any notes folder. Each folder has
    /// its own, so a note trashed from one never comes back into another.
    private static func bin(for url: URL) -> URL {
        URL.applicationSupportDirectory
            .appending(path: "Trash", directoryHint: .isDirectory)
            .appending(path: UUID(stableFrom: url.standardizedFileURL.path).uuidString, directoryHint: .isDirectory)
    }

    #if DEBUG
    private func openSample() {
        let root = URL.temporaryDirectory.appending(path: "Sample Notes", directoryHint: .isDirectory)
        let bin = URL.temporaryDirectory.appending(path: "Sample Trash", directoryHint: .isDirectory)
        do {
            try SampleLibrary.write(to: root, bin: bin)
        } catch {
            log.error("the sample folder could not be written: \(error.localizedDescription, privacy: .public)")
        }
        url = root
        start(NoteLibrary(loadingFrom: FolderStore(root: root, bin: bin), defaults: nil), watching: root)
    }
    #endif
}
