import AppKit

/// Where a secret shown once is copied to.
enum OwnerClipboard {
    /// How long a copied secret stays on the clipboard before it is taken off, if nothing else was copied since.
    private static let life: Duration = .seconds(60)

    /// Puts the secret on the clipboard marked concealed and transient, so clipboard managers do not keep it, and takes it
    /// off again after a minute unless something else has been copied since.
    @MainActor static func copySecret(_ secret: String) {
        let pasteboard = NSPasteboard.general
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        pasteboard.declareTypes([.string, concealed, transient], owner: nil)
        pasteboard.setString(secret, forType: .string)
        pasteboard.setData(Data(), forType: concealed)
        pasteboard.setData(Data(), forType: transient)
        let count = pasteboard.changeCount
        Task {
            try? await Task.sleep(for: life)
            if pasteboard.changeCount == count { pasteboard.clearContents() }
        }
    }
}
