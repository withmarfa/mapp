import Foundation
import UniformTypeIdentifiers

/// The words a list row shows under a file's name in place of text. The core gives a text item's preview.
nonisolated enum ItemPreview {
    /// What a file's row says in place of text: its kind and size, as `Plain text, 76 bytes`. A size the library
    /// does not know is left out.
    static func file(_ type: UTType, byteCount: Int64) -> String {
        let described = type.localizedDescription ?? String(localized: "File")
        let kind = described.prefix(1).localizedUppercase + described.dropFirst()
        guard byteCount > 0 else { return kind }
        return kind + ", " + ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}
