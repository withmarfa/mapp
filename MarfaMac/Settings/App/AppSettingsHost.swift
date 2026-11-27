import AppKit
import Foundation
import Marfa
import MarfaAPI
import SwiftUI
import UniformTypeIdentifiers

/// The name of the library in use: the name a server gave itself, or its host until one has been read.
@MainActor
enum LibraryDescription {
    static func name(_ libraries: Libraries) -> String {
        name(of: libraries.host)
    }

    static func name(of host: MarfaHost) -> String {
        guard let connection = host.configuredConnection else { return String(localized: "Marfa") }
        if let name = host.instanceName(for: connection) { return name }
        return connection.address.host() ?? connection.address.absoluteString
    }
}

/// What the app lends the Marfa's pages (`MarfaSettingsHost`): its host, its sign-in and its library, told in the pages' own
/// terms. It is the only place the Marfa's half meets the app.
@Observable @MainActor final class AppSettingsHost: MarfaSettingsHost {
    private let libraries: Libraries
    private let launcher: SettingsLauncher
    var isAllowingMore: Bool { libraries.marfaSettings.isAllowingMore }
    let instanceSettings: InstanceSettingsModel
    var ownerDrafts: OwnerDrafts { libraries.ownerDrafts }
    /// The main windows open, which `openInApp` shows a place in; without it Settings offers none.
    private let mainWindows: ItemLinkOpener?

    /// `instanceSettings` is the model the app keeps for This Marfa's fields, unless a test brings its own.
    init(
        libraries: Libraries, launcher: SettingsLauncher, instanceSettings: InstanceSettingsModel? = nil, mainWindows: ItemLinkOpener? = nil
    ) {
        self.libraries = libraries
        self.launcher = launcher
        self.instanceSettings = instanceSettings ?? libraries.instanceSettings
        self.mainWindows = mainWindows
    }

    private var host: MarfaHost { libraries.host }

    // MARK: Shared server readings

    private typealias Shared = (address: String?, overview: AccountOverview, health: ServerHealthModel, updates: UpdatesModel)
    @ObservationIgnored private var overviewModels: Shared?

    /// The shared readings belong to one server, because each call is bound to its sign-in.
    var overview: AccountOverview { models.overview }
    var health: ServerHealthModel { models.health }
    var updates: UpdatesModel { models.updates }

    private var models: Shared {
        if let held = overviewModels, held.address == serverAddress { return held }
        overviewModels?.updates.stop()
        let health = ServerHealthModel(context: OwnerContext(host: self))
        let made = (
            serverAddress, AccountOverview(context: OwnerContext(host: self)), health,
            UpdatesModel(context: OwnerContext(host: self))
        )
        overviewModels = made
        return made
    }

    func show(_ page: MarfaSettingsPage, subpage: SettingsSubpage?) { launcher.show(.marfa(page), subpage: subpage) }

    // MARK: Sources

    var sources: [MarfaSourceRow] {
        guard let library = libraries.current else { return [] }
        return library.sources.listing(loaded: [:]).map { listed in
            let info = library.sources.info(listed.code)
            return MarfaSourceRow(code: listed.code, name: listed.name, mark: info.mark, count: listed.count, nameOrigin: info.nameOrigin)
        }
    }

    func refreshSources() async { await libraries.current?.refreshSources() }

    var canChangeSources: Bool { libraries.current?.reachesServer ?? false }

    func changeSource(_ code: String, _ change: MarfaSourceChange) async -> OwnerFailure? {
        guard let library = libraries.current else { return .failed(SourceEditFailure.unsupported.message) }
        let failure: SourceEditFailure? =
            switch change {
            case .rename(let name): await library.updateSource(code, name: .set(name), mark: nil)
            case .useDefaultName: await library.updateSource(code, name: .clear, mark: nil)
            case .setMark(let mark): await library.updateSource(code, name: nil, mark: .set(mark))
            case .removeMark: await library.updateSource(code, name: nil, mark: .clear)
            }
        guard let failure else { return nil }
        return switch failure {
        case .unreachable: .unreachable
        case .notPermitted: .notPermitted(InstancePermission.keysManage.rawValue)
        case .keyRefused: .signedOut
        case .refused(let reason): .refused(reason)
        case .unsupported, .failed: .failed(failure.message)
        }
    }

    var markSets: [MarfaMarkSet] { IconSet.allCases.map { MarfaMarkSet(id: $0.rawValue, title: $0.title) } }

    func marks(matching query: String, in set: MarfaMarkSet) -> [String] {
        guard let iconSet = IconSet(rawValue: set.id) else { return [] }
        return IconNameSearch.matching(query, in: iconSet.ids)
    }

    func markGlyph(_ id: String) -> AnyView {
        AnyView(
            Group {
                if id.isEmpty { Image(systemName: "tray") } else { RowIconImage(icon: .type(id)) }
            }
            .foregroundStyle(SettingsTokens.secondaryText))
    }

    func markTitle(_ id: String) -> String { IconNameSearch.title(of: id) }

    func typeMark(for pattern: String) -> AnyView {
        AnyView(TypeTile(icon: libraries.current?.catalogue.itemTypes[TypeID(pattern)]?.icon, size: .side))
    }

    // MARK: Types

    var typeCalls: any TypeCalls { ServerTypeCalls(client: confirmingClient) }

    func largeTypeMark(for id: String) -> AnyView {
        AnyView(TypeTile(icon: typeIcon(of: id), size: .large))
    }

    // MARK: Plugins

    /// The plugins release is read by the app itself, never through the server, at the latest release of the plugins repository.
    /// A Debug build reads the release `MARFA_PLUGINS_URL` names instead, as the command line does, to try a release of its own.
    var pluginCalls: any PluginCalls {
        #if DEBUG
        let address = ProcessInfo.processInfo.environment["MARFA_PLUGINS_URL"]
        #else
        let address: String? = nil
        #endif
        return ClientPluginCalls(server: confirmingServer, client: confirmingClient, releaseAddress: address)
    }

    /// The type's own active items, its kinds' left out.
    func itemCount(ofType id: String) -> Int {
        libraries.current?.items(in: .type(TypeID(id)), scope: .all, archived: .hidden, includingKinds: false).count ?? 0
    }

    func typePlural(of id: String) -> String? {
        guard let catalogue = libraries.current?.catalogue, catalogue.itemTypes[TypeID(id)] != nil else { return nil }
        return catalogue.plural(for: TypeID(id))
    }

    func typeIcon(of id: String) -> String? { libraries.current?.catalogue.icon(for: TypeID(id)) }

    func changeTypeIcon(_ icon: String?, ofType id: String) async -> OwnerFailure? {
        guard let library = libraries.current else { return .failed(TypeIconFailure.unsupported.message) }
        guard let failure = await library.setIcon(icon, ofType: TypeID(id)) else { return nil }
        return switch failure {
        case .unreachable: .unreachable
        case .notPermitted: .notPermitted(InstancePermission.schemaWrite.rawValue)
        case .keyRefused: .signedOut
        case .refused(let reason): .refused(reason)
        case .unsupported, .failed: .failed(failure.message)
        }
    }

    func chooseBundleFile() async -> PluginFileChoice? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose a plugin bundle.")
        panel.prompt = String(localized: "Install")
        guard await panel.begin() == .OK, let url = panel.url else { return nil }
        // A release serves a bundle of at most 16 MiB, so a larger file is not one.
        guard let data = try? Data(contentsOf: url), data.count <= 16 * 1024 * 1024 else { return .unreadable(name: url.lastPathComponent) }
        return .file(name: url.lastPathComponent, path: url.path(percentEncoded: false), data: data)
    }

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
    var lacksAsked: Bool { host.lacksAsked }
    func holds(_ scope: String) -> Bool { host.heldScopes.contains(scope) }

    func allowMore(_ permissions: Set<InstancePermission>) async -> MarfaAllowMoreOutcome {
        await libraries.marfaSettings.allowMore(permissions)
    }

    func tryAgain() { host.refresh() }

    var isSignInBusy: Bool { libraries.marfaSettings.isWorking }

    func requestSignOut() {
        libraries.marfaSettings.requestDisconnect()
    }

    func showConnection() { launcher.show(.connection) }

    func client() throws -> Client {
        guard let connection = host.configuredConnection else { throw MarfaServerCalls.Ending.keyRefused }
        return try MarfaServerCalls(connection: connection, signIns: host.signIns).client()
    }

    func refreshGrants() async { await host.refreshGrants() }

    /// The owner's calls, made through a client that shows the system's sign-in in place where the server asks the owner to
    /// confirm it is them, and sends the call again once they have.
    var ownerCalls: any OwnerCalls { ClientOwnerCalls(server: plainServer, client: confirmingClient) }

    /// What Activity, Monitoring, Limits and Start-Up ask of the server, through the same client.
    var instanceCalls: any InstanceCalls { ClientInstanceCalls(client: confirmingClient) }

    @ObservationIgnored private var heldFolderCalls: CopyFolderCalls?

    /// A folder's settings, read and written through the open copy, which owns the folder doors. One for each copy, so its
    /// pins run one at a time across Folders' pages.
    var folderCalls: any FolderCalls {
        let copy = (host.library?.source as? MarfaSource)?.copy
        if let held = heldFolderCalls, held.copy === copy { return held }
        let made = CopyFolderCalls(copy: copy)
        heldFolderCalls = made
        return made
    }

    /// The package's server, for the calls the generated client does not hold (`Server.health()`, `Server.sources()`).
    private var plainServer: (@Sendable () throws -> Server)? {
        guard let connection = host.configuredConnection else { return nil }
        let signIns = host.signIns
        let address = connection.address.absoluteString
        return { try Self.server(address: address) { try MarfaServerCalls(connection: connection, signIns: signIns).server() } }
    }

    private var confirmingClient: @Sendable () throws -> Client {
        guard let connection = host.configuredConnection else {
            return { throw MarfaError.signedOut(origin: "", message: "no server is set") }
        }
        let signIns = host.signIns
        let address = connection.address.absoluteString
        return {
            let calls = MarfaServerCalls(connection: connection, signIns: signIns)
            let server = try Self.server(address: address) { try calls.server() }
                .confirming(from: { NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow() })
            return Client(server, timeout: calls.timeout)
        }
    }

    /// The package's server for a call the generated client does not hold, set as `confirmingClient` is: installing a plugin
    /// whose types carry guidance asks the owner to sign in again, and sends the bundle once more.
    private var confirmingServer: (@Sendable () throws -> Server)? {
        guard let connection = host.configuredConnection else { return nil }
        let signIns = host.signIns
        let address = connection.address.absoluteString
        return {
            try Self.server(address: address) { try MarfaServerCalls(connection: connection, signIns: signIns).server() }
                .confirming(from: { NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow() })
        }
    }

    /// The package's server from `build`: an ended sign-in is the server ending it, anything else cannot be read.
    nonisolated private static func server(address: String, _ build: () throws -> Server) throws -> Server {
        do {
            return try build()
        } catch let ending as MarfaServerCalls.Ending {
            switch ending {
            case .keyRefused: throw MarfaError.signedOut(origin: address, message: "the sign-in ended")
            default: throw MarfaError.invalid(message: Words.signInUnreadable)
            }
        }
    }

    /// Shows the type's items in the main window last in front, as the Go menu does; offered only while a main window is open.
    var openInApp: ((String) -> Void)? {
        guard let mainWindows, mainWindows.hasMainWindow, libraries.current != nil else { return nil }
        return { [libraries] id in
            guard let library = libraries.current, let browser = mainWindows.mainWindowForward() else { return }
            browser.show(.type(TypeID(id)), in: library, order: browser.storedOrder)
        }
    }

    var ownAppVendor: String? { PreferencesType.vendor }

    var webSignInReturn: String { SystemSignIns().redirectAddress }

    func showWebSignIn(at address: URL) async -> Bool {
        guard let scheme = URL(string: webSignInReturn)?.scheme,
            let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible)
        else { return false }
        return await WebSignInSheet.show(address, endingOn: scheme, over: window)
    }

    // MARK: Trash

    var canReadTrash: Bool { TrashPage.canReadItems(scopes: Array(host.heldScopes)) }

    var deletedItems: [MarfaDeletedItem] {
        guard let library = libraries.current else { return [] }
        let access = SourceWriters.Access.app(scopes: Array(host.heldScopes), vendors: [])
        return library.deletedItems.map { item in
            MarfaDeletedItem(
                id: item.id.rawValue, title: item.displayTitle, deleted: item.trashed ?? item.modified,
                kind: library.catalogue.label(for: item.type), source: item.source.map { library.sources.name($0) },
                typeID: item.type.rawValue, canWrite: access.writes(item.type.rawValue))
        }
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
        guard let library = libraries.current, library.reachesServer, connection == .connected, grants.contains(.itemsPurge) else { return }
        let shown = library.deletedItems
        guard !shown.isEmpty else { return }
        let message = AttributedString(
            localized: "Permanently delete up to ^[\(shown.count) listed item](inflect: true)? Parts that went to Trash with their hosts may also be deleted. You can’t undo this."
        ).text
        SettingsAlert.confirm(
            title: String(localized: "Empty Trash?"), message: message, confirm: String(localized: "Empty Trash"), window: NSApp.keyWindow
        ) { confirmed, _ in
            guard confirmed else { return }
            let title = String(localized: "Can’t Empty Trash")
            guard self.libraries.current === library else {
                self.host.notices.tell(title, String(localized: "The library whose Trash you opened is no longer open."))
                return
            }
            guard library.reachesServer else { return library.tellCannotPurge() }
            guard self.connection == .connected else {
                library.notices.tell(title, String(localized: "Wait until this Mac is connected to the library, then try again."))
                return
            }
            guard self.grants.contains(.itemsPurge) else {
                library.notices.tell(title, String(localized: "This sign-in doesn’t have permission to empty Trash."))
                return
            }
            // App-vendor types are hidden from the working-copy list.
            let access = SourceWriters.Access.app(scopes: Array(self.host.heldScopes), vendors: [])
            Self.purgeUnchanged(shown, in: library, access: access)
        }
    }

    /// The main actor checks and submits without suspending, so the ordinary purge sends each accepted row's original version.
    static func purgeUnchanged(_ shown: [Item], in library: any ItemLibrary, access: SourceWriters.Access) {
        var approved = Set<ItemID>()
        var skips = BatchSkips()
        for row in shown {
            guard let current = library.item(row.id) else {
                skips.skip(.gone)
                continue
            }
            // Restore and re-trash leave the version unchanged. The row also holds the time it went to Trash.
            guard current.state == .trashed, current == row else {
                skips.skip(.changedSince)
                continue
            }
            guard access.writes(current.type.rawValue) else {
                skips.skip(.typeWriteDenied)
                continue
            }
            approved.insert(row.id)
        }
        library.tellSkipped(skips, didChange: !approved.isEmpty, failing: String(localized: "Can’t Empty Trash"))
        if !approved.isEmpty { library.deletePermanentlyOnConfirm(approved) }
    }

    // MARK: Closing

    /// Hands over what was typed in the Marfa's pages and not saved, as the app's rules say for a panel that ends any way but
    /// the person's own Cancel: the text goes through `Notices.notKept`, to the clipboard, and the draft is dropped.
    func handOverDrafts() {
        instanceSettings.handOver(
            to: libraries.host.notices, because: String(localized: "You closed Settings before saving the changes to the server’s settings."))
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
    /// Tells the person what they typed and did not save, as a change not kept, and drops it. Nothing typed hands over nothing,
    /// and a change already agreed and being sent is not one that was left unsaved.
    func handOver(to notices: Notices, because reason: String) {
        guard hasUnsentEdits else { return }
        let lines = InstanceSetting.allCases.filter(isUnsent).map { "\($0.title): \(draft[$0] ?? "")" }
        notices.notKept(String(localized: "Settings Not Saved"), text: lines.joined(separator: "\n"), reason: reason)
        revert()
    }
}
