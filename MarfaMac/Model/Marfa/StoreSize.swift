import Foundation

/// Formats the local copy’s sizes and schedules reads while Connection is open.
nonisolated enum StoreSize {
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
