import Foundation
@testable import MAPP

extension Note {
    /// A note as the tests write one: its body, pinned in its front matter when asked, at a path named after its
    /// first line unless one is given, and in the trash when deleted.
    init(
        body: String,
        path: String? = nil,
        created: Date,
        modified: Date? = nil,
        folderID: Folder.ID? = nil,
        isPinned: Bool = false,
        deleted: Date? = nil
    ) {
        var file = NoteFile(text: body)
        if isPinned { file.setFlag("pinned", true) }
        self.init(
            path: path ?? "\(NoteText.fileName(for: body)).md",
            text: file.text,
            created: created,
            modified: modified,
            folderID: folderID,
            deleted: deleted,
            binID: deleted == nil ? nil : UUID()
        )
    }
}

/// A store that keeps a list of the changes it is asked to make, and makes none.
final class RecordingStore: NoteStore, @unchecked Sendable {
    var changes: [StoreChange] = []
    var relocated: @MainActor @Sendable (String, String) -> Void = { _, _ in }
    var failed: @MainActor @Sendable (String, String) -> Void = { _, _ in }

    func load() throws -> StoredLibrary { StoredLibrary() }
    func perform(_ change: StoreChange) { changes.append(change) }
    func drain() {}
    func acknowledgeRelocation(of path: String) {}
    func freeAttachmentPath(named name: String) -> String { "Attachments/\(name)" }
}

/// A folder of its own in the temporary directory, removed when the test ends.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = URL.temporaryDirectory.appending(path: "MAPPTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ text: String, to path: String) throws {
        let file = url.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    func read(_ path: String) -> String? {
        try? String(contentsOf: url.appending(path: path), encoding: .utf8)
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appending(path: path).path)
    }
}
