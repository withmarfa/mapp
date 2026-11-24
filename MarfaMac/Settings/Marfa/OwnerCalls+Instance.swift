import Foundation
import Marfa
import MarfaAPI
import OpenAPIRuntime

extension ClientOwnerCalls {
    func attention() async throws(OwnerFailure) -> [AttentionConcern] {
        try await run { client in
            try await client.listAttention().ok.body.json.data.map {
                AttentionConcern(
                    kind: AttentionConcern.Kind(rawValue: $0.kind.rawValue) ?? .unavailable, reference: $0.reference, title: $0.title)
            }
        }
    }

    func instanceMetrics() async throws(OwnerFailure) -> InstanceMetricsReading {
        try await run { client in
            let metrics = try await client.getInstanceMetrics().ok.body.json
            return InstanceMetricsReading(
                version: metrics.process.version, databaseBytes: metrics.storage.databaseBytes.map { Int($0) },
                fileBytes: Int(metrics.blobs.totalBytes))
        }
    }

    func fileStores() async throws(OwnerFailure) -> FileStores {
        try await run { client in
            let page = try await client.listBlobStores().ok.body.json
            let stores = page.data.filter { $0.detachedAt == nil }.map { store in
                let kind: FileStoreRow.Kind =
                    switch store.kind {
                    case .disk: .disk
                    case .folder: .folder
                    case .s3: .objectStore
                    }
                return FileStoreRow(id: store.id, kind: kind, locator: store.locator, error: store.error)
            }
            // The report is one answer; a next page is said, not read, so the count is shown as "at least".
            let orphans = try await client.listBlobOrphans().ok.body.json
            let count = orphans.data.count
            let bytes = orphans.data.reduce(0) { $0 + $1.sizeBytes }
            let first = orphans.data.first.flatMap { Self.date($0.reportedAt) }
            let complete = orphans.nextCursor == nil
            return FileStores(stores: stores, orphanCount: count, orphanBytes: bytes, firstFound: first, orphansComplete: complete)
        }
    }

    private static func enforcement(_ config: Components.Schemas.InstanceConfig) -> Enforcement {
        let levers = config.enforcement
        return Enforcement(
            instanceID: config.instanceId, strictTypes: levers?.strictMode?.types,
            allowlist: levers?.sourceAllowlist.map { .init(types: $0.types, sources: $0.sources) },
            filter: levers?.sourceFilter.map { .init(types: $0.types, sources: $0.sources) })
    }

    func enforcement() async throws(OwnerFailure) -> Enforcement {
        try await run { client in Self.enforcement(try await client.getConfig().ok.body.json) }
    }

    func setEnforcement(_ enforcement: Enforcement) async throws(OwnerFailure) -> Enforcement {
        try await run(plainConflict: Self.configConflict) { client in
            var body = Operations.UpdateConfig.Input.Body.JsonPayload()
            body.enforcement = Self.enforcementBody(enforcement)
            return Self.enforcement(
                try await client.updateConfig(headers: .init(xMarfaInstanceId: enforcement.instanceID), body: .json(body)).ok.body.json)
        }
    }

    /// All three levers, since the server replaces them together; with none, the enforcement is removed.
    static func enforcementBody(_ enforcement: Enforcement) -> Components.Schemas.MarfaNullableMarfaInlineaeb0b69539bcab54 {
        var levers = Components.Schemas.MarfaInlineaeb0b69539bcab54()
        levers.strictMode = enforcement.strictTypes.map { .init(types: $0) }
        levers.sourceAllowlist = enforcement.allowlist.map { .init(types: $0.types, sources: $0.sources) }
        levers.sourceFilter = enforcement.filter.map { .init(types: $0.types, sources: $0.sources) }
        let empty = levers.strictMode == nil && levers.sourceAllowlist == nil && levers.sourceFilter == nil
        return empty ? .null : .value(levers)
    }
}
