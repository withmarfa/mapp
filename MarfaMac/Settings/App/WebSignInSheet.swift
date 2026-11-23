import AppKit
import AuthenticationServices
import Synchronization

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
            // The completion handler and a refused start can both answer; the first one counts.
            let answer = Mutex(Optional(continuation))
            let finish: @Sendable (Bool) -> Void = { came in
                answer.withLock { held in
                    held?.resume(returning: came)
                    held = nil
                }
            }
            let session = ASWebAuthenticationSession(url: address, callback: .customScheme(scheme)) { callback, _ in
                finish(callback != nil)
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() { finish(false) }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }
}
