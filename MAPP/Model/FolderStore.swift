import Foundation
import OSLog
import os

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

    /// Where the notes folder is; it changes only when the folder itself is moved.
    var root: URL { location.withLock { $0 } }
    private let location: OSAllocatedUnfairLock<URL>
    private let bin: URL
    private let queue = DispatchQueue(label: "com.withmarfa.mapp.store")
    private let files = FileManager()
    // Set once, before the first change is queued.
    var relocated: @MainActor @Sendable (String, String) -> Void = { _, _ in }
    var imported: @MainActor @Sendable (UUID, String) -> Void = { _, _ in }
    var failed: @MainActor @Sendable (String, String) -> Void = { _, _ in }
    /// Paths the library gave that were taken, and the paths used instead, for the changes the library queued
    /// before it heard of the new path; once it has, the old path is its own again. Read and written on the
    /// queue only.
    private var aliases: [String: (path: String, before: Int?)] = [:]
    /// The number of each change as it is queued, and the one being made.
    private let queued = OSAllocatedUnfairLock(initialState: 0)
    private var making = 0
    /// Attachment paths handed out and not yet written, so two taken in a row are never the same.
    private let reservations = OSAllocatedUnfairLock(initialState: Set<String>())

    init(root: URL, bin: URL) {
        location = OSAllocatedUnfairLock(initialState: root)
        self.bin = bin
    }

    /// The notes folder was moved, in the Finder say: every change from now on, those already queued among them,
    /// is made where it now is.
    func move(to root: URL) {
        location.withLock { $0 = root }
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
                guard let safe = fileURL(for: path), safe == url.standardizedFileURL else { continue }
                if url.pathExtension.lowercased() == "md" {
                    if let note = read(url, path: path) { library.notes.append(note) }
                } else if let file = readFile(url, path: path) {
                    library.files.append(file)
                }
            }
            library.trash = readManifest().compactMap { entry in
                let url = binURL(entry.id)
                guard let text = readText(url) else { return nil }
                return TrashedNote(
                    id: entry.id,
                    note: StoredNote(path: entry.path, text: text, created: entry.created, modified: entry.modified),
                    trashed: entry.trashed
                )
            }
            return library
        }
    }

    func fileURL(for path: String) -> URL? {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { return nil }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let target = root.appending(path: path).standardizedFileURL
        let resolved = target.resolvingSymlinksInPath()
        guard resolved.pathComponents.starts(with: base.pathComponents), resolved.pathComponents.count > base.pathComponents.count,
              let values = try? target.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        return target
    }

    private func readFile(_ url: URL, path: String) -> StoredFile? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey, .documentIdentifierKey, .fileIdentifierKey]),
              values.isRegularFile == true else { return nil }
        let modified = values.contentModificationDate ?? .now
        return StoredFile(path: path, created: values.creationDate ?? modified, modified: modified,
                          byteCount: Int64(values.fileSize ?? 0),
                          fileID: values.documentIdentifier.map { UInt64(truncatingIfNeeded: $0) } ?? values.fileIdentifier)
    }

    private func read(_ url: URL, path: String) -> StoredNote? {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey, .documentIdentifierKey, .fileIdentifierKey]),
              values.isDirectory != true,
              let text = readText(url)
        else { return nil }
        let modified = values.contentModificationDate ?? .now
        return StoredNote(
            path: path, text: text, created: values.creationDate ?? modified, modified: modified,
            // A document identifier outlasts a safe save, and a file identifier stands in where there is none.
            fileID: values.documentIdentifier.map { UInt64(truncatingIfNeeded: $0) } ?? values.fileIdentifier
        )
    }

    private func relativePath(of url: URL) -> String {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return components.dropFirst(base.count).joined(separator: "/")
    }

    private func readText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Foundation's file/string initializers consume a UTF-8 BOM, which is part of the saved envelope.
        return String(validating: data, as: UTF8.self)
    }

    // MARK: Changing

    func perform(_ change: StoreChange) {
        let number = queued.withLock { count in
            count += 1
            return count
        }
        queue.async { [self] in
            making = number
            do {
                try make(change)
            } catch {
                log.error("\(String(describing: change).prefix(80), privacy: .private): \(error.localizedDescription, privacy: .public)")
                let failed = failed
                // The path the change was made at, which a failed move leaves as the file's old one.
                let path = change.path.map(resolved) ?? ""
                let message = error.localizedDescription
                Task { @MainActor in failed(path, message) }
            }
        }
    }

    func drain() {
        queue.sync {}
    }

    /// The path a change queued now means: the path used instead, while the change was queued before the
    /// library heard of it.
    private func resolved(_ path: String) -> String {
        guard let alias = aliases[path] else { return path }
        if let before = alias.before, making >= before {
            aliases[path] = nil
            return path
        }
        return alias.path
    }

    func acknowledgeRelocation(of path: String) {
        let last = queued.withLock { $0 }
        queue.async { [self] in aliases[path]?.before = last + 1 }
    }

    func freeAttachmentPath(named name: String) -> String {
        let name = (name as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return reservations.withLock { reserved in
            var number = 1
            while true {
                let file = number == 1 ? name : ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
                let path = "\(Self.attachments)/\(file)"
                // Names differing only in case are the same file on the usual Mac file system.
                if !reserved.contains(path.lowercased()), !files.fileExists(atPath: root.appending(path: path).path) {
                    reserved.insert(path.lowercased())
                    return path
                }
                number += 1
            }
        }
    }

    private func url(_ path: String) -> URL {
        root.appending(path: resolved(path), directoryHint: .notDirectory)
    }

    private func make(_ change: StoreChange) throws {
        // A notes folder moved or deleted is never made again where it was, which would scatter notes there.
        var isDirectory: ObjCBool = false
        guard files.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: root.path])
        }
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
            do {
                try move(source, to: target)
            } catch {
                // The file stays where it was, so what the library queued for the new path goes there too, rather
                // than making a second note under the new name; the library hears that the file did not move.
                report(to, source)
                throw error
            }
            report(to, target)
        case .trash(let path, let id, let date):
            let source = url(path)
            guard let note = read(source, path: path) else { return }
            // The entry is written first, so a file in the bin is never there without one saying where it was.
            let manifest = readManifest()
            try writeManifest(manifest + [BinEntry(id: id, path: path, trashed: date, created: note.created, modified: note.modified)])
            do {
                try move(source, to: binURL(id))
            } catch {
                try? writeManifest(manifest)
                throw error
            }
        case .restore(let id, let path):
            aliases[path] = nil
            let target = available(url(path))
            try move(binURL(id), to: target)
            try writeManifest(readManifest().filter { $0.id != id })
            report(path, target)
        case .importFile(let path, let source, let requestID):
            guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
                  !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }),
                  path.split(separator: "/").first != Substring(Self.attachments) else { throw CocoaError(.fileWriteInvalidFileName) }
            let target = available(root.appending(path: path))
            let base = root.standardizedFileURL.resolvingSymlinksInPath()
            guard target.resolvingSymlinksInPath().pathComponents.starts(with: base.pathComponents) else { throw CocoaError(.fileWriteNoPermission) }
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadUnsupportedScheme) }
            try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            var failure: Error?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges,
                                           writingItemAt: target, options: .forReplacing, error: &coordinationError) { from, to in
                do {
                    let coordinatedValues = try from.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard coordinatedValues.isRegularFile == true, coordinatedValues.isSymbolicLink != true,
                          to.resolvingSymlinksInPath().pathComponents.starts(with: base.pathComponents) else {
                        throw CocoaError(.fileWriteNoPermission)
                    }
                    // An interrupted copy must not appear as a complete item in the library.
                    let scratch = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: to, create: true)
                    defer { try? files.removeItem(at: scratch) }
                    let staged = scratch.appending(path: to.lastPathComponent)
                    try files.copyItem(at: from, to: staged)
                    // Move fails if another writer took the destination meanwhile; never overwrite it.
                    try files.moveItem(at: staged, to: to)
                } catch { failure = error }
            }
            if let error = coordinationError ?? failure { throw error }
            let actual = relativePath(of: target)
            let imported = imported
            Task { @MainActor in imported(requestID, actual) }
        case .attach(let path, let data):
            defer { reservations.withLock { _ = $0.remove(path.lowercased()) } }
            try writeNew(data, to: root.appending(path: path))
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
        aliases[path] = (actual, nil)
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

    /// The bin's list of what it holds. A list that cannot be read is set aside, never written over, and made
    /// again from the notes in the bin, each to come back at the top of the notes folder under its first line,
    /// since where it was went with the list.
    private func readManifest() -> [BinEntry] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        if let manifest = try? JSONDecoder().decode([BinEntry].self, from: data) { return manifest }
        log.error("the trash list could not be read; it is kept aside and made again")
        let aside = bin.appending(path: "Trash \(Int(Date.now.timeIntervalSince1970)).json")
        try? files.moveItem(at: manifestURL, to: aside)
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey]
        let found = (try? files.contentsOfDirectory(at: bin, includingPropertiesForKeys: keys)) ?? []
        let manifest = found.compactMap { url -> BinEntry? in
            guard url.pathExtension == "md", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let text = readText(url)
            else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let modified = values?.contentModificationDate ?? .now
            let name = NoteText.fileName(for: NoteFile(text: text).body)
            // When it was trashed went with the list; counting from now keeps it its full time in the bin.
            return BinEntry(id: id, path: "\(name).md", trashed: .now, created: values?.creationDate ?? modified, modified: modified)
        }
        try? writeManifest(manifest)
        return manifest
    }

    private func writeManifest(_ manifest: [BinEntry]) throws {
        try files.createDirectory(at: bin, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
    }
}
