import Foundation
import Marfa
import MarfaAPI
import MarfaTypes

extension MarfaServerCalls {
    /// The name the owner gave themselves, where the server tells it to this sign-in; nil where it does not.
    @concurrent func ownerName() async -> String? {
        guard let name = try? await client().getProfile().ok.body.json.name, !name.isEmpty else { return nil }
        return name
    }
}
