import Foundation
import Marfa
import MarfaAPI

/// How the connection stands, in the terms a Marfa page needs: whether it can show itself, and what to say if not.
enum MarfaSettingsConnection: Equatable {
    /// The copy is opening, or what the sign-in holds is being read.
    case opening
    case connected
    /// No server is set, or its copy is not open.
    case notConnected
    /// The server ended the sign-in.
    case signedOut
    /// The server is set but does not answer; `lastAnswered` is when it last did.
    case notAnswering(lastAnswered: Date?)
}

/// What came of Allow More…, for the page that asked. Only `allowed` changes what the page shows; every other outcome
/// leaves things as they were.
enum MarfaAllowMoreOutcome: Equatable {
    case allowed
    case cancelled
    /// The owner approved fewer permissions than the page needs.
    case approvedFewer
    case failed
}

/// A deleted item, as the Recently Deleted page lists it.
struct MarfaDeletedItem: Identifiable, Hashable {
    let id: String
    let title: String
    let deleted: Date?
}

/// What MAPP lends the Marfa's pages: the one way they reach the app that holds them, so another app could take them
/// without MAPP. The pages reach nothing of MAPP's model or views beyond this protocol and the parts.
@MainActor protocol MarfaSettingsHost: AnyObject, Observable {
    /// The server's own name, or its host until one is read.
    var serverName: String { get }
    /// The server's address as entered, or nil where none is set.
    var serverAddress: String? { get }
    var connection: MarfaSettingsConnection { get }
    /// The permissions the sign-in holds (`Credential.grants`).
    var grants: Set<InstancePermission> { get }

    /// Signs in again, asking for the permissions already held and `permissions`. Cancelled, or approved with fewer than
    /// asked, nothing is added; an approval that drops a permission held before is told to the owner.
    func allowMore(_ permissions: Set<InstancePermission>) async -> MarfaAllowMoreOutcome
    /// Whether an Allow More… is waiting on the owner.
    var isAllowingMore: Bool { get }
    /// Asks the server again, for a server that did not answer.
    func tryAgain()
    /// Opens Connection, the way back from a page that cannot show itself.
    func showConnection()
    /// The package's client over the current server, which a page's own calls go through.
    func client() throws -> Client
    /// What opens something in MAPP, such as Show in MAPP; nil where the app has no such place.
    var openInApp: ((String) -> Void)? { get }

    /// The server's own settings, drafted on This Marfa's fields.
    var instanceSettings: InstanceSettingsModel { get }

    /// Recently Deleted.
    var deletedItems: [MarfaDeletedItem] { get }
    var deletedCount: Int { get }
    /// How many days the server keeps deleted items, where it is known and limited.
    var deletedRetentionDays: Int? { get }
    var canDeletePermanently: Bool { get }
    func restoreDeleted(_ ids: Set<String>)
    /// Asks to confirm, then permanently deletes.
    func deleteDeletedPermanently(_ ids: Set<String>)
    func emptyDeleted()
}

/// A page of the Marfa's half of Settings, with the owner permission it needs to open.
nonisolated enum MarfaSettingsPage: String, CaseIterable, Hashable, Sendable {
    case overview, recentlyDeleted

    /// The pages in groups, as the sidebar shows them.
    static let groups: [[MarfaSettingsPage]] = [[.overview], [.recentlyDeleted]]

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .recentlyDeleted: String(localized: "Recently Deleted")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "server.rack"
        case .recentlyDeleted: "trash"
        }
    }

    var tone: SettingsTokens.Tone {
        switch self {
        case .overview: .blue
        case .recentlyDeleted: .gray
        }
    }

    /// The permission the page needs, which the owner may not have approved.
    var permission: InstancePermission {
        switch self {
        case .overview: .configManage
        case .recentlyDeleted: .itemsPurge
        }
    }

    /// What MAPP isn't allowed to do without it, as the page says it.
    var permissionLine: String {
        switch self {
        case .overview: String(localized: "MAPP isn’t allowed to see and change this Marfa’s settings.")
        case .recentlyDeleted: String(localized: "MAPP isn’t allowed to list and permanently delete deleted items.")
        }
    }

    /// The titles of the rows the page holds, so the sidebar's search finds the page by them.
    var searchWords: [String] {
        switch self {
        case .overview:
            InstanceSetting.allCases.map(\.title) + [String(localized: "Version History"), String(localized: "This Marfa")]
        case .recentlyDeleted:
            [String(localized: "Deleted Items"), String(localized: "Restore"), String(localized: "Delete Permanently"), String(localized: "Empty Recently Deleted")]
        }
    }
}
