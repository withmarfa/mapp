import AppKit
import Foundation
import Marfa
import MarfaAPI

/// The name of the library in use: the name a server gave itself, or its host until one has been read.
@MainActor
enum LibraryDescription {
    static func name(_ libraries: Libraries) -> String {
        guard let connection = libraries.host.configuredConnection else { return String(localized: "Marfa") }
        if let name = libraries.host.instanceName(for: connection) { return name }
        return connection.address.host() ?? connection.address.absoluteString
    }
}

/// What MAPP lends the Marfa's pages (`MarfaSettingsHost`): its host, its sign-in and its library, told in the pages' own
/// terms. It is the only place the Marfa's half meets MAPP.
@Observable @MainActor final class MAPPMarfaSettingsHost: MarfaSettingsHost {
    private let libraries: Libraries
    private let launcher: SettingsLauncher
    private(set) var isAllowingMore = false
    let instanceSettings: InstanceSettingsModel
    var ownerDrafts: OwnerDrafts { libraries.ownerDrafts }

    /// `instanceSettings` is the model the app keeps for This Marfa's fields, unless a test brings its own.
    init(libraries: Libraries, launcher: SettingsLauncher, instanceSettings: InstanceSettingsModel? = nil) {
        self.libraries = libraries
        self.launcher = launcher
        self.instanceSettings = instanceSettings ?? libraries.instanceSettings
    }

    private var host: MarfaHost { libraries.host }

    var serverName: String { LibraryDescription.name(libraries) }
    var serverAddress: String? { host.configuredConnection?.address.absoluteString }

    var connection: MarfaSettingsConnection {
        switch host.state {
        case .disconnected, .unavailable, .otherVersion, .inUse:
            return .notConnected
        case .keyRefused:
            return .signedOut
        case .offline:
            return .notAnswering(lastAnswered: host.lastSynced)
        case .connecting, .online:
            return host.grantsRead ? .connected : .opening
        }
    }

    var grants: Set<InstancePermission> { host.grants }

    func allowMore(_ permissions: Set<InstancePermission>) async -> MarfaAllowMoreOutcome {
        guard !isAllowingMore, host.connection != nil else { return .failed }
        isAllowingMore = true
        defer { isAllowingMore = false }
        let model = libraries.marfaSettings
        await model.start(.signInAgain(usingCode: false, permissions: host.grants.union(permissions))).value
        switch model.lastEnding {
        case .completed?:
            await host.refreshGrants()
            return permissions.isSubset(of: host.grants) ? .allowed : .approvedFewer
        case .canceled?:
            return .cancelled
        case .failed?, nil:
            return .failed
        }
    }

    func tryAgain() { host.refresh() }

    func showConnection() { launcher.show(.connection) }

    func client() throws -> Client {
        guard let connection = host.configuredConnection else { throw MarfaServerCalls.Ending.keyRefused }
        return try MarfaServerCalls(connection: connection, signIns: host.signIns).client()
    }

    func refreshGrants() async { await host.refreshGrants() }

    /// The owner's calls, made through a client that shows the system's sign-in in place where the server asks the owner to
    /// confirm it is them, and sends the call again once they have.
    var ownerCalls: any OwnerCalls {
        guard let connection = host.configuredConnection else {
            return ClientOwnerCalls { throw MarfaError.signedOut(origin: "", message: "no server is set") }
        }
        let signIns = host.signIns
        return ClientOwnerCalls {
            do {
                let calls = MarfaServerCalls(connection: connection, signIns: signIns)
                let server = try calls.server().confirming(from: { NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow() })
                return Client(server, timeout: calls.timeout)
            } catch let ending as MarfaServerCalls.Ending {
                switch ending {
                case .keyRefused: throw MarfaError.signedOut(origin: connection.address.absoluteString, message: "the sign-in ended")
                default: throw MarfaError.invalid(message: Words.signInUnreadable)
                }
            }
        }
    }

    var openInApp: ((String) -> Void)? { nil }

    // MARK: Recently Deleted

    var deletedItems: [MarfaDeletedItem] {
        libraries.current?.deletedItems.map { MarfaDeletedItem(id: $0.id.rawValue, title: $0.displayTitle, deleted: $0.modified) } ?? []
    }

    var deletedCount: Int { libraries.current?.deletedCount ?? 0 }
    var deletedRetentionDays: Int? { libraries.current?.trashDays }
    var canDeletePermanently: Bool { libraries.current?.reachesServer ?? false }

    func restoreDeleted(_ ids: Set<String>) {
        libraries.current?.recover(Set(ids.map { ItemID($0) }), undoManager: nil)
    }

    func deleteDeletedPermanently(_ ids: Set<String>) {
        libraries.current?.itemsToPurge = Set(ids.map { ItemID($0) })
    }

    func emptyDeleted() {
        guard let library = libraries.current else { return }
        library.itemsToPurge = Set(library.deletedItems.map(\.id))
    }

    // MARK: Closing

    /// Hands over what was typed in the Marfa's pages and not saved, as MAPP's rules say for a panel that ends any way but
    /// the person's own Cancel: the text goes through `Notices.notKept`, to the clipboard, and the draft is dropped.
    func handOverDrafts() {
        instanceSettings.handOver(
            to: libraries.host.notices, because: String(localized: "You closed Settings before saving the changes to this Marfa’s settings."))
        ownerDrafts.handOver(to: libraries.host.notices, because: String(localized: "You closed Settings before this was saved."))
    }
}

extension OwnerDrafts {
    /// Gives back what the open owner's pages hold: typed text as a change not kept, and what can't be shown again as a
    /// notice that holds the quit. A password is never among it, and nor is a key's secret.
    func handOver(to notices: Notices, because reason: String) {
        for draft in takeAll() { deliver(draft, to: notices, because: reason) }
    }

    /// One draft as a notice. What can't be shown again is a change not kept with no text, which the quit waits to tell.
    func deliver(_ draft: OwnerDraft, to notices: Notices, because reason: String) {
        switch draft {
        case .typed(let title, let text): notices.notKept(title, text: text, reason: reason)
        case .told(let title, let message): notices.notKept(title, text: nil, reason: message, standsAlone: true)
        }
    }
}

extension InstanceSettingsModel {
    /// Tells the person what they typed and did not save, as a change not kept, and drops it. Nothing typed hands over nothing.
    func handOver(to notices: Notices, because reason: String) {
        guard hasEdits else { return }
        let lines = InstanceSetting.allCases.filter(isEdited).map { "\($0.title): \(draft[$0] ?? "")" }
        notices.notKept(String(localized: "Settings Not Saved"), text: lines.joined(separator: "\n"), reason: reason)
        revert()
    }
}
