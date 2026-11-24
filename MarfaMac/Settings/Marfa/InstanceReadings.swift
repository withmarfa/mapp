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

/// The version and sizes returned by the server's metrics endpoint.
nonisolated struct InstanceMetricsReading: Hashable, Sendable {
    var version: String
    var databaseBytes: Int?
    var fileBytes: Int
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
    var orphanCount: Int
    var orphanBytes: Int
    /// The oldest time the server found a file that nothing uses.
    var firstFound: Date?
    /// Whether the count is all of them, rather than the first pages.
    var orphansComplete: Bool
}

/// The instance's three enforcement levers as `/config` holds them, with the instance they were read from. A write
/// replaces all three, so a lever is changed only through `EnforcementSettings`, which sends the other two as just read.
nonisolated struct Enforcement: Hashable, Sendable {
    /// Types and the sources that hold for them.
    struct Lever: Hashable, Sendable {
        var types: [String]
        var sources: [String]
    }

    var instanceID: String?
    /// The types strict mode names; nil while it is off.
    var strictTypes: [String]?
    /// Which sources may write the types it names; nil while it is off.
    var allowlist: Lever?
    /// The source filter: for the types it names, every app and key reads only items from the sources it names.
    var filter: Lever?
}
