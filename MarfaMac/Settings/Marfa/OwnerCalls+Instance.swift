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

    private static func limit(_ config: Components.Schemas.InstanceConfig) -> SourceLimit {
        let filter = config.enforcement?.sourceFilter
        return SourceLimit(
            instanceID: config.instanceId, isOn: filter != nil, types: filter?.types ?? [], sources: filter?.sources ?? [],
            strictTypes: config.enforcement?.strictMode?.types,
            allowlist: config.enforcement?.sourceAllowlist.map { ($0.types, $0.sources) })
    }

    func sourceLimit() async throws(OwnerFailure) -> SourceLimit {
        try await run { client in Self.limit(try await client.getConfig().ok.body.json) }
    }

    func setSourceRule(_ rule: SourceRule, of limit: SourceLimit, to value: SourceRuleValue?) async throws(OwnerFailure) -> SourceLimit {
        try await run(plainConflict: Self.configConflict) { client in
            var body = Operations.UpdateConfig.Input.Body.JsonPayload()
            body.enforcement = Self.enforcement(limit, setting: rule, to: value)
            return Self.limit(
                try await client.updateConfig(headers: .init(xMarfaInstanceId: limit.instanceID), body: .json(body)).ok.body.json)
        }
    }

    /// The enforcement a write sends: `rule` as given and the other levers as `limit` read them, since sending the enforcement
    /// replaces all three.
    static func enforcement(
        _ limit: SourceLimit, setting rule: SourceRule, to value: SourceRuleValue?
    ) -> MarfaNullable<Components.Schemas.MarfaInlineaeb0b69539bcab54> {
        var filter = limit.isOn ? SourceRuleValue(types: limit.types, sources: limit.sources) : nil
        var allowlist = limit.allowlist.map { SourceRuleValue(types: $0.types, sources: $0.sources) }
        switch rule {
        case .filter: filter = value
        case .allowlist: allowlist = value
        }
        var levers = Components.Schemas.MarfaInlineaeb0b69539bcab54()
        levers.strictMode = limit.strictTypes.map { .init(types: $0) }
        levers.sourceAllowlist = allowlist.map { .init(types: $0.types, sources: $0.sources) }
        levers.sourceFilter = filter.map { .init(types: $0.types, sources: $0.sources) }
        let empty = levers.strictMode == nil && levers.sourceAllowlist == nil && levers.sourceFilter == nil
        return empty ? .null : .value(levers)
    }
}
