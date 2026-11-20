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

    /// Hands over what was typed in This Marfa's fields and not saved, as MAPP's rules say for a panel that ends any way but
    /// the person's own Cancel: the text goes through `Notices.notKept`, to the clipboard, and the draft is dropped.
    func handOverDrafts() {
        let model = instanceSettings
        guard model.hasEdits else { return }
        let lines = InstanceSetting.allCases.filter(model.isEdited).map { "\($0.title): \(model.draft[$0] ?? "")" }
        libraries.host.notices.notKept(
            String(localized: "Settings Not Saved"), text: lines.joined(separator: "\n"),
            reason: String(localized: "You closed Settings before saving the changes to this Marfa’s settings."))
        model.revert()
    }
}
