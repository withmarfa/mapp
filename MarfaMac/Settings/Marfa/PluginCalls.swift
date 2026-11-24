import Foundation
import MarfaAPI

// What the Plugins page asks of the server and of the plugins release, in values of its own. The release is read by the app
// itself, never through the server, and sends no credential; the server is asked only to install, list, read and remove.

/// A plugin the server holds.
nonisolated struct InstalledPlugin: Identifiable, Hashable, Sendable {
    /// The connector the plugin brings, as its bundle declared it.
    struct Connector: Hashable, Sendable {
        var source: String
        var sourceName: String
    }

    let name: String
    var title: String
    var description: String
    /// An icon ID such as `lucide:ticket`.
    var mark: String
    var maker: String
    /// The oldest Marfa the installed version works with.
    var marfa: String
    var version: String
    /// The IDs of the types the plugin installed, at any version.
    var types: [String]
    var edgeTypes: [String]
    var connector: Connector?
    /// The connector host the connector is assigned to, where it has one.
    var host: String?
    /// The SHA-256 of the bundle's bytes as the install that wrote this version received them.
    var fingerprint: String
    var installedAt: Date?
    /// The name of the sign-in that first installed the plugin, where it is known.
    var installedBy: String?

    var id: String { name }
}

/// A plugin the release lists.
nonisolated struct ReleasePlugin: Identifiable, Hashable, Sendable {
    let name: String
    var title: String
    var description: String
    var mark: String
    var maker: String
    /// The oldest Marfa the version works with.
    var marfa: PluginVersion
    var version: PluginVersion
    /// The SHA-256 of the bundle's bytes as the release lists it, in hexadecimal.
    var sha256: String

    var id: String { name }
}

/// A bundle read from the release, whose bytes match the digest the release lists.
nonisolated struct ReleaseBundle: Hashable, Sendable {
    struct TypeDefinition: Hashable, Sendable {
        var id: String
        var label: String?
        var description: String?
        var icon: String?
    }

    struct EdgeTypeDefinition: Hashable, Sendable {
        var id: String
        var label: String?
        var description: String?
    }

    struct Connector: Hashable, Sendable {
        struct Kind: Hashable, Sendable {
            var name: String
            /// The ID of the type the kind is written as.
            var type: String
            /// `in`, `out` or `both`.
            var direction: String
        }

        var sourceName: String
        var kinds: [Kind]
    }

    var plugin: ReleasePlugin
    /// The bytes as the release serves them, which install unchanged.
    var bytes: Data
    var types: [TypeDefinition]
    var edgeTypes: [EdgeTypeDefinition]
    var connector: Connector?
}

/// How a type reads on the plugin's page: its name, and what it is based on.
nonisolated struct PluginTypeInfo: Hashable, Sendable {
    var label: String
    var plural: String?
    var parent: String?

    var title: String { plural ?? label }
}

/// What the server said after it took a bundle.
nonisolated struct PluginInstallAnswer: Hashable, Sendable {
    enum Outcome: Hashable, Sendable { case installed, updated, unchanged }

    var name: String
    var version: String
    var outcome: Outcome
    /// The SHA-256 the server recorded for the bytes it received.
    var fingerprint: String
}

/// What removing a plugin took away and what stayed, as the server answered.
nonisolated struct PluginRemoval: Hashable, Sendable {
    var name: String
    var version: String
    /// Whether the plugin had a connector, which stopped and lost its settings and secrets.
    var removedConnector: Bool
    var keptTypes: [String]
    var keptEdgeTypes: [String]
    /// What stays of the connector with its source, where the plugin had a connector.
    var keptConnector: KeptConnector?

    /// What a source keeps of a removed connector, for it to start again from.
    struct KeptConnector: Hashable, Sendable {
        var source: String
        /// Whether the source keeps a state document.
        var state: Bool
        var agreements: Int
    }
}

/// Why a call about a plugin did not do what was asked.
nonisolated enum PluginFailure: Error, Hashable, Sendable {
    case owner(OwnerFailure)
    case bundleFileUnreadable(name: String)
    /// The plugins release could not be read, in one line that does not name an address with a credential.
    case releaseUnreadable(String)
    /// A bundle's bytes are not the ones the release lists, so nothing was used.
    case digestMismatch(file: String)
    /// The plugin needs a later Marfa than the server runs.
    case needsNewerServer(marfa: String, server: String)
    /// The plugin's types carry guidance, and this Marfa takes that only from the command line: the server refused it from an app.
    case carriesGuidance
    /// The release lists another version or digest of the plugin than the page showed, or lists it no more.
    case releaseChanged
    /// A read was cancelled, or the owner closed the sign-in an install asked for. Neither is a failure and neither says anything.
    /// A bundle read is dropped. A release read puts back what it held. An install sent nothing.
    case canceled
}

/// What the Plugins page asks. A call that needs the server never queues.
nonisolated protocol PluginCalls: Sendable {
    /// Every plugin the server holds (`GET /plugins`).
    func installed() async throws(OwnerFailure) -> [InstalledPlugin]
    /// One plugin as the server holds it now (`GET /plugins/{name}`).
    func plugin(_ name: String) async throws(OwnerFailure) -> InstalledPlugin
    /// How each type the server lists is named and based, by its ID.
    func typeInfo() async throws(OwnerFailure) -> [String: PluginTypeInfo]
    /// The name of a connector host (`connectors.manage`).
    func hostName(_ id: String) async throws(OwnerFailure) -> String

    /// Where the release is read from, as a line says it: the plugins repository, or the address a Debug build was pointed at.
    var releaseName: String { get }
    /// The plugins the release lists, read without a credential.
    func release() async throws(PluginFailure) -> [ReleasePlugin]
    /// A bundle the release lists, checked against the digest the release lists.
    func bundle(of plugin: ReleasePlugin) async throws(PluginFailure) -> ReleaseBundle
    /// Installs a bundle as its bytes, unchanged (`POST /plugins`).
    func install(_ bundle: Data) async throws(PluginFailure) -> PluginInstallAnswer
    /// Removes a plugin, which keeps its types, edge types and items and deletes its connector's mapping (`DELETE /plugins/{name}`).
    func remove(_ name: String) async throws(OwnerFailure) -> PluginRemoval
}
