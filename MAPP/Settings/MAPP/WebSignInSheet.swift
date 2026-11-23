import AppKit
import AuthenticationServices

/// The system's web authentication sheet over a window, for a page the server shows and then sends the browser back from, such
/// as a connector's sign-in at its service. It ends where the browser comes back to the app's own address, and keeps no
/// cookies of the browser's apart from the system's own session.
@MainActor final class WebSignInSheet: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let window: NSWindow
    private var session: ASWebAuthenticationSession?

    private init(window: NSWindow) {
        self.window = window
    }

    /// Shows `address` and answers whether the browser came back to an address of `scheme`; false where the sheet was closed
    /// or could not be shown.
    static func show(_ address: URL, endingOn scheme: String, over window: NSWindow) async -> Bool {
        let sheet = WebSignInSheet(window: window)
        return await sheet.run(address, scheme: scheme)
    }

    private func run(_ address: URL, scheme: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(url: address, callback: .customScheme(scheme)) { callback, _ in
                continuation.resume(returning: callback != nil)
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() { continuation.resume(returning: false) }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }
}
