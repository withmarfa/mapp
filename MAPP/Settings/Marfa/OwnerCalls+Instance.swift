import Foundation
import Marfa
import MarfaAPI
import OpenAPIRuntime

extension ClientOwnerCalls {
    func attention() async throws(OwnerFailure) -> [AttentionConcern] {
        try await run { client in
            try await client.listAttention().ok.body.json.data.map {
                AttentionConcern(
                    kind: AttentionConcern.Kind(rawValue: $0.kind.rawValue) ?? .unavailable, reference: $0.reference, title: $0.title,
                    description: $0.description)
            }
        }
    }

    func reading() async throws(OwnerFailure) -> InstanceReading {
        try await run { client in
            var reading = InstanceReading()
            if let metrics = try? await client.getInstanceMetrics().ok.body.json {
                reading.version = metrics.process.version
                reading.databaseBytes = metrics.storage.databaseBytes.map { Int($0) }
                reading.fileBytes = Int(metrics.blobs.totalBytes)
            }
            if let update = try? await client.getUpdate().ok.body.json {
                if update.available, let latest = update.latest.value { reading.updateReady = latest.release }
                if reading.version == nil { reading.version = update.release }
            }
            // Reading backups needs `backups.manage`, which the sign-in may not hold: then no time is shown.
            reading.lastBackup = (try? await client.listBackups().ok.body.json.data)?.map(\.createdAt).max()
            reading.owner = try? await client.getProfile().ok.body.json.username
            return reading
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
            let total = (try? await client.getInstanceMetrics().ok.body.json.blobs.totalBytes).map { Int($0) }
            return FileStores(stores: stores, fileBytes: total, orphanCount: count, orphanBytes: bytes, firstFound: first, orphansComplete: complete)
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

    func setSourceLimit(_ limit: SourceLimit, to filter: (types: [String], sources: [String])?) async throws(OwnerFailure) -> SourceLimit {
        try await run(plainConflict: Self.configConflict) { client in
            // Sending the enforcement replaces all three levers, so the other two go back as they were read.
            var levers = Components.Schemas.MarfaInlineaeb0b69539bcab54()
            levers.strictMode = limit.strictTypes.map { .init(types: $0) }
            levers.sourceAllowlist = limit.allowlist.map { .init(types: $0.types, sources: $0.sources) }
            levers.sourceFilter = filter.map { .init(types: $0.types, sources: $0.sources) }
            var body = Operations.UpdateConfig.Input.Body.JsonPayload()
            let empty = levers.strictMode == nil && levers.sourceAllowlist == nil && levers.sourceFilter == nil
            body.enforcement = empty ? .null : .value(levers)
            return Self.limit(
                try await client.updateConfig(headers: .init(xMarfaInstanceId: limit.instanceID), body: .json(body)).ok.body.json)
        }
    }
}
