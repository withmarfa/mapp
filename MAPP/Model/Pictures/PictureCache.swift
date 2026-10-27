import CryptoKit
import Foundation

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

    nonisolated let folder: URL
    private let limit: Int

    init(folder: URL = PictureCache.standardFolder, limit: Int = PictureCache.standardLimit) {
        self.folder = folder
        self.limit = limit
    }

    /// Where a fetch writes before the cache takes the file.
    nonisolated var incoming: URL { folder.appending(path: ".incoming", directoryHint: .isDirectory) }

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

    /// Takes the fetched file in for the address and trims the cache to its limit.
    func store(_ picture: FetchedPicture, for address: URL) throws -> URL {
        let manager = FileManager.default
        let directory = directory(for: address)
        try? manager.removeItem(at: directory)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let kept = directory.appending(path: "picture.\(picture.format.fileExtension)", directoryHint: .notDirectory)
        try manager.moveItem(at: picture.file, to: kept)
        try? manager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: kept.path)
        trim()
        return kept
    }

    /// Removes the least recently used pictures until the rest fit.
    func trim() {
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
    @concurrent static func removeAll(in folder: URL = standardFolder) async {
        try? FileManager.default.removeItem(at: folder)
    }
}
