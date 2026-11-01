import Foundation
import Marfa

/// Sets and clears the owner's icon for a type on the Marfa server (`PUT` and `DELETE /types/{id}/icon`), which need
/// `schema.write` and write on the type. It uses the same address and key as the working copy, read from the key
/// store on each call, so a key the person has since replaced is the one used.
nonisolated struct MarfaServerTypeIcons: TypeIconSource {
    let connection: MarfaConnection
    let keys: any KeyStore
    /// How long a call waits for the server before it fails, so an unreachable server never leaves the picker waiting.
    var timeout = Duration.seconds(20)

    @concurrent func setIcon(_ icon: String?, ofType type: TypeID) async throws(TypeIconFailure) -> String? {
        let stored: String?
        do { stored = try keys.key(for: connection.address) } catch { throw .failed(Words.keyUnreadable) }
        guard let key = stored, !key.isEmpty else { throw .keyRefused }
        do {
            return try await connection.server(key: key).setTypeIcon(icon, ofType: type.rawValue, timeout: timeout)
        } catch {
            throw Self.failure(error)
        }
    }

    static func failure(_ error: any Error) -> TypeIconFailure {
        guard let error = error as? MarfaError else { return .failed(error.localizedDescription) }
        if error.isOffline { return .unreachable }
        if error.isKeyRefusal { return .keyRefused }
        switch error {
        case .forbidden: return .notPermitted
        case .validation(_, let message): return .refused(reason(message))
        default: return .failed(error.message)
        }
    }

    /// The server's sentence without the raw details the client appends to it.
    static func reason(_ message: String) -> String {
        message.components(separatedBy: " Details:").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? message
    }
}
