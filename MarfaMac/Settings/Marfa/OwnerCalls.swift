import Foundation
import Marfa
import MarfaAPI
import OpenAPIRuntime
import OSLog

// What the owner's pages (Account, Apps, Keys, Addresses) ask of the server, in values of their own so the pages and
// their models read nothing generated, and a test can script every answer.

/// How much of a type, or of a pattern of types, something may reach.
nonisolated enum AccessLevel: Int, Comparable, CaseIterable, Hashable, Sendable {
    case none, read, write

    static func < (lhs: AccessLevel, rhs: AccessLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .none: String(localized: "No Access")
        case .read: String(localized: "Read Only")
        case .write: String(localized: "Read and Edit")
        }
    }
}

nonisolated struct OwnerProfile: Hashable, Sendable {
    /// Nil where the sign-in may not read it.
    var name: String?
    var username: String?
    var emailIsReadable = false
    var email: String?
    /// Whether the sign-in may read the picture, and whether there is one to read.
    var pictureIsReadable = false
    var hasPicture = false
}

/// A part of the owner's profile an app may be allowed to change.
nonisolated enum ProfileField: String, CaseIterable, Hashable, Sendable {
    case name, avatar, username, email

    func mayWrite(holding scope: (String) -> Bool) -> Bool {
        scope("profile.\(rawValue):write") || (self != .username && scope("profile:write"))
    }
}

nonisolated struct OwnerPasskey: Identifiable, Hashable, Sendable {
    let id: String
    var name: String?
    var added: Date?
    var lastUsed: Date?
}

nonisolated struct BrowserSignIn: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var userAgent: String?
    var added: Date?
    var lastUsed: Date?
}

nonisolated struct AppAccess: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case app, web, commandLine }

    let id: String
    var clientID: String
    var kind: Kind
    var name: String?
    var origins: [String]
    var scopes: [String]
    /// Each `app.<vendor>` namespace the app holds, where its own data is kept.
    var vendors: [String] = []
    var granted: Date?
    var lastUsed: Date?
}

/// What an app keeps under one `app.<vendor>` namespace, as items counted by type and state. Marfa answers counts, never a size.
nonisolated struct AppData: Hashable, Sendable {
    struct Kind: Hashable, Sendable {
        let type: String
        var active: Int
        var archived: Int
        var trashed: Int
    }

    let vendor: String
    var types: [Kind]

    var active: Int { types.reduce(0) { $0 + $1.active } }
    var archived: Int { types.reduce(0) { $0 + $1.archived } }
    var trashed: Int { types.reduce(0) { $0 + $1.trashed } }
    var total: Int { active + archived + trashed }
}

/// How removing a namespace's data ended: what the server deleted over every call it answered, and what it says is left.
nonisolated struct AppDataRemoved: Hashable, Sendable {
    var removedItems: Int
    var remainingItems: Int
    /// Why it stopped with items left, or nil where it did not stop early.
    var stoppedBy: OwnerFailure?

    var isComplete: Bool { stoppedBy == nil && remainingItems == 0 }
}

nonisolated enum KeyTier: String, CaseIterable, Hashable, Sendable {
    case library, feed

    var title: String {
        switch self {
        case .library: String(localized: "Library")
        case .feed: String(localized: "Feed")
        }
    }
}

nonisolated struct KeyInfo: Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    var source: String
    var permissions: [String]
    var tier: KeyTier
    /// Item types, or patterns of them, by what the key may do with them.
    var types: [String: AccessLevel]
    var created: Date?
    var expires: Date?
    var lastUsed: Date?
    /// The app that made it; nil for a key the owner made.
    var appClientID: String?
    /// The sources it may write under besides its own.
    var claims: [String] = []
}

/// A source the instance holds, by the name the server gives it.
nonisolated struct OwnerSource: Hashable, Sendable {
    let code: String
    let name: String
}

nonisolated struct NewKey: Hashable, Sendable {
    var label: String
    var source: String
    var tier: KeyTier
    var expires: Date?
    var types: [String: AccessLevel]
    var permissions: [String]
}

/// When a key ends, as a change sets it: on a day, or never.
nonisolated enum KeyExpiry: Hashable, Sendable {
    case on(Date)
    case never
}

/// Who this sign-in is, so a page can tell what it made from what another credential made.
nonisolated struct OwnIdentity: Hashable, Sendable {
    /// The key the app is signed in with where it is one; nil for a signed-in app.
    var keyID: String?
    /// When that key ends, where it does. A signed-in app counts as having no expiry of its own.
    var expires: Date?

    /// Whether this sign-in made what `maker` made, by the key's id. A signed-in app is not told from another app: the server
    /// names the maker of an app's webhook by its client id, which neither the server nor the package tells the app about
    /// itself, and a name is never an identity, so none of an app's makers is taken as this sign-in's.
    func made(_ maker: OwnerWebhook.Maker) -> Bool {
        maker.kind == .key && keyID != nil && maker.id == keyID
    }
}

/// What a change to a key sends. Only narrowing is ever sent for access, so a key read before another change cannot be
/// widened by it. A later expiry adds no access, so a change that names one is not held to narrowing.
nonisolated struct KeyChange: Hashable, Sendable {
    var label: String?
    var tier: KeyTier?
    var expires: KeyExpiry?
    var types: [String: AccessLevel]?
    var permissions: [String]?
}

/// A key as made: shown once, and never kept.
nonisolated struct CreatedKey: Sendable {
    let id: String
    let label: String
    let secret: String
}

nonisolated struct AddressSettings: Hashable, Sendable {
    var instanceID: String?
    var signIn: String
    var addresses: [String]
    var websites: [String]
}

nonisolated enum PasswordOutcome: Hashable, Sendable {
    case changed
    case currentWrong
    case newRefused(String)
    case tooManyAttempts(retryAfterSeconds: UInt64?)
}

/// Why an owner's call did not do what was asked, in terms a page can word.
nonisolated enum OwnerFailure: Error, Hashable, Sendable {
    enum RedeliveryRefusal: String, Hashable, Sendable {
        case webhookInactive = "webhook_inactive"
        case credentialUnavailable = "credential_unavailable"
        case deliveryNotFailed = "delivery_not_failed"
        case deliveryExpired = "delivery_expired"
    }

    case unreachable
    case signedOut
    /// The server refused for want of a permission, which it names where it does.
    case notPermitted(String?)
    /// What the call named is gone, such as a key revoked elsewhere.
    case notFound
    /// What the call read has changed since.
    case conflict
    /// Another Marfa answers at the address than the one the call was made for. Nothing was sent to it, and nothing it
    /// holds is taken as what the page showed.
    case instanceChanged
    /// The server has no settings to read: none is set, or the library has none, as the sample does not.
    case unsupported
    /// The owner closed, or did not pass, the sign-in the server asked for.
    case notConfirmed
    case refused(String)
    case redeliveryRefused(RedeliveryRefusal)
    case connectorPaused
    /// A new key's source is another key's own, in the server's words.
    case sourceHeld(String)
    /// A connector's sign-in cannot start until these of its settings, named as the server names them, hold a value.
    case signInNeeds([String])
    case failed(String)
}

/// What the owner's pages ask of the server. Every call needs the server and is never queued.
nonisolated protocol OwnerCalls: Sendable {
    func profile() async throws(OwnerFailure) -> OwnerProfile
    func passkeys() async throws(OwnerFailure) -> [OwnerPasskey]
    func renamePasskey(_ id: String, to name: String) async throws(OwnerFailure)
    func removePasskey(_ id: String) async throws(OwnerFailure)
    func passkeyAddAddress() async throws(OwnerFailure) -> URL
    func browserSignIns() async throws(OwnerFailure) -> [BrowserSignIn]
    func endSignIn(_ id: String) async throws(OwnerFailure)
    func changePassword(from current: String, to new: String) async throws(OwnerFailure) -> PasswordOutcome
    /// The parts of the profile the sign-in may change, as its scopes say; every part where it holds no scopes to read, as a
    /// Sends the owner's name alone, and answers the profile as the server then holds it.
    func setProfileName(_ name: String) async throws(OwnerFailure) -> OwnerProfile
    func setProfileContact(_ field: ProfileContactField, to value: String) async throws(OwnerFailure) -> OwnerProfile
    /// The picture's bytes, or nil where there is none.
    func profilePicture() async throws(OwnerFailure) -> Data?
    /// Stores `picture`, a PNG, JPEG or WebP within the contract's limits (`ProfilePicture.prepared`), as the owner's picture.
    func setProfilePicture(_ picture: Data) async throws(OwnerFailure) -> OwnerProfile

    func typeNames() async throws(OwnerFailure) -> [String: String]
    func apps() async throws(OwnerFailure) -> [AppAccess]
    /// Narrows an app to `scopes`, which were read as `expected`; a change since is a `conflict`.
    func narrow(_ app: AppAccess, to scopes: [String]) async throws(OwnerFailure)
    /// Disconnects `app`; `removingData` also deletes permanently what it keeps, in the same write (`items.purge`).
    func disconnect(_ app: AppAccess, removingData: Bool) async throws(OwnerFailure)
    /// What an app keeps under `vendor`, an `app.<vendor>` namespace (`grants.manage`).
    func appData(vendor: String) async throws(OwnerFailure) -> AppData
    /// Deletes everything under `vendor` permanently, calling again until none is left. Throws where the first call fails; a
    /// later failure comes back as `stoppedBy`.
    func removeAppData(vendor: String) async throws(OwnerFailure) -> AppDataRemoved

    func keys() async throws(OwnerFailure) -> [KeyInfo]
    func create(_ key: NewKey) async throws(OwnerFailure) -> CreatedKey
    func change(_ id: String, _ change: KeyChange) async throws(OwnerFailure) -> KeyInfo
    func revoke(_ id: String) async throws(OwnerFailure)
    /// Who this sign-in is: the key it is, or the app it is signed in as.
    func identity() async throws(OwnerFailure) -> OwnIdentity

    func addresses() async throws(OwnerFailure) -> AddressSettings
    func check(signIn: String?, addresses: [String]?) async throws(OwnerFailure) -> AddressPlan
    func apply(_ plan: AddressPlan, instanceID: String?) async throws(OwnerFailure) -> AddressSettings
    func setWebsites(_ websites: [String], instanceID: String?) async throws(OwnerFailure) -> AddressSettings

    /// What needs the owner's attention (`instance.read`).
    func attention() async throws(OwnerFailure) -> [AttentionConcern]
    /// The running version, database size, and total file size (`instance.read`).
    func instanceMetrics() async throws(OwnerFailure) -> InstanceMetricsReading
    /// Where files are kept and the files nothing uses (`instance.read`).
    func fileStores() async throws(OwnerFailure) -> FileStores
    /// Every source the instance holds (`keys.manage`): those of its items, whatever a source filter hides, those named or
    /// marked, and those keys hold as their own or claim.
    func sources() async throws(OwnerFailure) -> [OwnerSource]
    /// The instance's three enforcement levers, with the instance that holds them (`config.manage`).
    func sourceLimit() async throws(OwnerFailure) -> SourceLimit
    /// Replaces all three levers with `levers`, on the instance it names. Only `EnforcementSettings` calls it, since the
    /// server guards only the instance.
    func setSourceLimit(_ levers: SourceLimit) async throws(OwnerFailure) -> SourceLimit

    func webhooks() async throws(OwnerFailure) -> [OwnerWebhook]
    /// One webhook as the server holds it now.
    func webhook(_ id: String) async throws(OwnerFailure) -> OwnerWebhook
    func create(_ webhook: NewWebhook) async throws(OwnerFailure) -> CreatedWebhook
    /// Changes only what `change` names and answers the webhook as the server holds it.
    func change(webhook id: String, _ change: WebhookChange) async throws(OwnerFailure) -> OwnerWebhook
    func delete(webhook id: String) async throws(OwnerFailure)
    func deliveries(of webhook: String) async throws(OwnerFailure) -> [WebhookDeliveryInfo]
    func redeliver(_ delivery: String, of webhook: String) async throws(OwnerFailure) -> WebhookDeliveryInfo

    /// The server's health: the open fields for any sign-in, the rest for `instance.read`.
    func health() async throws(OwnerFailure) -> ServerHealth

    /// Where and how often the server backs up, and whether it checks for updates by itself (`config.manage`).
    func upkeepSettings() async throws(OwnerFailure) -> UpkeepSettings
    /// Changes only what `change` names, on the instance `instanceID` was read from, and answers the settings as the server now holds
    /// them. A folder change needs a recent sign-in, which the call shows in place.
    func change(_ settings: UpkeepSettings, _ change: UpkeepSettingsChange) async throws(OwnerFailure) -> UpkeepSettings
    /// The backups the server holds, newest first (`backups.manage`).
    func backups() async throws(OwnerFailure) -> [BackupRecord]
    func backUpNow() async throws(OwnerFailure) -> BackupTaken
    /// Restores `backup`, which needs a recent sign-in that the call shows in place.
    func restore(_ backup: BackupRecord) async throws(OwnerFailure) -> BackupRestored

    func updateStatus() async throws(OwnerFailure) -> UpdateStatus
    /// Asks the server to look for a newer release now (`instance.maintain`), then reads the status again.
    func checkForUpdates() async throws(OwnerFailure) -> UpdateStatus
    /// Starts the update to the release found (`instance.maintain`).
    func startUpdate() async throws(OwnerFailure) -> UpdateStatus

    func housekeepingJobs() async throws(OwnerFailure) -> [HousekeepingJob]
    /// Takes the server's clock as right, so jobs that delete run again (`instance.maintain`), and answers the time the server took.
    func confirmClock() async throws(OwnerFailure) -> Date?

    func folders() async throws(OwnerFailure) -> FolderListing
    func folderReport(_ id: String) async throws(OwnerFailure) -> FolderReport

    /// The installed plugins that hold a connector (`connectors.manage`).
    func connectorPlugins() async throws(OwnerFailure) -> [PluginConnectorSummary]
    /// What the owner chose for a plugin's connector.
    func connectorControl(of plugin: String) async throws(OwnerFailure) -> ConnectorControl
    /// What the connector registered under `id` has reported itself.
    func connectorRegistration(_ id: String) async throws(OwnerFailure) -> ConnectorRegistration
    func connectorHosts() async throws(OwnerFailure) -> [ConnectorHostInfo]
    /// One machine, read again, with the connectors on it.
    func connectorHost(_ id: String) async throws(OwnerFailure) -> ConnectorHostInfo
    /// Makes a machine that runs connectors, with its one-time link, which the server answers only this once.
    func createConnectorHost(named name: String) async throws(OwnerFailure) -> ConnectorHostLink
    /// A new one-time link for a machine, which ends the one it had.
    func linkConnectorHost(_ id: String) async throws(OwnerFailure) -> ConnectorHostLink
    func connectorSettings(of plugin: String) async throws(OwnerFailure) -> ConnectorSettingsReading
    /// Sends only the settings `changes` names, and answers every setting as the server now holds it.
    func changeConnectorSettings(of plugin: String, _ changes: [String: ConnectorSettingChange]) async throws(OwnerFailure) -> ConnectorSettingsReading
    /// The three choices a connector follows at its next run. Each answers the choice as stored.
    func pauseConnector(_ plugin: String) async throws(OwnerFailure) -> ConnectorControl
    func resumeConnector(_ plugin: String) async throws(OwnerFailure) -> ConnectorControl
    /// Refused while the connector is paused.
    func runConnector(_ plugin: String) async throws(OwnerFailure) -> ConnectorControl
    /// Moves a connector to the machine `host`, or to none with nil.
    func assignConnector(_ plugin: String, toHost host: String?) async throws(OwnerFailure)
    /// Starts the vendor sign-in, for the browser to be sent back to `address`, which the app registered.
    func startConnectorSignIn(of plugin: String, returningTo address: String) async throws(OwnerFailure) -> ConnectorSignInStart
    func connectorSignInStatus(of plugin: String) async throws(OwnerFailure) -> ConnectorSignInReading

    /// What the owner chose each kind of a connector brings, with the rewrites asked for and not yet carried out.
    func connectorMapping(of plugin: String) async throws(OwnerFailure) -> ConnectorMappingReading
    /// Stores the mapping read as `version`. A mapping that changed since, or one the server refuses, is an outcome, not a failure.
    func saveConnectorMapping(of plugin: String, version: Int, kinds: [String: KindMapping]) async throws(OwnerFailure) -> MappingSaveOutcome
    /// Asks the connector to render one of its recent items under `draft`, or under the mapping in force with none.
    func startMappingPreview(of plugin: String, kind: String, draft: KindMapping?) async throws(OwnerFailure) -> MappingPreview
    /// A preview as it stands; `notFound` once it has expired.
    func mappingPreview(of plugin: String, id: String) async throws(OwnerFailure) -> MappingPreview
    /// Counts the items a rewrite moves, or asks the connector to move them.
    func rewriteConnectorItems(of plugin: String, kinds: [String], dryRun: Bool) async throws(OwnerFailure) -> MappingRewrite
    /// The types a kind can land as.
    func mappingTypeOptions() async throws(OwnerFailure) -> [MappingTypeOption]
    func mappingType(_ id: String) async throws(OwnerFailure) -> MappingTypeInfo

    /// The link types, the names of the item types they join and the plugins that brought them.
    func linkTypes() async throws(OwnerFailure) -> LinkTypeListing
    /// Registers a link type of the owner's (`metadata.edge_types:write`).
    func register(_ linkType: NewLinkType) async throws(OwnerFailure) -> OwnerLinkType
    /// Deletes a link type of the owner's, never forced, so a type links still use is kept (`schema.write`).
    func deleteLinkType(_ id: String) async throws(OwnerFailure) -> LinkTypeDeletion
}

/// What changing the addresses would do, as the server said before anything was written, with the change it said it
/// about. Applying it writes that change and no other.
nonisolated struct AddressPlan: Hashable, Sendable {
    enum Reach: Hashable, Sendable {
        /// The sign-in address did not move, so nothing was asked.
        case notAsked
        case answers
        case notAnswering(reason: String?)
        case notChecked
    }

    struct Consequence: Hashable, Sendable {
        let code: String
        let sentence: String
        let count: Int?
    }

    /// What was asked about, so that exactly it is written once the owner agrees.
    let askedSignIn: String?
    let askedAddresses: [String]?
    var signIn: String
    var addresses: [String]
    var requiresConfirmation: Bool
    var consequences: [Consequence]
    var reach: Reach
}

/// `OwnerCalls` over the package's generated client.
nonisolated struct ClientOwnerCalls: OwnerCalls {
    /// The package's server, for `Server.health()` and `Server.sources()`, which the generated client does not hold. Nil where
    /// there is none.
    var server: (@Sendable () throws -> Server)?
    let client: @Sendable () throws -> Client

    init(server: (@Sendable () throws -> Server)? = nil, client: @escaping @Sendable () throws -> Client) {
        self.server = server
        self.client = client
    }

    func make() throws(OwnerFailure) -> Client {
        do { return try client() } catch { throw Self.failure(error) }
    }

    /// The package's error inside what the generated client threw, which wraps it.
    static func marfaError(_ error: any Error) -> MarfaError? {
        var current = error
        for _ in 0..<4 {
            if let known = current as? MarfaError { return known }
            guard let wrapped = current as? ClientError else { return nil }
            current = wrapped.underlyingError
        }
        return nil
    }

    /// What the package's error stands for, unwrapping the generated client's own wrapper. A `409` that names no cause of
    /// its own (the codes below) is the server refusing the call, which `plainConflict` words for the call that made it.
    static func failure(_ error: any Error, plainConflict: (String) -> OwnerFailure = { .refused($0) }) -> OwnerFailure {
        guard let error = marfaError(error) else {
            OwnerSettingsLog.failure(error.localizedDescription)
            return .failed(String(localized: "The server’s answer couldn’t be read."))
        }
        if error.isOffline { return .unreachable }
        if error.isKeyRefusal { return .signedOut }
        switch error {
        case .forbidden(let code, _, let server):
            if code == "access_denied" { return .notConfirmed }
            return .notPermitted(server?.details?.object?["required_scope"]?.string)
        case .notFound: return .notFound
        case .versionConflict: return .conflict
        case .instanceChanged: return .instanceChanged
        case .server(409, let code, let message, let details, let server):
            OwnerSettingsLog.failure(error.localizedDescription)
            if code == "connector_paused" { return .connectorPaused }
            if code == "conflict", let reason = (details ?? server?.details)?.object?["reason"]?.string,
                let refusal = OwnerFailure.RedeliveryRefusal(rawValue: reason)
            {
                return .redeliveryRefused(refusal)
            }
            let refusals: Set<String> = ["sign_in_address_check_failed", "sign_in_address_change_unconfirmed"]
            return refusals.contains(code) ? .refused(message) : plainConflict(message)
        case .validation(_, let message, _, _):
            OwnerSettingsLog.failure(error.localizedDescription)
            return .refused(message)
        case .confirmationRequired, .appSignInRequired, .canceled: return .notConfirmed
        default:
            let detail = error.localizedDescription
            OwnerSettingsLog.failure(detail)
            return .failed(detail)
        }
    }

    /// The settings changed while the server checked the address, the only `409` that `/config` answers without a cause of
    /// its own.
    static let configConflict: @Sendable (String) -> OwnerFailure = { _ in .conflict }

    func run<Result>(
        plainConflict: (String) -> OwnerFailure = { .refused($0) }, _ call: (Client) async throws -> Result
    ) async throws(OwnerFailure) -> Result {
        let client = try make()
        do {
            return try await call(client)
        } catch let failure as OwnerFailure {
            throw failure
        } catch {
            throw Self.failure(error, plainConflict: plainConflict)
        }
    }

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return (try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)))
            ?? (try? Date(text, strategy: .iso8601))
            ?? (try? Date(text, strategy: .iso8601.year().month().day()))
    }

    /// Whether the server's text names a time of day, not only a day.
    static func hasTime(_ text: String?) -> Bool { text?.contains("T") ?? true }
}

nonisolated enum OwnerSettingsLog {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Marfa", category: "OwnerSettings")

    static func failure(_ detail: String) {
        logger.error("Settings request failed: \(detail, privacy: .private)")
    }
}
