import Foundation
import Marfa
import MarfaAPI

/// Sets and clears the owner's icon for a type on the Marfa server (`PUT` and `DELETE /types/{id}/icon`), which need
/// `schema.write` and write on the type. It uses the same address and key as the working copy, read from the key
/// store on each call, so a key the person has since replaced is the one used.
nonisolated struct MarfaServerTypeIcons: TypeIconSource {
    let connection: MarfaConnection
    let keys: any KeyStore
    /// How long a call waits for the server before it fails, so an unreachable server never leaves the picker waiting.
    var timeout = Duration.seconds(20)

    @concurrent func setIcon(_ icon: String?, ofType type: TypeID) async throws(TypeIconFailure) -> String? {
        guard let key = try? keys.key(for: connection), !key.isEmpty else { throw .keyRefused }
        let client = Client(connection.server(key: key), timeout: timeout)
        do {
            let answer: Components.Schemas.RegisteredType
            if let icon {
                answer = try await client.set(icon: icon, forType: type.rawValue)
            } else {
                answer = try await client.clearIcon(ofType: type.rawValue)
            }
            return answer.value1.displayHints?.icon
        } catch {
            throw Self.failure(error)
        }
    }

    static func failure(_ error: any Error) -> TypeIconFailure {
        guard let error = error as? MarfaError else { return .failed(error.localizedDescription) }
        switch error {
        case .noConnection, .network: return .unreachable
        case .forbidden: return .notPermitted
        case .unauthorized, .signedOut: return .keyRefused
        case .validation(_, let message): return .refused(reason(message))
        default: return .failed(error.message)
        }
    }

    /// The server's sentence without the raw details the client appends to it.
    static func reason(_ message: String) -> String {
        message.components(separatedBy: " Details:").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? message
    }
}
