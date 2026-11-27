import Foundation

/// Reads and formats the local copy’s sizes while Connection is open.
nonisolated enum StoreSize {
    /// The allocated bytes of every regular file under the copy's folder.
    @concurrent static func bytes(of directory: URL) async -> UInt64? { sum(of: directory) }

    private static func sum(of directory: URL) -> UInt64? {
        guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
        guard let files = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey], options: [])
        else { return nil }
        var total: UInt64 = 0
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                values.isRegularFile == true
            else { continue }
            total += UInt64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// `bytes` as the Finder says it, such as "2.4 GB".
    static func text(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    /// Reads now and every 30 seconds until the page closes.
    static func keepReading(_ read: () async -> Void) async {
        await read()
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            await read()
        }
    }
}
