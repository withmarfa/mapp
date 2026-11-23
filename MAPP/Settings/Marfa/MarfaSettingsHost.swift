import Foundation
import Marfa
import MarfaAPI
import SwiftUI

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
    /// The item's type, as the server names it.
    let kind: String
    /// The name of the source that wrote it, where it has one.
    let source: String?
}

/// A source as the Sources page lists it: the code items carry, the name and mark the server gives it, and how many items it wrote.
struct MarfaSourceRow: Identifiable, Hashable {
    let code: String
    let name: String
    /// An icon ID such as `simple-icons:readwise`, drawn by the host.
    let mark: String?
    /// Nil until the server has counted.
    let count: Int?
    /// Whether the name was set on the source itself, so it can be taken back to the one its app or key gives.
    let hasChosenName: Bool

    var id: String { code }
}

/// One change to a source, for every app that reads it.
enum MarfaSourceChange: Hashable {
    case rename(String)
    case useDefaultName
    case setMark(String)
    case removeMark
}

/// A set of marks the owner may choose from, such as the icons of one library.
struct MarfaMarkSet: Identifiable, Hashable {
    let id: String
    let title: String
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
    /// Reads what the sign-in holds again, where the server refused for want of a permission MAPP thought it held.
    func refreshGrants() async
    /// What the owner's pages (Account, Apps, Keys, Addresses) ask of the server.
    var ownerCalls: any OwnerCalls { get }
    /// What Activity, Monitoring, Limits and Start-Up ask of the server.
    var instanceCalls: any InstanceCalls { get }
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
    /// The `app.<vendor>` namespace the app keeps its own synced settings in, which the Apps page never removes the data of;
    /// nil where the app keeps none.
    var ownAppVendor: String? { get }

    /// The server's own settings, drafted on This Marfa's fields.
    var instanceSettings: InstanceSettingsModel { get }
    /// The open owner's pages that hold something typed and not kept, which the app asks when Settings closes.
    var ownerDrafts: OwnerDrafts { get }

    /// Where the Overview's Needs Attention and Health are read, kept by the app so the sidebar's badge is its count.
    var overview: OverviewModel { get }
    /// The one reader of the server's health, which Overview, Backups and Housekeeping all read.
    var health: ServerHealthModel { get }
    /// Opens another of the Marfa's pages in this window.
    func show(_ page: MarfaSettingsPage)

    /// Sources, as the server last named and counted them (the last answer, while it cannot be reached).
    var sources: [MarfaSourceRow] { get }
    func refreshSources() async
    /// Whether a name or mark can be changed now: with a server to keep it.
    var canChangeSources: Bool { get }
    /// Makes one change to a source and answers why the server refused it, or nil once it took it.
    func changeSource(_ code: String, _ change: MarfaSourceChange) async -> OwnerFailure?
    var markSets: [MarfaMarkSet] { get }
    /// The marks in `set` whose names contain every word of `query`, best first; every mark for an empty query.
    func marks(matching query: String, in set: MarfaMarkSet) -> [String]
    func markGlyph(_ id: String) -> AnyView
    /// The mark an access row leads with for `pattern`: the type's own mark in its tone where the pattern names a type, the
    /// neutral mark for any other pattern, at the lead column's size.
    func typeMark(for pattern: String) -> AnyView
    func markTitle(_ id: String) -> String

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
    case overview, account, apps, keys, addresses, sources, recentlyDeleted, history, fileStorage, webhooks, folders, backups, updates, housekeeping, activity, monitoring, limits, startUp

    /// The pages in groups, as the sidebar shows them.
    static let groups: [[MarfaSettingsPage]] = [
        [.overview], [.account, .apps, .keys, .addresses], [.sources], [.recentlyDeleted, .history, .fileStorage], [.webhooks, .folders],
        [.backups, .updates, .housekeeping], [.activity, .monitoring], [.limits, .startUp],
    ]

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .account: String(localized: "Account")
        case .apps: String(localized: "Apps")
        case .keys: String(localized: "Keys")
        case .addresses: String(localized: "Addresses")
        case .sources: String(localized: "Sources")
        case .recentlyDeleted: String(localized: "Recently Deleted")
        case .history: String(localized: "History")
        case .fileStorage: String(localized: "File Storage")
        case .webhooks: String(localized: "Webhooks")
        case .folders: String(localized: "Folders")
        case .backups: String(localized: "Backups")
        case .updates: String(localized: "Updates")
        case .housekeeping: String(localized: "Housekeeping")
        case .activity: String(localized: "Activity")
        case .monitoring: String(localized: "Monitoring")
        case .limits: String(localized: "Limits")
        case .startUp: String(localized: "Start-Up")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "server.rack"
        case .account: "person.crop.circle"
        case .apps: "macwindow"
        case .keys: "key.fill"
        case .addresses: "globe"
        case .sources: "tray.and.arrow.down.fill"
        case .recentlyDeleted: "trash"
        case .history: "clock.arrow.circlepath"
        case .fileStorage: "externaldrive.fill"
        case .webhooks: "dot.radiowaves.up.forward"
        case .folders: "folder.fill"
        case .backups: "externaldrive.badge.timemachine"
        case .updates: "arrow.down.circle.fill"
        case .housekeeping: "sparkles"
        case .activity: "list.bullet.rectangle"
        case .monitoring: "waveform.path.ecg"
        case .limits: "gauge.with.needle"
        case .startUp: "power"
        }
    }

    var tone: SettingsTokens.Tone {
        switch self {
        case .overview: .blue
        case .account: .indigo
        case .apps: .purple
        case .keys: .amber
        case .addresses: .teal
        case .sources: .green
        case .recentlyDeleted: .gray
        case .history: .indigo
        case .fileStorage: .blue
        case .webhooks: .pink
        case .folders: .blue
        case .backups: .green
        case .updates: .blue
        case .housekeeping: .orange
        case .activity: .purple
        case .monitoring: .red
        case .limits, .startUp: .gray
        }
    }

    /// The permission the page needs to open, which the owner may not have approved. Account needs none to open: its
    /// sign-ins need `sign_ins.manage`, which it asks for from Change Password and never at sign-in. Folders needs none: a
    /// folder is read as an item, under the access MAPP holds to every type.
    var permission: InstancePermission? {
        switch self {
        case .overview, .updates, .housekeeping: .instanceRead
        case .backups: .backupsManage
        case .addresses, .history, .fileStorage, .monitoring, .limits: .configManage
        case .account: nil
        case .apps: .grantsManage
        case .keys, .sources: .keysManage
        case .recentlyDeleted: .itemsPurge
        case .webhooks: .webhooksManage
        case .folders: nil
        case .activity: .auditRead
        case .startUp: .instanceRead
        }
    }

    /// What MAPP isn't allowed to do on this page without its permission, in the page's own words from what the
    /// permission opens there. Pages that share a permission still say different things, since each opens a different part.
    var permissionLine: String {
        switch self {
        case .overview: String(localized: "MAPP isn’t allowed to read the server’s health and status.")
        case .account: ""
        case .apps: String(localized: "MAPP isn’t allowed to list, narrow or disconnect apps.")
        case .keys: String(localized: "MAPP isn’t allowed to list, make, extend or revoke keys.")
        case .sources: String(localized: "MAPP isn’t allowed to rename, mark or limit sources.")
        case .addresses: String(localized: "MAPP isn’t allowed to see or change the server’s addresses.")
        case .recentlyDeleted: String(localized: "MAPP isn’t allowed to list or permanently delete deleted items.")
        case .history: String(localized: "MAPP isn’t allowed to see or change version and log retention.")
        case .fileStorage: String(localized: "MAPP isn’t allowed to see or change how the server keeps files.")
        case .webhooks: String(localized: "MAPP isn’t allowed to list, make, change or remove webhooks.")
        case .folders: ""
        case .backups: String(localized: "MAPP isn’t allowed to see, take or restore backups.")
        case .updates: String(localized: "MAPP isn’t allowed to read whether a newer Marfa is ready.")
        case .housekeeping: String(localized: "MAPP isn’t allowed to read the jobs the server runs by itself.")
        case .activity: String(localized: "MAPP isn’t allowed to read the server’s audit log.")
        case .monitoring: String(localized: "MAPP isn’t allowed to see or change how the server is monitored.")
        case .limits: String(localized: "MAPP isn’t allowed to see or change the server’s limits.")
        case .startUp: String(localized: "MAPP isn’t allowed to read the settings the server started with.")
        }
    }

    /// The titles of the rows the page holds, so the sidebar's search finds the page by them.
    var searchWords: [String] {
        switch self {
        case .overview:
            [String(localized: "Name"), String(localized: "Needs Attention"), String(localized: "This Marfa"), String(localized: "Health")]
        case .account:
            [
                String(localized: "Username"), String(localized: "Email"), String(localized: "Password"),
                String(localized: "Change Password"), String(localized: "Passkeys"), String(localized: "Browsers"),
            ]
        case .apps:
            [String(localized: "Connected"), String(localized: "Disconnect"), String(localized: "Access"), String(localized: "Narrow")]
        case .keys:
            [String(localized: "New Key"), String(localized: "Revoke"), String(localized: "Expires"), String(localized: "Source")]
        case .addresses:
            [
                String(localized: "Sign-In Address"), String(localized: "Other Addresses"), String(localized: "Websites"),
                String(localized: "Add an Address"), String(localized: "Add a Website"),
            ]
        case .sources:
            [String(localized: "Rename"), String(localized: "Change Mark"), String(localized: "Limit Sources"), String(localized: "Rules for Every App and Key")]
        case .recentlyDeleted:
            [
                String(localized: "Deleted Items"), String(localized: "Restore"), String(localized: "Permanently Delete"),
                String(localized: "Empty Recently Deleted"), InstanceSetting.trashRetentionDays.title,
            ]
        case .history:
            InstanceSetting.versionSettings.map(\.title) + InstanceSetting.logSettings.map(\.title) + [String(localized: "Versions"), String(localized: "Logs")]
        case .fileStorage:
            [String(localized: "Where Files Are"), String(localized: "Reading Files"), String(localized: "Files From the Web"), String(localized: "Unused Files")]
                + InstanceSetting.fileSettings.map(\.title)
        case .webhooks:
            [
                String(localized: "New Webhook"), String(localized: "Events"), String(localized: "Deliveries"), String(localized: "Redeliver"),
                String(localized: "Signing Secret"), String(localized: "Sending"),
            ]
        case .folders:
            [String(localized: "Copies"), String(localized: "Needs Attention"), String(localized: "Synced Folders")]
        case .backups:
            [
                String(localized: "Keep Backups In"), String(localized: "Back Up Every"), String(localized: "Last Backup"), String(localized: "Back Up Now"),
                String(localized: "Restore"), String(localized: "Folder"),
            ]
        case .updates:
            [
                String(localized: "Check for Updates"), String(localized: "Update"), String(localized: "Check Automatically"), String(localized: "Last Update"),
            ]
        case .housekeeping:
            [String(localized: "Jobs"), String(localized: "Clean-up"), String(localized: "Confirm Date"), String(localized: "Clock")]
        case .activity:
            [String(localized: "Audit Log"), String(localized: "Who Did What")]
        case .monitoring:
            [
                String(localized: "Heartbeat"), String(localized: "Error Reports"), String(localized: "Telemetry"), String(localized: "PostHog Host"),
                String(localized: "Project Token"), String(localized: "Report Errors"),
            ]
        case .limits:
            LimitSetting.all.map(\.title) + [String(localized: "Rate Limits"), String(localized: "Limit Requests"), String(localized: "Requests")]
        case .startUp:
            [String(localized: "Environment"), String(localized: "Settings Read When It Starts")]
        }
    }
}
