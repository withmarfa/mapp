import Foundation

/// How much room the copy of a library takes on this Mac: every file in its store folder, which the package does not
/// report (it reports the bytes of downloaded files only).
nonisolated enum StoreSize {
    /// The bytes of every regular file under `directory`, or nil where the folder cannot be read.
    @concurrent static func bytes(of directory: URL) async -> UInt64? { sum(of: directory) }

    static func sum(of directory: URL) -> UInt64? {
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
}
