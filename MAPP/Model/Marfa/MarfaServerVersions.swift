import Foundation
import Marfa
import MarfaAPI

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
        guard let key = try? keys.key(for: connection), !key.isEmpty else { throw .keyRefused }
        let client = Client(connection.server(key: key), timeout: timeout)
        do {
            let answer = try await client.listItemVersions(path: .init(id: id.rawValue), query: .init(limit: limit, cursor: cursor))
            let page = try answer.ok.body.json
            return ItemHistoryPage(snapshots: page.data.map(Self.snapshot), next: page.nextCursor)
        } catch {
            throw Self.failure(error)
        }
    }

    static func failure(_ error: any Error) -> ItemHistoryFailure {
        guard let error = error as? MarfaError else { return .failed(error.localizedDescription) }
        switch error {
        case .noConnection, .network: return .unreachable
        case .forbidden: return .notPermitted
        case .notFound: return .unavailable
        case .unauthorized, .signedOut: return .keyRefused
        default: return .failed(error.message)
        }
    }

    static func snapshot(_ version: Components.Schemas.Version) -> ItemSnapshot {
        ItemSnapshot(
            id: version.id, version: version.version, type: TypeID(version._type), properties: properties(version.properties),
            written: ItemDate.parse(version.occurredAt)?.date,
            writer: version.writer.map { writer in
                ItemSnapshot.Writer(kind: kind(writer.kind), name: writer.name)
            })
    }

    private static func kind(_ kind: Components.Schemas.Version.WriterPayload.KindPayload) -> ItemSnapshot.Writer.Kind {
        switch kind {
        case .browser: .browser
        case .app: .app
        case .key: .key
        case .local: .local
        }
    }

    /// The properties through their JSON, which the package's `JSONValue` reads as the rest of the app does.
    private static func properties(_ payload: Components.Schemas.Version.PropertiesPayload) -> [String: PropertyValue] {
        guard let data = try? JSONEncoder().encode(payload), let json = try? JSONDecoder().decode(JSONValue.self, from: data),
            case .object(let properties) = MarfaMapping.value(json)
        else { return [:] }
        return properties
    }
}
