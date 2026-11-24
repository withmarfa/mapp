import Foundation
import Marfa
import MarfaAPI

// What the Folders page asks of the server: the folders it lists and what each copy of a folder reports, through the
// client. A folder's settings are read and changed through the working copy (`FolderCalls`), which owns the folder doors.

/// A synced folder, as the server lists it.
nonisolated struct OwnerFolder: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
}

/// The folders the overview lists, which it cuts at a limit, and how many the server holds.
nonisolated struct FolderListing: Hashable, Sendable {
    var folders: [OwnerFolder]
    var total: Int
}

/// One problem a copy reports, by the code the server stores.
nonisolated struct FolderProblem: Hashable, Sendable {
    enum Code: String, Hashable, Sendable, CaseIterable {
        case conflict, refused
        case credentialRefused = "credential_refused"
        case unreadable
        case heldFile = "held_file"
        case unavailable
        case rootGone = "root_gone"
        case settingsInvalid = "settings_invalid"
        case unwatched, paused
    }

    var code: Code
    var count: Int
}

/// What one copy of a folder last reported. It holds no file names, paths or item ids: the server keeps none.
nonisolated struct FolderCopy: Identifiable, Hashable, Sendable {
    /// The copy's own id, which tells two copies of one sign-in apart.
    let id: String
    /// The key or app that keeps the copy, which is how a copy is named.
    var signIn: String
    var pendingUploads: Int
    var pendingDownloads: Int
    var pausedRemovals: Int
    var firstSyncWaiting: Bool
    var problems: [FolderProblem]
    /// How long ago the server received the report, in seconds.
    var ageSeconds: Int
}

/// What a folder's copies report, from the sign-ins that still stand.
nonisolated struct FolderReport: Hashable, Sendable {
    var copies: [FolderCopy]

    var pausedRemovals: Int { copies.reduce(0) { $0 + $1.pausedRemovals } }
    var pendingUploads: Int { copies.reduce(0) { $0 + $1.pendingUploads } }
    var pendingDownloads: Int { copies.reduce(0) { $0 + $1.pendingDownloads } }
}

extension ClientOwnerCalls {
    func folders() async throws(OwnerFailure) -> FolderListing {
        try await run { client in
            let overview = try await client.getOverview().ok.body.json
            let folders = (overview.folders ?? []).map { OwnerFolder(id: $0.id, title: $0.title) }
            return FolderListing(folders: folders, total: max(folders.count, overview.truncated?.additionalProperties["folders"] ?? 0))
        }
    }

    func folderReport(_ id: String) async throws(OwnerFailure) -> FolderReport {
        try await run { client in
            let status = try await client.getFolderStatus(path: .init(id: id)).ok.body.json
            let copies = status.signIns.filter(\.current).flatMap { group in
                group.copies.map { copy in
                    FolderCopy(
                        id: copy.folderStoreId, signIn: group.signIn.name, pendingUploads: copy.pendingUploads,
                        pendingDownloads: copy.pendingDownloads, pausedRemovals: copy.pausedRemovals,
                        firstSyncWaiting: copy.firstSyncWaiting,
                        problems: copy.problems.compactMap { problem in
                            FolderProblem.Code(rawValue: problem.code.rawValue).map { FolderProblem(code: $0, count: problem.count) }
                        },
                        ageSeconds: copy.ageSeconds)
                }
            }
            return FolderReport(copies: copies)
        }
    }
}

/// A folder's settings as the server last answered them, with the version a change is based on.
nonisolated struct FolderSettingsReading: Hashable, Sendable {
    let id: String
    let version: Int64
    /// A stopped folder changes no more, and no copy can follow it again.
    var isStopped: Bool
    var title: String
    /// The types the folder holds, including subtypes. An empty list holds all nonhidden types.
    var types: [String]
    /// Nil holds the library.
    var tier: SliceTier?
    /// Whether the query also narrows by a filter, by state or to what is beneath an item.
    var isNarrowed: Bool
    /// The type a new file takes, where the folder names one.
    var newFileType: String?
    var include: [String]
    var ignore: [String]
    var removalThreshold: RemovalThreshold
    var additionThreshold: AdditionThreshold

    /// The removal file-count threshold, independent of the fraction and ceiling.
    var removalLimit: UInt64 { removalThreshold.files ?? 10 }
    /// The addition file-count threshold, independent of the fraction.
    var additionLimit: UInt64 { additionThreshold.files ?? 50 }
}

/// One setting changed from the Folders page, sent whole.
nonisolated enum FolderSettingChange: Hashable, Sendable {
    case title(String)
    case include([String])
    case ignore([String])
    case removalThreshold(RemovalThreshold)
    case additionThreshold(AdditionThreshold)
}

/// What the Folders page asks of the working copy, which sends a folder's writes at once and never queues them. The host
/// supplies it, since the copy is the app's.
nonisolated protocol FolderCalls: Sendable {
    /// Reads the folder from the server and keeps it in the copy, which then follows it and checks a change against it.
    func settings(of id: String) async throws(OwnerFailure) -> FolderSettingsReading
    /// Replaces one setting, based on `baseVersion`. A change to the same setting since is a `conflict`, and nothing is
    /// written over.
    func change(_ id: String, _ change: FolderSettingChange, baseVersion: Int64) async throws(OwnerFailure) -> FolderSettingsReading
    /// Stops the folder everywhere, for good, and lets the copy stop holding it.
    func stopSyncing(_ id: String) async throws(OwnerFailure)
}

nonisolated extension FolderSettingsReading {
    init(_ folder: Folder) {
        let settings = folder.settings
        let query = settings.query
        self.init(
            id: folder.id, version: folder.version, isStopped: folder.state == .revoked,
            title: settings.title ?? "", types: query.types, tier: query.tier,
            isNarrowed: query.filter != nil || query.beneath != nil || query.states != nil,
            newFileType: settings.defaults.type, include: settings.include, ignore: settings.ignore,
            removalThreshold: settings.removalThreshold, additionThreshold: settings.additionThreshold)
    }
}

nonisolated extension FolderSettingChange {
    var change: FolderSettingsChange {
        switch self {
        case .title(let title): FolderSettingsChange(title: title)
        case .include(let patterns): FolderSettingsChange(include: patterns)
        case .ignore(let patterns): FolderSettingsChange(ignore: patterns)
        case .removalThreshold(let threshold): FolderSettingsChange(removalThreshold: threshold)
        case .additionThreshold(let threshold): FolderSettingsChange(additionThreshold: threshold)
        }
    }
}
