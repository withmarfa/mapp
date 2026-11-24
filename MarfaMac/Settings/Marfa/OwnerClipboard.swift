import AppKit

/// Where a secret shown once, or the steps to take on the server's machine, is copied to.
enum OwnerClipboard {
    /// Puts plain text, which is no secret, on the clipboard.
    @MainActor static func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// How long a copied secret stays on the clipboard before it is taken off, if nothing else was copied since.
    private static let life: Duration = .seconds(60)

    /// The clipboard's change count just after the last secret was copied, while that secret may still be on it.
    @MainActor private static var secretCount: Int?
    @MainActor private static var quitObserver: (any NSObjectProtocol)?

    /// Puts the secret on the clipboard marked concealed and transient, so clipboard managers do not keep it, and takes it
    /// off again after a minute, or when the app quits before then, unless something else has been copied since.
    @MainActor static func copySecret(_ secret: String) {
        let pasteboard = NSPasteboard.general
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        // The count comes from the write itself: a read after it could already be another app's copy.
        let count = pasteboard.declareTypes([.string, concealed, transient], owner: nil)
        pasteboard.setString(secret, forType: .string)
        pasteboard.setData(Data(), forType: concealed)
        pasteboard.setData(Data(), forType: transient)
        secretCount = count
        clearAtQuit()
        Task {
            try? await Task.sleep(for: life)
            clearSecret(copiedAt: count)
        }
    }

    /// Takes the secret copied at `count` off the clipboard if it is still there: a later copy, ours or another app's, has
    /// moved the change count on, and is left alone.
    @MainActor private static func clearSecret(copiedAt count: Int) {
        guard secretCount == count else { return }
        secretCount = nil
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount == count { pasteboard.clearContents() }
    }

    /// Watches for the app quitting, once, since the minute's timer dies with it.
    @MainActor private static func clearAtQuit() {
        guard quitObserver == nil else { return }
        quitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                if let count = secretCount { clearSecret(copiedAt: count) }
            }
        }
    }
}
