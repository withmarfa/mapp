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
        let store = FolderStore(root: url, bin: Self.bin)
        let library = NoteLibrary(loadingFrom: store, defaults: defaults)
        self.library = library
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

    /// Where trashed notes wait, in the app's own storage, outside any notes folder.
    private static var bin: URL {
        URL.applicationSupportDirectory.appending(path: "Trash", directoryHint: .isDirectory)
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
        let library = NoteLibrary(loadingFrom: FolderStore(root: root, bin: bin), defaults: nil)
        self.library = library
        Task { await library.load() }
    }
    #endif
}
