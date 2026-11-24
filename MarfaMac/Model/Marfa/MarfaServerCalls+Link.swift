import Foundation
import Marfa

extension MarfaServerCalls: ItemLinkSource {
    /// How long Copy Link waits for the server before it copies the `marfa://` link instead.
    static let linkTimeout = Duration.seconds(5)

    /// The item's `https` link from the package's `itemLinks(of:timeout:)`, which checks it is a web address.
    @concurrent func webLink(of id: ItemID) async throws -> URL {
        try await server().itemLinks(of: id.rawValue, timeout: min(timeout, Self.linkTimeout)).web
    }
}
