import Foundation
import Marfa

/// Reads which scopes a server grants, from its authorization server metadata (`scopes_supported`, RFC 8414), so a
/// sign-in asks only for what the server offers. The server lists a vendor's scope (`app.<vendor>.*:write`) only once a
/// type sits under that vendor, so the first app of a vendor cannot ask for it (`keys-and-oauth/app-vendor-not-named`).
///
/// The package reads the same document to sign in but offers no way to read its scopes, so the app reads it here, from
/// the Marfa server alone. A read that fails throws, and the sign-in does not start: it never guesses what is offered.
/// A transport failure is the `URLError` the session threw; an answer that is no Marfa metadata is a `SignInError`, which
/// `SignInOutcome` words as no Marfa server.
nonisolated struct OfferedScopes: Sendable {
    /// The scopes the server at `address` offers.
    let read: @Sendable (_ address: URL) async throws -> Set<String>

    init(_ read: @escaping @Sendable (URL) async throws -> Set<String>) {
        self.read = read
    }

    /// The metadata's address on a server's origin.
    static let path = "/.well-known/oauth-authorization-server"

    /// Reads the metadata over `URLSession`, as every call to the server does, so App Transport Security applies to a plain
    /// http address.
    static let fromServer = OfferedScopes.reading { request in
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }

    /// Reads the metadata through `fetch`, which a test answers without a network.
    static func reading(through fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) -> OfferedScopes {
        OfferedScopes { address in
            // The metadata is at the server's origin, whatever path the address typed carries.
            guard var parts = URLComponents(url: address, resolvingAgainstBaseURL: false) else { throw unreadable(address) }
            parts.path = path
            parts.query = nil
            parts.fragment = nil
            guard let metadata = parts.url else { throw unreadable(address) }
            var request = URLRequest(url: metadata, timeoutInterval: TimeInterval(Server.defaultTimeout.components.seconds))
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (body, response) = try await fetch(request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            // An answer from another origin, which a redirect may bring, is not this server's.
            guard let answered = http.url, answered.scheme == metadata.scheme, answered.host == metadata.host, answered.port == metadata.port
            else { throw SignInError.unreadable(message: "the sign-in metadata did not come from the server asked") }
            return try parse(status: http.statusCode, body: body)
        }
    }

    private static func unreadable(_ address: URL) -> SignInError {
        .unreadable(message: "\(address.absoluteString) is not an address the sign-in metadata can be read from")
    }

    /// The scopes a metadata answer lists. Anything but a 200 with a `scopes_supported` list of strings is no answer.
    static func parse(status: Int, body: Data) throws -> Set<String> {
        guard status == 200 else { throw SignInError.refused(code: "http_\(status)", message: "the server answered \(status)") }
        guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
            let scopes = object["scopes_supported"] as? [String]
        else { throw SignInError.unreadable(message: "the sign-in metadata lists no scopes this app can read") }
        return Set(scopes)
    }
}
