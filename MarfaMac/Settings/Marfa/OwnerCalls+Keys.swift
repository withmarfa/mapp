import Foundation
import Marfa
import MarfaAPI

extension ClientOwnerCalls {
    // MARK: Keys

    private static func text(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    }

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
                expiresAt: change.expires.map { expiry in
                    switch expiry {
                    case .on(let date): .value(Self.text(date))
                    case .never: .null
                    }
                },
                narrowOnly: change.expires == nil ? true : nil)
            return Self.info(try await client.updateKey(path: .init(id: id), body: .json(body)).ok.body.json)
        }
    }

    func revoke(_ id: String) async throws(OwnerFailure) {
        try await run { client in _ = try await client.revokeKey(path: .init(id: id)).ok }
    }

    func identity() async throws(OwnerFailure) -> OwnIdentity {
        do {
            return try await run { client in
                let key = try await client.getCurrentKey().ok.body.json
                return OwnIdentity(keyID: key.id, expires: Self.date(key.expiresAt))
            }
        } catch {
            // A signed-in app's token is not a key, and the server says so; it has no expiry of its own as a caller.
            if case .notPermitted = error { return OwnIdentity(keyID: nil, expires: nil) }
            throw error
        }
    }
}
