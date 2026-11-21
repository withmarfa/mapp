import Foundation
import Marfa
import MarfaAPI

// What the Folders page asks of the server: the folders it lists and what each copy of a folder reports. A folder's
// settings and its files are read and changed by the command line and the package's working copy, which this app does not
// use for folders.

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
