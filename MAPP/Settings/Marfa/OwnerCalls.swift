import Foundation
import Marfa
import MarfaAPI
import OpenAPIRuntime

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
    var username: String?
    var emailIsReadable = false
    var email: String?

    var isEmpty: Bool { username == nil && !emailIsReadable }
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
    var granted: Date?
    var lastUsed: Date?
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
}

nonisolated struct NewKey: Hashable, Sendable {
    var label: String
    var source: String
    var tier: KeyTier
    var expires: Date?
    var types: [String: AccessLevel]
    var permissions: [String]
}

/// What a change to a key sends. Only narrowing is ever sent for access, so a key read before another change cannot be
/// widened by it.
nonisolated struct KeyChange: Hashable, Sendable {
    var label: String?
    var tier: KeyTier?
    var expires: Date?
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
    /// The owner closed, or did not pass, the sign-in the server asked for.
    case notConfirmed
    case refused(String)
    /// A new key's source is another key's own, in the server's words.
    case sourceHeld(String)
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

    func typeNames() async throws(OwnerFailure) -> [String: String]
    func apps() async throws(OwnerFailure) -> [AppAccess]
    /// Narrows an app to `scopes`, which were read as `expected`; a change since is a `conflict`.
    func narrow(_ app: AppAccess, to scopes: [String]) async throws(OwnerFailure)
    func disconnect(_ app: AppAccess) async throws(OwnerFailure)

    func keys() async throws(OwnerFailure) -> [KeyInfo]
    func create(_ key: NewKey) async throws(OwnerFailure) -> CreatedKey
    func change(_ id: String, _ change: KeyChange) async throws(OwnerFailure) -> KeyInfo
    func revoke(_ id: String) async throws(OwnerFailure)

    func addresses() async throws(OwnerFailure) -> AddressSettings
    func check(signIn: String?, addresses: [String]?) async throws(OwnerFailure) -> AddressPlan
    func apply(_ plan: AddressPlan, instanceID: String?) async throws(OwnerFailure) -> AddressSettings
    func setWebsites(_ websites: [String], instanceID: String?) async throws(OwnerFailure) -> AddressSettings

    /// What needs the owner's attention (`instance.read`).
    func attention() async throws(OwnerFailure) -> [AttentionConcern]
    /// How the server stands: its health, what it holds and whether an update is ready (`instance.read`). A part the server
    /// does not give is left out.
    func reading() async throws(OwnerFailure) -> InstanceReading
    /// Where files are kept and the files nothing uses (`instance.read`).
    func fileStores() async throws(OwnerFailure) -> FileStores
    /// The source filter, with the instance that holds it (`config.manage`).
    func sourceLimit() async throws(OwnerFailure) -> SourceLimit
    /// Replaces the source filter, sending the other two levers as `limit` holds them, or turns it off with nil. The server
    /// guards only the instance, so a caller reads the limit again just before.
    func setSourceLimit(_ limit: SourceLimit, to filter: (types: [String], sources: [String])?) async throws(OwnerFailure) -> SourceLimit

    func webhooks() async throws(OwnerFailure) -> [OwnerWebhook]
    /// One webhook as the server holds it now.
    func webhook(_ id: String) async throws(OwnerFailure) -> OwnerWebhook
    func create(_ webhook: NewWebhook) async throws(OwnerFailure) -> CreatedWebhook
    /// Changes only what `change` names and answers the webhook as the server holds it.
    func change(webhook id: String, _ change: WebhookChange) async throws(OwnerFailure) -> OwnerWebhook
    func delete(webhook id: String) async throws(OwnerFailure)
    func deliveries(of webhook: String) async throws(OwnerFailure) -> [WebhookDeliveryInfo]
    func redeliver(_ delivery: String, of webhook: String) async throws(OwnerFailure) -> WebhookDeliveryInfo

    func folders() async throws(OwnerFailure) -> FolderListing
    func folderReport(_ id: String) async throws(OwnerFailure) -> FolderReport
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
    let client: @Sendable () throws -> Client

    func make() throws(OwnerFailure) -> Client {
        do { return try client() } catch { throw Self.failure(error) }
    }

    /// What the package's error stands for, unwrapping the generated client's own wrapper. A `409` that names no cause of
    /// its own (the codes below) is the server refusing the call, which `plainConflict` words for the call that made it.
    static func failure(_ error: any Error, plainConflict: (String) -> OwnerFailure = { .refused($0) }) -> OwnerFailure {
        var current = error
        var found: MarfaError?
        for _ in 0..<4 {
            if let known = current as? MarfaError {
                found = known
                break
            }
            guard let wrapped = current as? ClientError else { break }
            current = wrapped.underlyingError
        }
        guard let error = found else { return .failed(String(localized: "The server’s answer couldn’t be read.")) }
        if error.isOffline { return .unreachable }
        if error.isKeyRefusal { return .signedOut }
        switch error {
        case .forbidden(let code, _, let server):
            if code == "access_denied" { return .notConfirmed }
            return .notPermitted(server?.details?.object?["required_scope"]?.string)
        case .notFound: return .notFound
        case .versionConflict: return .conflict
        case .instanceChanged: return .instanceChanged
        case .server(let status, let code, let message, _, _) where status == 409:
            let refusals: Set<String> = ["sign_in_address_check_failed", "sign_in_address_change_unconfirmed"]
            return refusals.contains(code) ? .refused(message) : plainConflict(message)
        case .validation(_, let message, _, _): return .refused(message)
        case .confirmationRequired, .appSignInRequired, .canceled: return .notConfirmed
        default: return .failed(error.localizedDescription)
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
        return try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
            ?? Date(text, strategy: .iso8601)
    }

    private static func text(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    }

    // MARK: Account

    func profile() async throws(OwnerFailure) -> OwnerProfile {
        try await run { client in
            let profile = try await client.getProfile().ok.body.json
            return OwnerProfile(
                username: profile.username, emailIsReadable: profile.email != nil, email: profile.email?.value)
        }
    }

    func passkeys() async throws(OwnerFailure) -> [OwnerPasskey] {
        try await run { client in
            try await client.listOwnerPasskeys().ok.body.json.data.map {
                OwnerPasskey(id: $0.id, name: $0.name, added: Self.date($0.createdAt), lastUsed: Self.date($0.lastUsedAt))
            }
        }
    }

    func renamePasskey(_ id: String, to name: String) async throws(OwnerFailure) {
        try await run { client in
            _ = try await client.renameOwnerPasskey(path: .init(id: id), body: .json(.init(name: name))).ok
        }
    }

    func removePasskey(_ id: String) async throws(OwnerFailure) {
        try await run { client in _ = try await client.deleteOwnerPasskey(path: .init(id: id)).ok }
    }

    func passkeyAddAddress() async throws(OwnerFailure) -> URL {
        try await run { client in
            let link = try await client.getPasskeyAddUrl().ok.body.json
            guard let url = URL(string: link.url), url.scheme == "https" || url.scheme == "http" else {
                throw OwnerFailure.failed(String(localized: "The server’s link for adding a passkey couldn’t be read."))
            }
            return url
        }
    }

    func browserSignIns() async throws(OwnerFailure) -> [BrowserSignIn] {
        try await run { client in
            try await client.listSignIns().ok.body.json.data.filter { $0.kind == .browser }.map {
                BrowserSignIn(
                    id: $0.id, name: $0.name, userAgent: $0.userAgent, added: Self.date($0.createdAt),
                    lastUsed: Self.date($0.lastUsedAt))
            }
        }
    }

    func endSignIn(_ id: String) async throws(OwnerFailure) {
        try await run { client in _ = try await client.endSignIn(path: .init(id: id)).ok }
    }

    func changePassword(from current: String, to new: String) async throws(OwnerFailure) -> PasswordOutcome {
        let client = try make()
        do {
            switch try await client.changePassword(from: current, to: new) {
            case .changed: return .changed
            case .currentPasswordWrong: return .currentWrong
            case .newPasswordRefused(let message): return .newRefused(message)
            case .notPermitted(let scope, _): throw OwnerFailure.notPermitted(scope)
            case .tooManyAttempts(let seconds): return .tooManyAttempts(retryAfterSeconds: seconds)
            }
        } catch let failure as OwnerFailure {
            throw failure
        } catch {
            throw Self.failure(error)
        }
    }

    // MARK: Apps

    func typeNames() async throws(OwnerFailure) -> [String: String] {
        try await run { client in
            OwnerWording.typeNames(
                try await client.listTypes().ok.body.json.data.map { (id: $0.value1.id, label: $0.value1.label ?? $0.value1.id, parent: $0.value1.parent) })
        }
    }

    func apps() async throws(OwnerFailure) -> [AppAccess] {
        try await run { client in
            try await client.listAppGrants().ok.body.json.data.map { grant in
                let kind: AppAccess.Kind =
                    switch grant.kind {
                    case .cli: .commandLine
                    case .web: .web
                    case .app: .app
                    }
                return AppAccess(
                    id: grant.id, clientID: grant.clientId, kind: kind, name: grant.clientName, origins: grant.origins,
                    scopes: grant.scopes, granted: Self.date(grant.grantedAt), lastUsed: Self.date(grant.lastUsedAt))
            }
        }
    }

    func narrow(_ app: AppAccess, to scopes: [String]) async throws(OwnerFailure) {
        // The grant's scopes changed since they were read: the only `409` this call answers.
        try await run(plainConflict: { _ in .conflict }) { client in
            _ = try await client.narrowAppGrant(
                path: .init(id: app.id), body: .json(.init(scopes: scopes, expectedScopes: app.scopes))
            ).ok
        }
    }

    func disconnect(_ app: AppAccess) async throws(OwnerFailure) {
        try await run { client in _ = try await client.revokeAppGrant(path: .init(id: app.id)).ok }
    }

    // MARK: Keys

    private static func info(_ key: Components.Schemas.ApiKey) -> KeyInfo {
        var types: [String: AccessLevel] = [:]
        for (pattern, level) in key.typePermissions.additionalProperties {
            types[pattern] = switch level {
            case .none: AccessLevel.none
            case .read: .read
            case .write: .write
            }
        }
        return KeyInfo(
            id: key.id, label: key.label, source: key.source, permissions: key.permissions.map(\.rawValue),
            tier: KeyTier(rawValue: key.defaultTier.rawValue) ?? .library, types: types, created: date(key.createdAt),
            expires: date(key.expiresAt), lastUsed: date(key.lastUsedAt), appClientID: key.oauthClientId)
    }

    private static func levels(_ types: [String: AccessLevel]) -> [String: Components.Schemas.TypePermissionLevel] {
        types.mapValues { level in
            switch level {
            case .none: .none
            case .read: .read
            case .write: .write
            }
        }
    }

    func keys() async throws(OwnerFailure) -> [KeyInfo] {
        try await run { client in try await client.listKeys().ok.body.json.data.map(Self.info) }
    }

    func create(_ key: NewKey) async throws(OwnerFailure) -> CreatedKey {
        // Another key holds the source: the only `409` this call answers.
        try await run(plainConflict: { .sourceHeld($0) }) { client in
            let body = Operations.CreateKey.Input.Body.JsonPayload(
                label: key.label, source: key.source,
                permissions: key.permissions.compactMap { Components.Schemas.Permission(rawValue: $0) },
                defaultTier: Components.Schemas.Tier(rawValue: key.tier.rawValue),
                typePermissions: .init(additionalProperties: Self.levels(key.types)),
                expiresAt: key.expires.map(Self.text), ownerKey: true)
            let made = try await client.createKey(body: .json(body)).created.body.json
            return CreatedKey(id: made.id, label: made.label, secret: made.key)
        }
    }

    func change(_ id: String, _ change: KeyChange) async throws(OwnerFailure) -> KeyInfo {
        try await run { client in
            let body = Operations.UpdateKey.Input.Body.JsonPayload(
                label: change.label, defaultTier: change.tier.flatMap { Components.Schemas.Tier(rawValue: $0.rawValue) },
                typePermissions: change.types.map { .init(additionalProperties: Self.levels($0)) },
                permissions: change.permissions?.compactMap { Components.Schemas.Permission(rawValue: $0) },
                expiresAt: change.expires.map { .value(Self.text($0)) }, narrowOnly: true)
            return Self.info(try await client.updateKey(path: .init(id: id), body: .json(body)).ok.body.json)
        }
    }

    func revoke(_ id: String) async throws(OwnerFailure) {
        try await run { client in _ = try await client.revokeKey(path: .init(id: id)).ok }
    }

    // MARK: Addresses

    private static func settings(_ config: Components.Schemas.InstanceConfig) -> AddressSettings {
        let addresses = config.addresses ?? []
        return AddressSettings(
            instanceID: config.instanceId, signIn: config.signInAddress ?? addresses.first ?? "", addresses: addresses,
            websites: config.corsOrigins ?? [])
    }

    func addresses() async throws(OwnerFailure) -> AddressSettings {
        try await run { client in Self.settings(try await client.getConfig().ok.body.json) }
    }

    func check(signIn: String?, addresses: [String]?) async throws(OwnerFailure) -> AddressPlan {
        try await run { client in
            let answer = try await client.check(
                AddressChange(signInAddress: signIn.map { .set($0) }, addresses: addresses.map { .set($0) })
            ).answer
            let reach: AddressPlan.Reach =
                switch answer.signInAddressCheck?.passed {
                case true?: .answers
                case false?: .notAnswering(reason: answer.signInAddressCheck?.reason?.rawValue)
                case nil: signIn == nil ? .notAsked : .notChecked
                }
            return AddressPlan(
                askedSignIn: signIn, askedAddresses: addresses, signIn: answer.signInAddress, addresses: answer.addresses,
                requiresConfirmation: answer.requiresConfirmation,
                consequences: answer.consequences.map { .init(code: $0.code.rawValue, sentence: $0.sentence, count: $0.count) },
                reach: reach)
        }
    }

    func apply(_ plan: AddressPlan, instanceID: String?) async throws(OwnerFailure) -> AddressSettings {
        try await run(plainConflict: Self.configConflict) { client in
            let body = Operations.UpdateConfig.Input.Body.JsonPayload(
                addresses: plan.askedAddresses.map { .value($0) }, signInAddress: plan.askedSignIn.map { .value($0) },
                confirmSignInAddressChange: plan.requiresConfirmation ? true : nil)
            return Self.settings(
                try await client.updateConfig(headers: .init(xMarfaInstanceId: instanceID), body: .json(body)).ok.body.json)
        }
    }

    func setWebsites(_ websites: [String], instanceID: String?) async throws(OwnerFailure) -> AddressSettings {
        try await run(plainConflict: Self.configConflict) { client in
            let body = Operations.UpdateConfig.Input.Body.JsonPayload(corsOrigins: .value(websites))
            return Self.settings(
                try await client.updateConfig(headers: .init(xMarfaInstanceId: instanceID), body: .json(body)).ok.body.json)
        }
    }
}
