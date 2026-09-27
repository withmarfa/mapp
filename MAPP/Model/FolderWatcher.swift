import CoreServices
import Foundation

/// Tells when another app, an agent or the Finder changes a note or folder in the notes folder. MAPP's own
/// changes, and changes to what is not MAPP's (hidden files such as Marfa's `.marfa`, and the attachments
/// folder), are not told. It says only that something changed; the library reads the folder to find out what.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let root: String
    private let changed: () -> Void
    private let rootChanged: () -> Void

    /// `rootChanged` is told when the notes folder itself is moved, renamed or deleted.
    init(_ url: URL, changed: @escaping () -> Void, rootChanged: @escaping () -> Void = {}) {
        root = url.standardizedFileURL.resolvingSymlinksInPath().path
        self.changed = changed
        self.rootChanged = rootChanged
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let paths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            let rootMoved = (0..<count).contains { flags[$0] & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 }
            MainActor.assumeIsolated {
                let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
                if rootMoved { return watcher.rootChanged() }
                if paths.isEmpty || paths.contains(where: watcher.matters) { watcher.changed() }
            }
        }
        // Changes a moment apart arrive together, and a moved or deleted folder is reported as well.
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagIgnoreSelf | kFSEventStreamCreateFlagUseCFTypes
        )
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2, flags
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    /// Whether a change at the path can change what MAPP shows: anything but a hidden file or folder and the
    /// attachments folder. The root itself matters, since it may have moved or gone.
    private func matters(_ path: String) -> Bool {
        let resolved = URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath().path
        guard resolved.hasPrefix(root) else { return true }
        let components = resolved.dropFirst(root.count).split(separator: "/")
        if components.first == Substring(FolderStore.attachments) { return false }
        return !components.contains { $0.hasPrefix(".") }
    }

    isolated deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
