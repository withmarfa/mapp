import CoreServices
import Foundation

/// Tells when anything in the notes folder changes, whoever changed it: another app, an agent, the Finder or
/// MAPP itself. It says only that something changed; the library reads the folder again to find out what.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let changed: () -> Void

    init(_ url: URL, changed: @escaping () -> Void) {
        self.changed = changed
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            MainActor.assumeIsolated {
                Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().changed()
            }
        }
        // Changes a moment apart arrive together, and a moved or deleted folder is reported as well.
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2, flags
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    isolated deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
