import Foundation

/// How full the disk is, as the usage bar draws it. Free space and the disk size stay nil when the server omits them.
/// Neither is derived from the other.
nonisolated enum StorageBar {
    enum Kind: Hashable, Sendable {
        case pictures, pdfs, audioAndVideo, other, database, writeAheadLog

        /// The file kinds, in the order the bar draws them.
        static let files: [Kind] = [.pictures, .pdfs, .audioAndVideo, .other]

        var title: String {
            switch self {
            case .pictures: String(localized: "Pictures")
            case .pdfs: String(localized: "PDFs")
            case .audioAndVideo: String(localized: "Audio and video")
            case .other: String(localized: "Other files")
            case .database: String(localized: "Database")
            case .writeAheadLog: String(localized: "Write-ahead log")
            }
        }
    }

    struct Reading: Hashable, Sendable {
        struct Part: Hashable, Sendable {
            var kind: Kind
            var bytes: Int64
        }

        var parts: [Part]
        var freeBytes: Int64?
        var diskSizeBytes: Int64?
        var usedBytes: Int64

        /// The spoken total: the disk size the server reported, never used plus free.
        var totalBytes: Int64? { diskSizeBytes }
    }

    /// The write-ahead log is part of the database when both were read. A missing half is left out, not counted as zero.
    static func reading(from source: StorageUsageReading) -> Reading {
        var parts = source.kinds.map { Reading.Part(kind: $0.kind, bytes: shown($0.bytes)) }
        if let database = databasePart(database: source.databaseBytes, log: source.writeAheadLogBytes) {
            parts.append(database)
        }
        return Reading(
            parts: parts, freeBytes: source.freeBytes.map(shown), diskSizeBytes: source.diskSizeBytes.map(shown),
            usedBytes: parts.reduce(0) { saturatingAdd($0, $1.bytes) })
    }

    private static func databasePart(database: Int64?, log: Int64?) -> Reading.Part? {
        switch (database, log) {
        case let (database?, log?): .init(kind: .database, bytes: saturatingAdd(shown(database), shown(log)))
        case let (database?, nil): .init(kind: .database, bytes: shown(database))
        case let (nil, log?): .init(kind: .writeAheadLog, bytes: shown(log))
        case (nil, nil): nil
        }
    }

    private static func shown(_ bytes: Int64) -> Int64 { max(0, bytes) }

    private static func saturatingAdd(_ left: Int64, _ right: Int64) -> Int64 {
        let (sum, overflow) = left.addingReportingOverflow(right)
        return overflow ? .max : sum
    }
}

/// What the storage call answered, before the bar decides what to draw.
nonisolated struct StorageUsageReading: Hashable, Sendable {
    struct KindUsage: Hashable, Sendable {
        var kind: StorageBar.Kind
        var bytes: Int64
    }

    var kinds: [KindUsage]
    var databaseBytes: Int64?
    var writeAheadLogBytes: Int64?
    var freeBytes: Int64?
    var diskSizeBytes: Int64?

    /// A new Marfa: every figure was read, and each is zero.
    static let empty = StorageUsageReading(
        kinds: StorageBar.Kind.files.map { .init(kind: $0, bytes: 0) },
        databaseBytes: 0, writeAheadLogBytes: 0, freeBytes: 0, diskSizeBytes: 0)
}
