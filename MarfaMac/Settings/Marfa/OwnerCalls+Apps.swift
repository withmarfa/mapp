import Foundation
import Marfa
import MarfaAPI

extension ClientOwnerCalls {
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
                    scopes: grant.scopes, vendors: grant.vendors, granted: Self.date(grant.grantedAt),
                    lastUsed: Self.date(grant.lastUsedAt))
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

    func disconnect(_ app: AppAccess, removingData: Bool) async throws(OwnerFailure) {
        try await run { client in
            try await client.disconnect(grant: app.id, data: removingData ? .remove(.ownerConfirmed) : .keep)
        }
    }

    func appData(vendor: String) async throws(OwnerFailure) -> AppData {
        try await run { client in
            let page = try await client.appData(vendor: vendor)
            return AppData(
                vendor: page.vendor,
                types: page.types.map {
                    AppData.Kind(type: $0._type, active: $0.active, archived: $0.archived, trashed: $0.trashed)
                })
        }
    }

    func removeAppData(vendor: String) async throws(OwnerFailure) -> AppDataRemoved {
        try await run { client in
            let removal = try await client.removeAppData(vendor: vendor, .ownerConfirmed)
            return AppDataRemoved(
                removedItems: removal.removedItems, remainingItems: removal.remainingItems,
                stoppedBy: removal.stoppedBy.map { Self.failure($0) })
        }
    }
}
