import Foundation

// What the Overview, File Storage and Limit Sources pages read of the server, in values of their own so the pages read
// nothing generated and a test can script every answer.

/// One thing the server says needs the owner's attention, as `GET /attention` words it.
nonisolated struct AttentionConcern: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case health, job, connector, folder, key, backup, setting, clock, fault, unavailable
    }

    let kind: Kind
    /// What the concern is about: a key's id for a key, a code for the rest.
    let reference: String
    let title: String
    let description: String

    var id: String { kind.rawValue + "/" + reference }
}

/// How a part of the server stands, as `GET /health` words it, or `unknown` where the server could not check.
nonisolated enum Condition: String, Hashable, Sendable {
    case ok, degraded, down, unknown
}

/// How one part of the server stands.
nonisolated struct HealthPart: Hashable, Sendable {
    var condition: Condition
}

nonisolated struct BackupsHealth: Hashable, Sendable {
    enum State: String, Hashable, Sendable { case ok, incomplete, failing, off, unknown }

    var state: State
    var lastBackup: Date?
}

/// What the Overview reads of the server besides what needs attention. Every part is optional: a part the server did not give
/// is left out, never guessed.
nonisolated struct InstanceReading: Hashable, Sendable {
    /// The release the server runs.
    var version: String?
    /// A later release the server says is ready, if one is.
    var updateReady: String?
    var databaseBytes: Int?
    var fileBytes: Int?
    var lastBackup: Date?
    /// The owner's username, where the sign-in may read it.
    var owner: String?
}

nonisolated struct FileStoreRow: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable { case disk, folder, objectStore }

    let id: String
    let kind: Kind
    /// A folder's path or an object store's bucket address, as the server gives it.
    let locator: String
    /// Why the server can't use it now, in its words.
    let error: String?
}

/// Where the server keeps files, and what nothing uses.
nonisolated struct FileStores: Hashable, Sendable {
    var stores: [FileStoreRow]
    /// What the files take on the server's disk.
    var fileBytes: Int?
    var orphanCount: Int
    var orphanBytes: Int
    /// The oldest time the server found a file that nothing uses.
    var firstFound: Date?
    /// Whether the count is all of them, rather than the first pages.
    var orphansComplete: Bool
}

/// The server's source filter: for the types it names, every app and key reads only items from the sources it names.
/// The other two levers are carried unchanged, since a write replaces all three.
nonisolated struct SourceLimit: Hashable, Sendable {
    var instanceID: String?
    var isOn: Bool
    var types: [String]
    var sources: [String]
    var strictTypes: [String]?
    var allowlist: (types: [String], sources: [String])?

    static func == (lhs: SourceLimit, rhs: SourceLimit) -> Bool {
        lhs.instanceID == rhs.instanceID && lhs.isOn == rhs.isOn && lhs.types == rhs.types && lhs.sources == rhs.sources
            && lhs.strictTypes == rhs.strictTypes && lhs.allowlist?.types == rhs.allowlist?.types
            && lhs.allowlist?.sources == rhs.allowlist?.sources
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(instanceID)
        hasher.combine(isOn)
        hasher.combine(types)
        hasher.combine(sources)
    }
}
