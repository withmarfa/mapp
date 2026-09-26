import Foundation
import OSLog

nonisolated private let log = Logger(subsystem: "com.withmarfa.mapp", category: "store")

/// Notes as markdown files in a folder, as Marfa's folders keep them: each `.md` file is a note, each directory
/// at the top a folder, and anything whose name starts with a dot, such as Marfa's own `.marfa`, is not
/// MAPP's. The trash is kept apart from the folder, so a note trashed leaves the folder as a deleted file does.
///
/// Changes are made one at a time on a queue of the store's own, coordinated with any other app that
/// coordinates, and a file is only ever replaced whole, so another reader never sees half a note.
nonisolated final class FolderStore: NoteStore, @unchecked Sendable {
    /// The folder of attachments at the top of the notes folder, which holds files notes point at, not notes.
    static let attachments = "Attachments"

    let root: URL
    private let bin: URL
    private let queue = DispatchQueue(label: "com.withmarfa.mapp.store")
    private let files = FileManager()
    // Set once, before the first change is queued.
    var relocated: @MainActor @Sendable (String, String) -> Void = { _, _ in }
    var failed: @MainActor @Sendable (String, String) -> Void = { _, _ in }
    /// Paths the library gave that were taken, and the paths used instead. Read and written on the queue only, so
    /// a change the library queued before it heard of the new path still reaches the right file.
    private var aliases: [String: String] = [:]

    init(root: URL, bin: URL) {
        self.root = root
        self.bin = bin
    }

    // MARK: Reading

    func load() throws -> StoredLibrary {
        try queue.sync {
            var library = StoredLibrary()
            let keys: [URLResourceKey] = [.isDirectoryKey, .creationDateKey, .contentModificationDateKey]
            let top = try files.contentsOfDirectory(at: root, includingPropertiesForKeys: keys)
            for url in top where !url.lastPathComponent.hasPrefix(".") && url.lastPathComponent != Self.attachments {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    library.folders.append(url.lastPathComponent)
                }
            }
            guard let walk = files.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { return library }
            for case let url as URL in walk {
                let path = relativePath(of: url)
                if path == Self.attachments { walk.skipDescendants(); continue }
                guard url.pathExtension.lowercased() == "md", let note = read(url, path: path) else { continue }
                library.notes.append(note)
            }
            library.trash = readManifest().compactMap { entry in
                let url = binURL(entry.id)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return TrashedNote(
                    id: entry.id,
                    note: StoredNote(path: entry.path, text: text, created: entry.created, modified: entry.modified),
                    trashed: entry.trashed
                )
            }
            return library
        }
    }

    private func read(_ url: URL, path: String) -> StoredNote? {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey, .fileIdentifierKey]),
              values.isDirectory != true,
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        let modified = values.contentModificationDate ?? .now
        return StoredNote(
            path: path, text: text, created: values.creationDate ?? modified, modified: modified, fileID: values.fileIdentifier
        )
    }

    private func relativePath(of url: URL) -> String {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return components.dropFirst(base.count).joined(separator: "/")
    }

    // MARK: Changing

    func perform(_ change: StoreChange) {
        queue.async { [self] in
            do {
                try make(change)
            } catch {
                log.error("\(String(describing: change).prefix(80), privacy: .private): \(error.localizedDescription, privacy: .public)")
                let failed = failed
                let path = change.path ?? ""
                let message = error.localizedDescription
                Task { @MainActor in failed(path, message) }
            }
        }
    }

    func drain() {
        queue.sync {}
    }

    private func url(_ path: String) -> URL {
        root.appending(path: aliases[path] ?? path, directoryHint: .notDirectory)
    }

    private func make(_ change: StoreChange) throws {
        switch change {
        case .create(let path, let text):
            aliases[path] = nil
            let target = available(url(path))
            try writeNew(Data(text.utf8), to: target)
            report(path, target)
        case .write(let path, let text):
            let target = url(path)
            let data = Data(text.utf8)
            guard files.fileExists(atPath: target.path) else { return try writeNew(data, to: target) }
            guard (try? Data(contentsOf: target)) != data else { return }
            try replace(target, with: data)
        case .move(let from, let to):
            let source = url(from)
            aliases[from] = nil
            aliases[to] = nil
            let target = available(url(to), besides: source)
            try move(source, to: target)
            report(to, target)
        case .trash(let path, let id, let date):
            let source = url(path)
            guard let note = read(source, path: path) else { return }
            try files.createDirectory(at: bin, withIntermediateDirectories: true)
            try move(source, to: binURL(id))
            var manifest = readManifest()
            manifest.append(BinEntry(id: id, path: path, trashed: date, created: note.created, modified: note.modified))
            try writeManifest(manifest)
        case .restore(let id, let path):
            aliases[path] = nil
            let target = available(url(path))
            try move(binURL(id), to: target)
            try writeManifest(readManifest().filter { $0.id != id })
            report(path, target)
        case .purge(let id):
            try? files.removeItem(at: binURL(id))
            try writeManifest(readManifest().filter { $0.id != id })
        case .purgeTrash(let date):
            let manifest = readManifest()
            let expired = manifest.filter { $0.trashed < date }
            guard !expired.isEmpty else { return }
            for entry in expired { try? files.removeItem(at: binURL(entry.id)) }
            try writeManifest(manifest.filter { $0.trashed >= date })
        case .createFolder(let path):
            try files.createDirectory(at: root.appending(path: path, directoryHint: .isDirectory), withIntermediateDirectories: true)
        case .moveFolder(let from, let to):
            try move(root.appending(path: from, directoryHint: .isDirectory), to: root.appending(path: to, directoryHint: .isDirectory))
        case .removeFolder(let path):
            let folder = root.appending(path: path, directoryHint: .isDirectory)
            guard holdsNothing(folder) else { return }
            try coordinated(writing: folder, options: .forDeleting) { try files.removeItem(at: $0) }
        }
    }

    /// Whether a directory holds nothing anyone would miss: only empty directories and the Finder's own
    /// `.DS_Store`. A hidden file is someone's, Marfa's or git's, and keeps the directory.
    private func holdsNothing(_ folder: URL) -> Bool {
        guard let walk = files.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return true }
        for case let url as URL in walk where url.lastPathComponent != ".DS_Store" {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true { return false }
        }
        return true
    }

    private func report(_ path: String, _ target: URL) {
        let actual = relativePath(of: target)
        guard actual != path else { return }
        aliases[path] = actual
        let relocated = relocated
        Task { @MainActor in relocated(path, actual) }
    }

    /// The URL, or the first free one numbered after it, as the Finder numbers a copy. A file moving onto its own
    /// name in another case, which the file system takes for the same name, keeps it.
    private func available(_ url: URL, besides source: URL? = nil) -> URL {
        guard files.fileExists(atPath: url.path) else { return url }
        if let source, isSameFile(source, url) { return url }
        let directory = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var number = 2
        while true {
            let candidate = directory.appending(path: ext.isEmpty ? "\(name) \(number)" : "\(name) \(number).\(ext)")
            if !files.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    private func isSameFile(_ a: URL, _ b: URL) -> Bool {
        let key = URLResourceKey.fileResourceIdentifierKey
        guard let first = try? a.resourceValues(forKeys: [key]).fileResourceIdentifier,
              let second = try? b.resourceValues(forKeys: [key]).fileResourceIdentifier
        else { return false }
        return first.isEqual(second)
    }

    private func writeNew(_ data: Data, to target: URL) throws {
        try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try coordinated(writing: target, options: .forReplacing) { url in
            try data.write(to: url, options: .withoutOverwriting)
        }
    }

    /// Replaces the file whole: the new text is written apart from the notes folder and swapped in, so the
    /// folder never holds a partial or temporary file, and the file keeps its creation date.
    private func replace(_ target: URL, with data: Data) throws {
        try coordinated(writing: target, options: .forReplacing) { url in
            let scratch = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
            defer { try? files.removeItem(at: scratch) }
            let staged = scratch.appending(path: url.lastPathComponent)
            try data.write(to: staged)
            _ = try files.replaceItemAt(url, withItemAt: staged)
        }
    }

    private func move(_ source: URL, to target: URL) throws {
        try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        var failure: Error?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: source, options: .forMoving, writingItemAt: target, options: .forReplacing, error: &coordinationError) { from, to in
            do {
                try files.moveItem(at: from, to: to)
                coordinator.item(at: from, didMoveTo: to)
            } catch {
                failure = error
            }
        }
        if let error = coordinationError ?? failure { throw error }
    }

    private func coordinated(writing url: URL, options: NSFileCoordinator.WritingOptions, _ body: (URL) throws -> Void) throws {
        var failure: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinationError) { url in
            do { try body(url) } catch { failure = error }
        }
        if let error = coordinationError ?? failure { throw error }
    }

    // MARK: The trash

    private struct BinEntry: Codable {
        var id: UUID
        var path: String
        var trashed: Date
        var created: Date
        var modified: Date
    }

    private func binURL(_ id: UUID) -> URL {
        bin.appending(path: "\(id.uuidString).md")
    }

    private var manifestURL: URL { bin.appending(path: "Trash.json") }

    private func readManifest() -> [BinEntry] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        return (try? JSONDecoder().decode([BinEntry].self, from: data)) ?? []
    }

    private func writeManifest(_ manifest: [BinEntry]) throws {
        try files.createDirectory(at: bin, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
    }
}
