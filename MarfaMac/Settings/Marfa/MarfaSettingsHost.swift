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

/// A deleted item as shown in Trash.
struct MarfaDeletedItem: Identifiable, Hashable {
    let id: String
    let title: String
    let deleted: Date?
    /// The item's type, as the server names it.
    let kind: String
    /// The name of the source that wrote it, where it has one.
    let source: String?
    var typeID: String? = nil
    var canWrite = true
}

/// A source as the Sources page lists it: the code items carry, the name and mark the server gives it, and how many items it wrote.
struct MarfaSourceRow: Identifiable, Hashable {
    let code: String
    let name: String
    /// An icon ID such as `simple-icons:readwise`, drawn by the host.
    let mark: String?
    /// Nil until the server has counted.
    let count: Int?
    /// Where the name comes from: set on the source itself, the app that writes under it, its key's label, or its code.
    let nameOrigin: Marfa.ItemSource.NameOrigin

    var id: String { code }

    /// Whether the name was set on the source itself, so it can be taken back to the one its app or key gives.
    var hasChosenName: Bool { nameOrigin == .set }
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

/// What the app lends the Marfa's pages: the one way they reach the app that holds them, so another app could take them
/// without the app. The pages reach nothing of the app's model or views beyond this protocol and the parts.
@MainActor protocol MarfaSettingsHost: AnyObject, Observable {
    /// The server's own name, or its host until one is read.
    var serverName: String { get }
    /// The server's address as entered, or nil where none is set.
    var serverAddress: String? { get }
    var connection: MarfaSettingsConnection { get }
    /// The permissions the sign-in holds (`Credential.grants`).
    var grants: Set<InstancePermission> { get }
    /// Whether the sign-in lacks something the app asks for at sign-in (`SystemSignIns.lacksAsked`): an owner permission,
    /// or a scope the app began to ask for after the sign-in was made. Connection offers Allow More while it does.
    var lacksAsked: Bool { get }
    /// Whether the sign-in holds `scope`, one the app asks for beyond the owner's permissions.
    func holds(_ scope: String) -> Bool

    /// Signs in again with the full request. The new sign-in holds what the owner approves.
    /// Returns `.allowed` when the new sign-in holds every permission in `permissions`.
    func allowMore(_ permissions: Set<InstancePermission>) async -> MarfaAllowMoreOutcome
    /// Reads what the sign-in holds again, where the server refused for want of a permission the app thought it held.
    func refreshGrants() async
    /// What the owner's pages (Account, Apps, Keys, Network) ask of the server.
    var ownerCalls: any OwnerCalls { get }
    /// What the pages read and change through the instance API.
    var instanceCalls: any InstanceCalls { get }
    /// What Folders asks of the open working copy, which reads, changes and stops a folder.
    var folderCalls: any FolderCalls { get }
    /// Whether an Allow More… is waiting on the owner.
    var isAllowingMore: Bool { get }
    /// Asks the server again, for a server that did not answer.
    func tryAgain()
    /// Opens Connection, the way back from a page that cannot show itself.
    func showConnection()
    /// Starts the app’s usual sign-out flow, including any changes waiting to be sent.
    func requestSignOut()
    var isSignInBusy: Bool { get }
    /// The package's client over the current server, which a page's own calls go through.
    func client() throws -> Client
    /// What opens something in the app, such as Show in the app; nil where the app has no such place.
    var openInApp: ((String) -> Void)? { get }
    /// The `app.<vendor>` namespace the app keeps its own synced settings in, which the Apps page never removes the data of;
    /// nil where the app keeps none.
    var ownAppVendor: String? { get }

    /// The address the system's web authentication sheet ends on, which the app registered for its sign-ins: where a
    /// connector's vendor sign-in sends the browser back to.
    var webSignInReturn: String { get }
    /// Shows `address` in the system's web authentication sheet, over the window in front. Answers whether the browser came back
    /// to `webSignInReturn`, and false where the sheet was closed first.
    func showWebSignIn(at address: URL) async -> Bool
    /// What the Plugins page asks of the server and of the plugins release.
    var pluginCalls: any PluginCalls { get }
    /// Asks the owner for a plugin bundle file, and reads it. Nil where the owner chose none.
    func chooseBundleFile() async -> PluginFileChoice?

    /// The shared model for edits to the server’s settings.
    var instanceSettings: InstanceSettingsModel { get }
    /// The open owner's pages that hold something typed and not kept, which the app asks when Settings closes.
    var ownerDrafts: OwnerDrafts { get }

    /// Shares Account’s problems with the sidebar and its server readings with Connection.
    var overview: AccountOverview { get }
    /// The one reader of the server's health, which Backups and Housekeeping share.
    var health: ServerHealthModel { get }
    /// The one model of the server's updates, which follows an update across page changes.
    var updates: UpdatesModel { get }
    /// Opens another of the Marfa's pages in this window, at one of its own pages where `subpage` names it.
    func show(_ page: MarfaSettingsPage, subpage: SettingsSubpage?)

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

    /// What the Types page asks of the server.
    var typeCalls: any TypeCalls { get }
    /// The type's mark in its tone, at the size of a head card's tile.
    func largeTypeMark(for id: String) -> AnyView
    /// How many items the type holds itself, never those of its subtypes, as the library counts them.
    func itemCount(ofType id: String) -> Int
    /// The type's plural as the working copy reads it, where it has one.
    func typePlural(of id: String) -> String?
    /// The icon the type shows now, an icon ID, or nil where it has none.
    func typeIcon(of id: String) -> String?
    /// Sets the type's icon, or with nil takes the owner's away, for every app. Answers why the server refused, or nil once it took it.
    func changeTypeIcon(_ icon: String?, ofType id: String) async -> OwnerFailure?

    var canReadTrash: Bool { get }
    /// Items shown in Trash.
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

extension MarfaSettingsHost {
    var isSignInBusy: Bool { false }
    func show(_ page: MarfaSettingsPage) { show(page, subpage: nil) }
}

/// A page of the Marfa's half of Settings, with the owner permission it needs to open.
nonisolated enum MarfaSettingsPage: String, CaseIterable, Hashable, Sendable {
    case account, passkeys, browsers, apps, keys, network, plugins, types, sources, trash, fileStorage, connectors, webhooks, folders, backups, housekeeping, activity, monitoring, limits, links

    /// The pages in groups, as the sidebar shows them.
    static let groups: [[MarfaSettingsPage]] = [
        [.account, .activity, .keys, .sources, .webhooks],
        [.types, .plugins, .connectors, .folders, .backups, .trash],
    ]

    var sidebarEntry: MarfaSettingsPage {
        switch self {
        case .passkeys, .browsers, .network, .fileStorage, .housekeeping, .limits, .monitoring: .account
        case .apps: .keys
        case .links: .types
        default: self
        }
    }

    var title: String {
        switch self {
        case .passkeys: String(localized: "Passkeys")
        case .browsers: String(localized: "Browsers")
        case .account: String(localized: "Account")
        case .apps: String(localized: "Apps")
        case .keys: String(localized: "Apps and Keys")
        case .network: String(localized: "Network")
        case .types: String(localized: "Types")
        case .plugins: String(localized: "Plugins")
        case .sources: String(localized: "Sources")
        case .trash: String(localized: "Trash")
        case .fileStorage: String(localized: "Storage")
        case .connectors: String(localized: "Connectors")
        case .webhooks: String(localized: "Webhooks")
        case .folders: String(localized: "Folders")
        case .backups: String(localized: "Backups")
        case .housekeeping: String(localized: "Housekeeping")
        case .activity: String(localized: "Activity")
        case .monitoring: String(localized: "Monitoring")
        case .limits: String(localized: "Limits")
        case .links: String(localized: "Links")
        }
    }

    var symbol: String {
        switch self {
        case .passkeys: "person.badge.key.fill"
        case .browsers: "safari.fill"
        case .account: "person.crop.circle"
        case .apps: "macwindow"
        case .keys: "key.fill"
        case .network: "globe"
        case .types: "shippingbox.fill"
        case .plugins: "puzzlepiece.extension.fill"
        case .sources: "tray.and.arrow.down.fill"
        case .trash: "trash"
        case .fileStorage: "externaldrive.fill"
        case .connectors: "arrow.triangle.2.circlepath"
        case .webhooks: "wave.3.right"
        case .folders: "folder.fill"
        case .backups: "externaldrive.badge.timemachine"
        case .housekeeping: "sparkles"
        case .activity: "chart.bar.fill"
        case .monitoring: "waveform.path.ecg"
        case .limits: "gauge.with.needle"
        case .links: "link"
        }
    }

    var tone: SettingsTokens.Tone {
        switch self {
        case .passkeys: .green
        case .browsers: .blue
        case .account: .indigo
        case .apps: .purple
        case .keys: .amber
        case .network: .blue
        case .types: .orange
        case .plugins: .purple
        case .sources: .green
        case .trash: .gray
        case .fileStorage: .blue
        case .connectors: .green
        case .webhooks: .pink
        case .folders: .blue
        case .backups: .green
        case .housekeeping: .orange
        case .activity: .teal
        case .monitoring: .red
        case .limits: .gray
        case .links: .indigo
        }
    }

    /// The permission the page needs to open, which the owner may not have approved. Account needs none to open, since the
    /// profile needs none: its sign-ins need `sign_ins.manage`, which Change Password asks for where the sign-in lacks it.
    /// Folders needs none: a folder is read as an item, under the access the app holds to every type.
    var permission: InstancePermission? {
        switch self {
        case .housekeeping: .instanceRead
        case .passkeys, .browsers: .signInsManage
        case .backups: .backupsManage
        case .network, .fileStorage, .monitoring, .limits: .configManage
        case .account, .keys: nil
        case .apps: .grantsManage
        case .sources: .keysManage
        case .types, .links: .schemaWrite
        case .plugins: .schemaWrite
        case .trash: nil
        case .connectors: .connectorsManage
        case .webhooks: .webhooksManage
        case .folders: nil
        case .activity: .auditRead
        }
    }

    /// What the app isn't allowed to do on this page without its permission, in the page's own words from what the
    /// permission opens there. Pages that share a permission still say different things, since each opens a different part.
    func missingPermission(in grants: Set<InstancePermission>) -> InstancePermission? {
        if self == .fileStorage || self == .limits || self == .housekeeping, !grants.isDisjoint(with: [.instanceRead, .configManage]) { return nil }
        return permission.flatMap { grants.contains($0) ? nil : $0 }
    }

    var permissionLine: String {
        switch self {
        case .passkeys: String(localized: "The app isn’t allowed to manage your passkeys.")
        case .browsers: String(localized: "The app isn’t allowed to manage your browser sign-ins.")
        case .account: ""
        case .apps: String(localized: "The app isn’t allowed to list, narrow or disconnect apps.")
        case .keys: String(localized: "This sign-in doesn’t have permission to manage all keys.")
        case .types: String(localized: "The app isn’t allowed to change types, their icons, words or fields.")
        case .plugins: String(localized: "The app isn’t allowed to install, update or remove plugins.")
        case .sources: String(localized: "The app isn’t allowed to rename, mark or limit sources.")
        case .network: String(localized: "The app isn’t allowed to see or change the server’s addresses.")
        case .trash: String(localized: "The app isn’t allowed to read deleted items.")
        case .fileStorage: String(localized: "The app isn’t allowed to see or change how the server keeps files.")
        case .connectors: String(localized: "The app isn’t allowed to see, pause, run or set up connectors.")
        case .webhooks: String(localized: "The app isn’t allowed to list, make, change or remove webhooks.")
        case .folders: ""
        case .backups: String(localized: "The app isn’t allowed to see, take or restore backups.")
        case .housekeeping: String(localized: "The app isn’t allowed to read the jobs the server runs by itself.")
        case .activity: String(localized: "The app isn’t allowed to read the server’s audit log.")
        case .monitoring: String(localized: "The app isn’t allowed to see or change how the server is monitored.")
        case .limits: String(localized: "The app isn’t allowed to see or change the server’s limits.")
        case .links: String(localized: "The app isn’t allowed to change link types.")
        }
    }

    /// The titles of the rows the page holds, so the sidebar's search finds the page by them.
    var searchWords: [String] {
        switch self {
        case .passkeys: [String(localized: "Add Passkey"), String(localized: "Rename")]
        case .browsers: [String(localized: "Sign Out")]
        case .account:
            [
                String(localized: "Username"), String(localized: "Email"), String(localized: "Password"),
                String(localized: "Change Password"), String(localized: "Passkeys"), String(localized: "Browsers"),
                String(localized: "Check for Updates"), String(localized: "Check automatically"), String(localized: "Profile"),
                String(localized: "Problems"), String(localized: "Sign Out"), String(localized: "Name"),
            ]
        case .apps:
            [
                String(localized: "Disconnect"), String(localized: "Access"), String(localized: "Narrow"),
            ]
        case .keys:
            [String(localized: "Your Keys"), String(localized: "New Key"), String(localized: "Revoke"), String(localized: "Expires"), String(localized: "Source")]
        case .network:
            [
                String(localized: "Sign-In Address"), String(localized: "Other Addresses"), String(localized: "Websites"),
                String(localized: "Add an Address"), String(localized: "Add a Website"),
            ]
        case .types:
            [
                String(localized: "All"), String(localized: "Yours"), String(localized: "From Plugins"), String(localized: "From Apps"),
                String(localized: "Built In"), String(localized: "New Type"), String(localized: "Links Between Items"), String(localized: "Links"),
                String(localized: "New Child Type"), String(localized: "Statuses"), String(localized: "Guidance"), String(localized: "Icon"),
                String(localized: "Based On"), String(localized: "Plural"), String(localized: "Description"),
            ]
        case .plugins:
            [
                String(localized: "Installed"), String(localized: "Updates"), String(localized: "Plugin Updates"), String(localized: "Available"),
                String(localized: "Install"), String(localized: "Install from a File"), String(localized: "Update"), String(localized: "Remove"),
                String(localized: "Connector"),
            ]
        case .sources:
            [String(localized: "Rename"), String(localized: "Change Mark"), String(localized: "Limit Sources"), String(localized: "Rules for Every App and Key")]
        case .trash:
            [
                String(localized: "Deleted Items"), String(localized: "Restore"), String(localized: "Permanently Delete"),
                String(localized: "Empty Trash"), String(localized: "Recently Deleted"),
            ]
        case .fileStorage:
            [String(localized: "Files"), String(localized: "Reading Files"), String(localized: "Files from the Web"), String(localized: "Trash")]
                + (InstanceSetting.fileSettings + InstanceSetting.versionSettings + [.trashRetentionDays]).map(\.title)
                + LimitSetting.storageFields.map(\.title) + [String(localized: "Versions")]
        case .connectors:
            [
                String(localized: "Pause"), String(localized: "Run Now"), String(localized: "Runs On"), String(localized: "Settings"),
                String(localized: "What It Brings"), String(localized: "Sign In"), String(localized: "Status"), String(localized: "Needs Attention"),
            ]
        case .webhooks:
            [
                String(localized: "New Webhook"), String(localized: "Events"), String(localized: "Deliveries"), String(localized: "Redeliver"),
                String(localized: "Signing Secret"), String(localized: "Sending"),
            ]
        case .folders:
            [
                String(localized: "Folders"),
                String(localized: "Copies"), String(localized: "Needs Attention"), String(localized: "Synced Folders"), String(localized: "Rename"),
                String(localized: "Ignore"), String(localized: "Include"), String(localized: "Safety"), String(localized: "Pause Removals Over"),
                String(localized: "Pause Additions Over"), String(localized: "Stop Syncing"),
            ]
        case .backups:
            [
                String(localized: "Keep Backups In"), String(localized: "Back Up Every"), String(localized: "Last Backup"), String(localized: "Back Up Now"),
                String(localized: "Restore"), String(localized: "Folder"),
            ]
        case .housekeeping:
            [String(localized: "Jobs"), String(localized: "Clean-up"), String(localized: "Confirm Date"), String(localized: "Clock"), String(localized: "Keep Records For")] + InstanceSetting.logSettings.map(\.title)
        case .activity:
            [String(localized: "Audit Log"), String(localized: "Who Did What")]
        case .monitoring:
            [
                String(localized: "Heartbeat"), String(localized: "Error Reports"), String(localized: "Telemetry"), String(localized: "Error reports address"),
                String(localized: "Project token"), String(localized: "Report errors"),
            ]
        case .limits:
            LimitSetting.limitFields.map(\.title) + [String(localized: "Rate Limits"), String(localized: "Limit requests"), String(localized: "Requests"), String(localized: "Start-Up"), String(localized: "Set Where It Runs")]
        case .links:
            [String(localized: "Links Between Items"), String(localized: "New Link Type")]
        }
    }
}
