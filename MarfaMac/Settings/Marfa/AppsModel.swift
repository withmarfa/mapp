import Foundation
import Marfa
import Observation

/// The Apps page: the apps the owner approved, with what each may reach and the data each keeps. Access can only be
/// narrowed, and narrowing, removing data or disconnecting asks first. Every change is sent with the access it was read as,
/// so a change made elsewhere is told, not overwritten.
@Observable @MainActor final class AppsModel {
    /// A change waiting on the owner's answer.
    struct Question: Identifiable, Equatable {
        enum Action: Equatable {
            case narrow(appID: String, scopes: [String])
            case disconnect(appID: String)
            case removeData(appID: String, vendor: String)
        }

        let id = UUID()
        let action: Action
        let title: String
        let message: String
        let confirm: String
        /// The choice that goes with the question, off until the owner ticks it, or nil where there is none.
        var checkbox: String?
    }

    /// What the page knows of one app's data.
    enum Data: Equatable {
        case reading
        case kept([AppData])
        case failed(OwnerFailure)
    }

    /// The most items the server deletes in the write that disconnects an app. Above it, the data goes first.
    nonisolated static let disconnectRemovalLimit = 1000

    private let context: OwnerContext
    /// The namespace the app keeps its own settings in, whose data this page never removes: `PreferencesSync` keeps them.
    private let ownVendor: String?

    private(set) var apps: [AppAccess] = []
    private(set) var typeNames: [String: String] = [:]
    private var identity: OwnIdentity?
    var currentKeyID: String? { identity?.keyID }
    private var currentAppClientID: String?
    /// The keys each app made, by the app's client ID, where the app may list keys.
    private(set) var keysMade: [String: [KeyInfo]] = [:]
    private let loader = OwnerLoader()
    var failure: OwnerFailure? { loader.failure }
    private let keysRead = OwnerLoader.ReadStatus()
    var keysFailure: OwnerFailure? { keysRead.failure }
    var hasLoaded: Bool { loader.hasLoaded }
    /// One line under a row whose change was refused, by the app's id.
    private(set) var rowErrors: [String: OwnerFailure] = [:]
    private(set) var disconnectDataFailures: [String: OwnerFailure] = [:]
    /// What each app keeps, by the app's id, read when its page opens and after a removal.
    private(set) var data: [String: Data] = [:]
    /// The apps whose data is being removed now.
    private(set) var removing: Set<String> = []
    /// A removal that stopped with data left, by the app's id, until the data is read again and shows what is left.
    private(set) var unfinished: [String: AppDataRemoved] = [:]
    /// An app whose data a finished removal deleted before its disconnect failed, by the app's id, with how many items went
    /// and why the disconnect stopped.
    private(set) var removedButConnected: [String: (items: Int, stoppedBy: OwnerFailure)] = [:]
    var question: Question?
    /// The app an Apps page was disconnected from, so the page it was shown on can go back.
    private(set) var disconnected: String?

    init(context: OwnerContext, ownVendor: String? = nil) {
        self.context = context
        self.ownVendor = ownVendor
    }

    func app(_ id: String) -> AppAccess? { apps.first { $0.id == id } }

    var canReadApps: Bool { context.grants().contains(.grantsManage) }

    func isCurrent(_ app: AppAccess) -> Bool { app.clientID == currentAppClientID }

    static func name(of app: AppAccess) -> String {
        if let name = app.name, !name.isEmpty { return name }
        switch app.kind {
        case .commandLine: return String(localized: "Command Line")
        case .web, .app: return app.clientID
        }
    }

    func load(includeKeys: Bool = true) async {
        await loader.load(in: context, primary: { () throws(OwnerFailure) in
            apps = try await context.calls.apps()
        }, secondary: [
            .quiet { [self] () throws(OwnerFailure) in try await readIdentity() },
            .quiet { [self] () throws(OwnerFailure) in
                typeNames = [:]
                typeNames = try await context.calls.typeNames()
            },
            .required(keysRead) { [self] () throws(OwnerFailure) in
                guard includeKeys, !context.grants().isDisjoint(with: [.keysManage, .keysMint]) else {
                    keysMade = [:]
                    return
                }
                let keys = try await context.calls.keys()
                keysMade = Dictionary(grouping: keys.filter { $0.appClientID != nil }, by: { $0.appClientID ?? "" })
            },
        ])
    }

    private func readIdentity() async throws(OwnerFailure) {
        identity = nil
        currentAppClientID = nil
        let identity = try await context.calls.identity()
        self.identity = identity
        guard identity.keyID == nil, let ownVendor, apps.contains(where: { $0.vendors.contains(ownVendor) }) else { return }
        // An OAuth caller can read app data only from namespaces held by its own registration.
        currentAppClientID = try await context.calls.appData(vendor: ownVendor).clientID
    }

    // MARK: Narrowing

    /// Asks before lowering what `pattern` may do for `app`.
    func askToNarrow(_ app: AppAccess, pattern: String, to level: AccessLevel) {
        ask(app, scopes: AccessScopes.narrowed(app.scopes, pattern: pattern, to: level))
    }

    func askToRemove(permission: String, from app: AppAccess) {
        ask(app, scopes: AccessScopes.removing(permission: permission, from: app.scopes))
    }

    private func ask(_ app: AppAccess, scopes: [String]) {
        guard scopes != app.scopes else { return }
        let name = Self.name(of: app)
        question = Question(
            action: .narrow(appID: app.id, scopes: scopes), title: String(localized: "Narrow \(name)’s access?"),
            message: String(localized: "\(name) must ask you to get it back. Keys it made that reach further stop working."),
            confirm: String(localized: "Narrow"))
    }

    /// The namespaces of `app` whose data can be removed here: not the app's own settings.
    func removableVendors(of app: AppAccess) -> [String] { app.vendors.filter { $0 != ownVendor } }

    /// Whether the namespace is the one the app keeps its own settings in.
    func isOwn(_ vendor: String) -> Bool { vendor == ownVendor }

    func dataRemovalFailure(for app: AppAccess, vendor: String) -> OwnerFailure? {
        let required: [InstancePermission] = [.grantsManage, .itemsPurge]
        for permission in required where !context.grants().contains(permission) {
            return .notPermitted(permission.rawValue)
        }
        let held: AppData? = if case .kept(let entries)? = data[app.id] { entries.first { $0.vendor == vendor } } else { nil }
        let appClientID = currentAppClientID ?? identity?.appClientID
        if let appClientID, appClientID != app.clientID { return .notPermitted(nil) }
        if case .failed(.notPermitted(let scope))? = data[app.id] { return .notPermitted(scope) }
        if let holder = held?.clientID, holder != app.clientID { return .notPermitted(nil) }

        let registered = typeNames.keys.filter { $0.hasPrefix(vendor + ".") }
        let types = Set(registered).union(held?.types.map(\.type) ?? [])
        let appAccess: SourceWriters.Access? = if appClientID == app.clientID
            || (identity != nil && identity?.keyID == nil && held?.clientID == app.clientID)
        {
            Self.vendorAccess(scopes: app.scopes, vendor: vendor)
        } else { nil }
        let keyAccess = identity?.keyTypes.map { SourceWriters.Access.key(types: $0, madeByApp: identity?.appClientID != nil) }
        if types.contains(where: { appAccess?.writes($0) == false || keyAccess?.writes($0) == false }) {
            return .notPermitted(vendor + ".*:write")
        }
        // The counts include unregistered types with items. A type with no items is listed only if registered.
        let deletesTypes = !registered.isEmpty || held?.types.contains { $0.active == 0 && $0.archived == 0 && $0.trashed == 0 } == true
        if deletesTypes && !context.grants().contains(.schemaWrite) { return .notPermitted(InstancePermission.schemaWrite.rawValue) }
        return nil
    }

    private static func vendorAccess(scopes: [String], vendor: String) -> SourceWriters.Access {
        let entries = AccessScopes.parse(scopes).entries
        let inherited = entries.filter {
            let root = $0.pattern.prefix { $0 != "." }
            return !["app", "edge", "metadata", "profile"].contains(root)
        }.map(\.level).max() ?? .none
        var types = Dictionary(uniqueKeysWithValues: entries.filter { $0.pattern.hasPrefix("app.") }.map { ($0.pattern, $0.level) })
        let wildcard = vendor + ".*"
        types[wildcard] = max(types[wildcard] ?? types["app.*"] ?? .none, inherited)
        return .key(types: types, madeByApp: true)
    }

    static func dataRemovalPermissionLine(_ failure: OwnerFailure) -> String? {
        guard case .notPermitted(let scope) = failure else { return nil }
        if let scope {
            return InstancePermission(rawValue: scope) == nil ? OwnerWording.permissionLine(scope) : nil
        }
        return String(localized: "This sign-in needs access to this app’s namespace and its types.")
    }

    func askToDisconnect(_ app: AppAccess, keepingData: Bool = false) {
        let name = Self.name(of: app)
        let hasRemovableData = !removableVendors(of: app).isEmpty && !app.vendors.contains { isOwn($0) }
        let offersData = hasRemovableData && !keepingData
            && removableVendors(of: app).allSatisfy { dataRemovalFailure(for: app, vendor: $0) == nil }
        var message = String(localized: "\(name) stops working at once and must be approved again. Its webhooks are deleted. The keys it made keep working.")
        if isCurrent(app) {
            message += " " + String(localized: "Disconnecting this app also signs this Mac out.")
        } else if currentAppClientID == nil, currentKeyID == nil {
            message += " " + String(localized: "If this Mac uses this app sign-in, disconnecting it signs this Mac out.")
        }
        if offersData {
            message += " " + String(localized: "Its data stays unless you also remove it. Removing it deletes it permanently, and only a backup brings it back.")
        }
        question = Question(
            action: .disconnect(appID: app.id), title: String(localized: "Disconnect \(name)?"), message: message,
            confirm: String(localized: "Disconnect"), checkbox: offersData ? String(localized: "Also remove its data") : nil)
    }

    /// Asks before deleting what `app` keeps under `vendor`.
    func askToRemoveData(_ app: AppAccess, vendor: String) {
        guard app.vendors.contains(vendor), !isOwn(vendor), dataRemovalFailure(for: app, vendor: vendor) == nil else { return }
        let name = Self.name(of: app)
        question = Question(
            action: .removeData(appID: app.id, vendor: vendor), title: String(localized: "Remove the Data \(name) Keeps?"),
            message: String(localized: "This deletes it permanently, the items in the trash too. Only a backup brings it back. \(name) stays connected and may make new data."),
            confirm: String(localized: "Remove"))
    }

    func cancelQuestion() { question = nil }

    /// Carries out what was asked, `alsoRemovingData` being the owner's answer to the question's checkbox.
    func confirm(_ asked: Question, alsoRemovingData: Bool = false) async {
        question = nil
        switch asked.action {
        case .narrow(let id, let scopes):
            guard let app = app(id) else { return }
            rowErrors[id] = nil
            do {
                try await context.calls.narrow(app, to: scopes)
                await load()
            } catch {
                await refused(error, appID: id)
            }
        case .disconnect(let id):
            guard let app = app(id) else { return }
            rowErrors[id] = nil
            disconnectDataFailures[id] = nil
            unfinished[id] = nil
            removedButConnected[id] = nil
            let removingData = alsoRemovingData && asked.checkbox != nil
            if removingData {
                guard !app.vendors.contains(where: isOwn) else {
                    disconnectDataFailures[id] = .conflict
                    return
                }
                if let failure = app.vendors.lazy.compactMap({ self.dataRemovalFailure(for: app, vendor: $0) }).first {
                    disconnectDataFailures[id] = failure
                    return
                }
            }
            var removedItems = 0
            do {
                if removingData, case .kept(let kept)? = data[id], kept.reduce(0, { $0 + $1.total }) > Self.disconnectRemovalLimit {
                    // The server refuses to disconnect with more than it deletes in one write, so the data goes first.
                    for vendor in removableVendors(of: app) {
                        var removal = try await context.calls.removeAppData(vendor: vendor)
                        removedItems += removal.removedItems
                        guard removal.isComplete else {
                            removal.removedItems = removedItems
                            unfinished[id] = removal
                            if let failure = removal.stoppedBy {
                                disconnectDataFailures[id] = failure
                                await context.learn(from: failure)
                            }
                            await readData(of: app)
                            return
                        }
                    }
                }
                try await context.calls.disconnect(app, removingData: removingData)
                apps.removeAll { $0.id == id }
                data[id] = nil
                disconnected = id
            } catch {
                if removingData { disconnectDataFailures[id] = error }
                guard removedItems > 0 else {
                    if removingData {
                        await context.learn(from: error)
                        if error == .conflict || error == .notFound { await load() }
                    } else {
                        await refused(error, appID: id)
                    }
                    return
                }
                // The data is gone and the app is connected: the row's "Not Changed" would be untrue, so the page says both.
                removedButConnected[id] = (removedItems, error)
                await context.learn(from: error)
                if error == .conflict || error == .notFound { await load() }
                if let app = self.app(id) { await readData(of: app) }
            }
        case .removeData(let id, let vendor):
            guard let app = app(id) else { return }
            guard app.vendors.contains(vendor), !isOwn(vendor) else {
                return await refused(.conflict, appID: id)
            }
            if let failure = dataRemovalFailure(for: app, vendor: vendor) {
                return await refused(failure, appID: id)
            }
            rowErrors[id] = nil
            unfinished[id] = nil
            removing.insert(id)
            defer { removing.remove(id) }
            do {
                let removal = try await context.calls.removeAppData(vendor: vendor)
                if !removal.isComplete { unfinished[id] = removal }
            } catch {
                await refused(error, appID: id)
            }
            await readData(of: app)
        }
    }

    // MARK: Data

    /// What a removal that deleted items and then stopped says under the data: never that nothing changed, and told even where
    /// the data could not be read again.
    struct RemovalNote: Equatable {
        let title: String
        let line: String
    }

    func removalNote(for app: AppAccess) -> RemovalNote? {
        if let gone = removedButConnected[app.id] {
            return RemovalNote(
                title: String(localized: "Data Removed, Still Connected"),
                line: AppDataWording.removedButConnected(removed: gone.items, appName: Self.name(of: app), stoppedBy: gone.stoppedBy))
        }
        guard let left = unfinished[app.id] else { return nil }
        var couldReadAgain = true
        if case .failed? = data[app.id] { couldReadAgain = false }
        return RemovalNote(
            title: String(localized: "Some Data May Be Left"), line: AppDataWording.unfinished(left, couldReadAgain: couldReadAgain))
    }

    /// Reads what `app` keeps under each namespace it holds. Without any, nothing is asked.
    func readData(of app: AppAccess) async {
        guard !app.vendors.isEmpty else { return data[app.id] = .kept([]) }
        if data[app.id] == nil { data[app.id] = .reading }
        var kept: [AppData] = []
        for vendor in app.vendors {
            do {
                kept.append(try await context.calls.appData(vendor: vendor))
            } catch {
                data[app.id] = .failed(error)
                await context.learn(from: error)
                return
            }
        }
        data[app.id] = .kept(kept)
    }

    /// A refusal is told under the row and the page reads again, so what it shows is what the server holds.
    private func refused(_ failure: OwnerFailure, appID: String) async {
        rowErrors[appID] = failure
        await context.learn(from: failure)
        if failure == .conflict || failure == .notFound { await load() }
    }
}
