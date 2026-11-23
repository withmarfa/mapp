import Foundation
import Marfa
import MarfaAPI

/// `PluginCalls` over the package's generated client, its server (for installing a bundle as its bytes) and its release reader.
/// A bundle is read with the index again, so a call needs no value the package hides.
nonisolated struct ClientPluginCalls: PluginCalls {
    let owner: ClientOwnerCalls
    /// The release the app reads, or nil for the latest release of the plugins repository.
    let releaseAddress: String?

    init(
        server: (@Sendable () throws -> Server)?, client: @escaping @Sendable () throws -> Client, releaseAddress: String? = nil
    ) {
        owner = ClientOwnerCalls(server: server, client: client)
        self.releaseAddress = releaseAddress
    }

    // MARK: The server

    func installed() async throws(OwnerFailure) -> [InstalledPlugin] {
        try await owner.run { client in try await client.listPlugins().ok.body.json.data.map(Self.record) }
    }

    func plugin(_ name: String) async throws(OwnerFailure) -> InstalledPlugin {
        try await owner.run { client in Self.record(try await client.getPlugin(path: .init(name: name)).ok.body.json) }
    }

    func typeInfo() async throws(OwnerFailure) -> [String: PluginTypeInfo] {
        try await owner.run { client in
            var info: [String: PluginTypeInfo] = [:]
            for type in try await client.listTypes().ok.body.json.data {
                let own = type.value1
                info[own.id] = PluginTypeInfo(label: own.label ?? own.id, plural: own.plural, parent: own.parent)
            }
            return info
        }
    }

    func hostName(_ id: String) async throws(OwnerFailure) -> String {
        try await owner.run { client in try await client.getConnectorHost(path: .init(id: id)).ok.body.json.name }
    }

    func remove(_ name: String) async throws(OwnerFailure) -> PluginRemoval {
        try await owner.run { client in
            let answer = try await client.removePlugin(path: .init(name: name)).ok.body.json
            return PluginRemoval(
                name: answer.removed.name, version: answer.removed.version, removedConnector: answer.removed.connector != nil,
                keptTypes: answer.kept.types, keptEdgeTypes: answer.kept.edgeTypes)
        }
    }

    func install(_ bundle: Data) async throws(PluginFailure) -> PluginInstallAnswer {
        let server: Server
        do {
            guard let make = owner.server else { throw OwnerFailure.signedOut }
            server = try make()
        } catch {
            throw .owner(error as? OwnerFailure ?? ClientOwnerCalls.failure(error))
        }
        do {
            let answer = try await server.install(pluginBundle: bundle)
            let outcome: PluginInstallAnswer.Outcome =
                switch answer.outcome {
                case .installed: .installed
                case .updated: .updated
                case .unchanged: .unchanged
                }
            return PluginInstallAnswer(name: answer.name, version: answer.version, outcome: outcome, fingerprint: answer.fingerprint)
        } catch {
            throw Self.refusal(error)
        }
    }

    /// The two refusals that name a plugin are told apart; every other is told as an owner's call is.
    static func refusal(_ error: MarfaError) -> PluginFailure {
        switch error.pluginInstallRefusal {
        case .needsNewerServer(let marfa, let server)?: .needsNewerServer(marfa: marfa, server: server)
        case .carriesGuidance?: .carriesGuidance
        case nil: .owner(ClientOwnerCalls.failure(error))
        }
    }

    // MARK: The release

    func release() async throws(PluginFailure) -> [ReleasePlugin] {
        do {
            return try await PluginRelease(address: releaseAddress).index().map(Self.listed)
        } catch { throw Self.failure(error) }
    }

    func bundle(of plugin: ReleasePlugin) async throws(PluginFailure) -> ReleaseBundle {
        do throws(PluginReleaseError) {
            let release = try PluginRelease(address: releaseAddress)
            guard let entry = try await release.index().first(where: { $0.name == plugin.name }) else {
                throw PluginReleaseError.unreachable(address: release.address, reason: "the release no longer lists \(plugin.name)")
            }
            return Self.bundle(try await release.bundle(for: entry))
        } catch { throw Self.failure(error) }
    }

    private static func listed(_ entry: PluginIndexEntry) -> ReleasePlugin {
        ReleasePlugin(
            name: entry.name, title: entry.title, description: entry.description, mark: entry.mark, maker: entry.maker,
            marfa: entry.marfa, version: entry.version, sha256: entry.sha256)
    }

    private static func bundle(_ released: ReleasedPlugin) -> ReleaseBundle {
        let contents = released.contents
        return ReleaseBundle(
            plugin: listed(released.entry), bytes: released.bytes,
            types: contents.types.map {
                .init(id: $0.id, label: $0.label, description: $0.description, icon: $0.icon, hasGuidance: !($0.guidance ?? "").isEmpty)
            },
            edgeTypes: contents.edgeTypes.map { .init(id: $0.id, label: $0.label, description: $0.description) },
            connector: contents.connector.map { connector in
                .init(
                    sourceName: connector.sourceName,
                    kinds: connector.kinds.map { .init(name: $0.name, type: $0.type, direction: $0.direction) })
            })
    }

    /// What a release that could not be read says, without an address that carried a credential.
    static func failure(_ error: PluginReleaseError) -> PluginFailure {
        switch error {
        case .digestMismatch(let file, _, _): .digestMismatch(file: file)
        case .addressCarriesCredentials, .addressUnreadable, .unreachable, .canceled:
            .releaseUnreadable(String(localized: "MAPP couldn’t reach it, or it served something that isn’t a release. Installed plugins and Install From a File… still work."))
        }
    }

    // MARK: Reading

    private static func record(_ plugin: Components.Schemas.Plugin) -> InstalledPlugin {
        InstalledPlugin(
            name: plugin.name, title: plugin.title, description: plugin.description, mark: plugin.mark, maker: plugin.maker,
            marfa: plugin.marfa, version: plugin.version, types: plugin.types, edgeTypes: plugin.edgeTypes,
            connector: plugin.connector.value.map { InstalledPlugin.Connector(source: $0.source, sourceName: $0.sourceName) },
            host: plugin.connectorHost, fingerprint: plugin.fingerprint, installedAt: plugin.installedAt,
            installedBy: plugin.installedBy.value?.name)
    }
}
