import Foundation
import Marfa

/// Reads an item's snapshots from the Marfa server (`GET /items/{id}/versions`). The working copy keeps no history,
/// so this is the one read that asks the server and fails while it cannot be reached. The key is read from the key
/// store on each call, so a key the person has since replaced is the one used. Unlike the copy, which goes through the
/// package's core, this call goes through `URLSession`, so App Transport Security applies to a plain http address.
nonisolated struct MarfaServerVersions: ItemHistorySource {
    let connection: MarfaConnection
    let keys: any KeyStore
    /// How long a call waits for the server to answer before it fails, so an unreachable server never leaves the
    /// sheet waiting.
    var timeout = Duration.seconds(20)

    @concurrent func page(of id: ItemID, after cursor: String?, limit: Int) async throws(ItemHistoryFailure) -> ItemHistoryPage {
        let stored: String?
        do { stored = try keys.key(for: connection.address) } catch { throw .failed(Words.keyUnreadable) }
        guard let key = stored, !key.isEmpty else { throw .keyRefused }
        do {
            let page = try await connection.server(key: key).snapshots(
                ofItem: id.rawValue, after: cursor, limit: limit, timeout: timeout)
            return ItemHistoryPage(snapshots: page.snapshots.map(Self.snapshot), next: page.next)
        } catch {
            throw Self.failure(error)
        }
    }

    static func failure(_ error: any Error) -> ItemHistoryFailure {
        guard let error = error as? MarfaError else { return .failed(error.localizedDescription) }
        if error.isOffline { return .unreachable }
        if error.isKeyRefusal { return .keyRefused }
        switch error {
        case .forbidden: return .notPermitted
        case .notFound: return .unavailable
        default: return .failed(error.message)
        }
    }

    static func snapshot(_ version: Marfa.ItemSnapshot) -> ItemSnapshot {
        ItemSnapshot(
            id: version.id, version: version.version, type: TypeID(version.type),
            properties: properties(version.properties), written: version.occurredAt?.date,
            writer: version.writer.map { writer in
                ItemSnapshot.Writer(kind: kind(writer.kind), name: writer.name)
            })
    }

    private static func kind(_ kind: Marfa.ItemSnapshot.Writer.Kind) -> ItemSnapshot.Writer.Kind {
        switch kind {
        case .browser: .browser
        case .app: .app
        case .key: .key
        case .local: .local
        case .other: .key
        }
    }

    private static func properties(_ object: JSONObject) -> [String: PropertyValue] {
        guard case .object(let properties) = MarfaMapping.value(.object(object)) else { return [:] }
        return properties
    }
}
