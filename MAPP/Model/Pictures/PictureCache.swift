import CryptoKit
import Foundation
import Synchronization

/// The pictures fetched for notes, kept on this Mac so a picture shows again without a request or a question.
///
/// They live in the system's caches folder, in a folder of MAPP's own named for the bundle identifier, so a Debug and
/// a Release build never share them and the system may clear them. Each picture is in a folder named for a hash of
/// its address. When the pictures together pass `limit`, the least recently used go first.
actor PictureCache {
    /// The most the cache holds, in bytes.
    nonisolated static let standardLimit = 200 << 20

    nonisolated static var standardFolder: URL {
        URL.cachesDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "com.withmarfa.mapp", directoryHint: .isDirectory)
            .appending(path: "Remote Pictures", directoryHint: .isDirectory)
    }

    /// How many times each folder has been emptied by `removeAll`. A fetch that began before an emptying must not
    /// store its picture after it, and the lock is held for the emptying and for a store, so neither happens halfway
    /// through the other.
    private nonisolated static let emptied = Mutex<[URL: Int]>([:])

    nonisolated let folder: URL
    private let limit: Int
    private var sweptIncoming = false

    #if DEBUG
    nonisolated let hooks = TestHooks()
    #endif

    init(folder: URL = PictureCache.standardFolder, limit: Int = PictureCache.standardLimit) {
        self.folder = folder
        self.limit = limit
    }

    /// Where a fetch writes before the cache takes the file.
    nonisolated var incoming: URL { folder.appending(path: ".incoming", directoryHint: .isDirectory) }

    /// A token for what the cache holds now. Give it to `store` with a fetch's picture: the picture is kept only if
    /// the cache has not been emptied (the library disconnected) since the token was read.
    nonisolated var generation: Int { Self.emptied.withLock { $0[folder] ?? 0 } }

    /// Removes what an earlier run left in `incoming`, the first time it is asked and not again, since a fetch of this
    /// run may be writing there by then. Ask before the first fetch.
    func sweepIncomingOnce() {
        guard !sweptIncoming else { return }
        sweptIncoming = true
        try? FileManager.default.removeItem(at: incoming)
    }

    private func directory(for address: URL) -> URL {
        let hash = SHA256.hash(data: Data(address.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appending(path: hash, directoryHint: .isDirectory)
    }

    /// The file kept for the address, which then counts as used just now.
    func file(for address: URL) -> URL? {
        let directory = directory(for: address)
        guard let name = try? FileManager.default.contentsOfDirectory(atPath: directory.path).first(where: { !$0.hasPrefix(".") })
        else { return nil }
        let file = directory.appending(path: name, directoryHint: .notDirectory)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return file
    }

    /// Takes the fetched file in for the address and trims the cache to its limit. The file is the cache's from here
    /// on: if it is not kept, because this throws, it is removed.
    ///
    /// `generation` is the cache's `generation` from before the fetch began. If the cache was emptied since, the
    /// library was disconnected while the picture was on its way, so nothing is stored and `CancellationError` is thrown.
    func store(_ picture: FetchedPicture, for address: URL, generation: Int) throws -> URL {
        let kept: URL
        do {
            kept = try Self.emptied.withLock { emptied in
                let manager = FileManager.default
                guard (emptied[folder] ?? 0) == generation else { throw CancellationError() }
                let directory = directory(for: address)
                try? manager.removeItem(at: directory)
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
                let kept = directory.appending(path: "picture.\(picture.format.fileExtension)", directoryHint: .notDirectory)
                try manager.moveItem(at: picture.file, to: kept)
                try? manager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: kept.path)
                return kept
            }
        } catch {
            try? FileManager.default.removeItem(at: picture.file)
            throw error
        }
        // Outside the lock: it lists and reads every picture held, and the main actor reads `generation` under the lock.
        // An emptying that comes first leaves it a missing folder to list.
        trim()
        return kept
    }

    /// Removes the least recently used pictures until the rest fit.
    func trim() {
        #if DEBUG
        hooks.trimming.current?(Self.emptied.withLockIfAvailable { _ in true } ?? false)
        #endif
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: folder.path) else { return }
        var held: [(directory: URL, size: Int, used: Date)] = []
        for name in names where !name.hasPrefix(".") {
            let directory = folder.appending(path: name, directoryHint: .isDirectory)
            guard let files = try? manager.contentsOfDirectory(atPath: directory.path) else { continue }
            var size = 0
            var used = Date.distantPast
            for file in files {
                let attributes = try? manager.attributesOfItem(atPath: directory.appending(path: file).path)
                size += (attributes?[.size] as? Int) ?? 0
                used = max(used, (attributes?[.modificationDate] as? Date) ?? .distantPast)
            }
            held.append((directory, size, used))
        }
        var total = held.reduce(0) { $0 + $1.size }
        for entry in held.sorted(by: { $0.used < $1.used }) where total > limit {
            try? manager.removeItem(at: entry.directory)
            total -= entry.size
        }
    }

    /// Removes every picture, as when the library is disconnected, so pictures fetched for its notes don't outlast it.
    /// A fetch still on its way is not stored when it ends (`generation`).
    @concurrent static func removeAll(in folder: URL = standardFolder) async {
        emptied.withLock { emptied in
            emptied[folder, default: 0] += 1
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
