import Foundation
import Marfa
import MarfaAPI

/// An event a webhook may send, as the server names it.
nonisolated enum WebhookEvent: String, CaseIterable, Hashable, Sendable {
    case itemCreated = "item.created"
    case itemUpdated = "item.updated"
    case itemTrashed = "item.trashed"
    case itemRestored = "item.restored"
    case itemPurged = "item.purged"
    case itemStateChanged = "item.state_changed"
    case metadataChanged = "metadata.changed"
    case rowsChanged = "rows.changed"
    case edgeCreated = "edge.created"
    case edgeUpdated = "edge.updated"
    case edgeDeleted = "edge.deleted"
    case attentionRaised = "attention.raised"

    var title: String {
        switch self {
        case .itemCreated: String(localized: "Item Created")
        case .itemUpdated: String(localized: "Item Changed")
        case .itemTrashed: String(localized: "Item Deleted")
        case .itemRestored: String(localized: "Item Restored")
        case .itemPurged: String(localized: "Item Permanently Deleted")
        case .itemStateChanged: String(localized: "Item State Changed")
        case .metadataChanged: String(localized: "Tags or Extra Data Changed")
        case .rowsChanged: String(localized: "Table Rows Changed")
        case .edgeCreated: String(localized: "Relationship Added")
        case .edgeUpdated: String(localized: "Relationship Changed")
        case .edgeDeleted: String(localized: "Relationship Removed")
        case .attentionRaised: String(localized: "Needs Attention")
        }
    }

    /// One line under the event where it is not what its title says by itself.
    var line: String? {
        switch self {
        case .attentionRaised: String(localized: "Sent only while this sign-in may read the server’s status.")
        case .itemStateChanged: String(localized: "Archived, unarchived or moved to or from another state.")
        default: nil
        }
    }
}

/// A webhook as the server holds it. The signing secret is never part of it: only its last four characters.
nonisolated struct OwnerWebhook: Identifiable, Hashable, Sendable {
    /// The credential that made it, which a page groups its webhooks by.
    struct Maker: Hashable, Sendable {
        enum Kind: Hashable, Sendable { case key, app }
        var kind: Kind
        var id: String
        var name: String?
    }

    let id: String
    var url: String
    /// The event names as the server sent them, so an event this build doesn't know is kept when others change.
    var events: [String]
    /// The type, with its subtypes, or the pattern whose item events are sent; nil sends item events of every type.
    var typeFilter: String?
    /// The last four characters of the signing secret.
    var secretTail: String
    var active: Bool
    var created: Date?
    var maker: Maker?
}

nonisolated enum WebhookDeliveryStatus: Hashable, Sendable {
    case pending, succeeded, failed, canceled
}

nonisolated struct WebhookDeliveryInfo: Identifiable, Hashable, Sendable {
    let id: String
    var event: String
    var status: WebhookDeliveryStatus
    var statusCode: Int?
    var attempts: Int
    var error: String?
    var created: Date?
}

nonisolated struct NewWebhook: Hashable, Sendable {
    var url: String
    var events: [String]
    var typeFilter: String?
}

/// What a change to a webhook sends: only what is named, so a webhook changed somewhere else keeps its other fields.
nonisolated struct WebhookChange: Hashable, Sendable {
    var url: String?
    var events: [String]?
    /// `.some(nil)` sends every type.
    var typeFilter: String??
    var active: Bool?
}

/// A webhook as made: its signing secret is shown once, and never kept.
nonisolated struct CreatedWebhook: Sendable {
    let webhook: OwnerWebhook
    let secret: String
}

extension ClientOwnerCalls {
    private static func webhook(_ webhook: Components.Schemas.Webhook, maker: OwnerWebhook.Maker? = nil) -> OwnerWebhook {
        OwnerWebhook(
            id: webhook.id, url: webhook.url, events: webhook.events, typeFilter: webhook.typeFilter,
            secretTail: String(webhook.secret.suffix(4)), active: webhook.active, created: date(webhook.createdAt), maker: maker)
    }

    private static func delivery(_ delivery: Components.Schemas.WebhookDelivery) -> WebhookDeliveryInfo {
        let status: WebhookDeliveryStatus =
            switch delivery.status {
            case .pending: .pending
            case .succeeded: .succeeded
            case .failed: .failed
            case .canceled: .canceled
            }
        return WebhookDeliveryInfo(
            id: delivery.id, event: delivery.eventType, status: status, statusCode: delivery.statusCode.map { Int($0) },
            attempts: Int(delivery.attempt), error: delivery.error, created: date(delivery.createdAt))
    }

    private static func events(_ names: [String]) -> [Operations.CreateWebhook.Input.Body.JsonPayload.EventsPayloadPayload] {
        names.compactMap { .init(rawValue: $0) }
    }

    func webhooks() async throws(OwnerFailure) -> [OwnerWebhook] {
        try await run { client in
            try await client.listWebhooks().ok.body.json.data.map { read in
                let maker = read.value2.maker
                return Self.webhook(
                    read.value1,
                    maker: .init(kind: maker.kind == .app ? .app : .key, id: maker.id, name: maker.name))
            }
        }
    }

    func webhook(_ id: String) async throws(OwnerFailure) -> OwnerWebhook {
        try await run { client in
            let read = try await client.getWebhook(path: .init(id: id)).ok.body.json
            let maker = read.value2.maker
            return Self.webhook(read.value1, maker: .init(kind: maker.kind == .app ? .app : .key, id: maker.id, name: maker.name))
        }
    }

    func create(_ webhook: NewWebhook) async throws(OwnerFailure) -> CreatedWebhook {
        try await run { client in
            let body = Operations.CreateWebhook.Input.Body.JsonPayload(
                url: webhook.url, events: Self.events(webhook.events), typeFilter: webhook.typeFilter.map { .value($0) })
            let made = try await client.createWebhook(body: .json(body)).created.body.json
            return CreatedWebhook(webhook: Self.webhook(made), secret: made.secret)
        }
    }

    func change(webhook id: String, _ change: WebhookChange) async throws(OwnerFailure) -> OwnerWebhook {
        try await run { client in
            let filter: Components.Schemas.MarfaNullableMarfaInline00404e686415370f? =
                switch change.typeFilter {
                case nil: nil
                case .some(nil): .null
                case .some(let type?): .value(type)
                }
            let body = Operations.UpdateWebhook.Input.Body.JsonPayload(
                url: change.url,
                events: change.events.map { names in
                    names.compactMap { Operations.UpdateWebhook.Input.Body.JsonPayload.EventsPayloadPayload(rawValue: $0) }
                },
                typeFilter: filter, active: change.active)
            return Self.webhook(try await client.updateWebhook(path: .init(id: id), body: .json(body)).ok.body.json)
        }
    }

    func delete(webhook id: String) async throws(OwnerFailure) {
        try await run { client in _ = try await client.deleteWebhook(path: .init(id: id)).ok }
    }

    func deliveries(of webhook: String, limit: Int = 50) async throws(OwnerFailure) -> [WebhookDeliveryInfo] {
        try await run { client in
            try await client.listWebhookDeliveries(path: .init(id: webhook), query: .init(limit: limit)).ok.body.json.data
                .map(Self.delivery)
        }
    }

    func redeliver(_ delivery: String, of webhook: String) async throws(OwnerFailure) -> WebhookDeliveryInfo {
        try await run { client in
            Self.delivery(
                try await client.redeliverWebhookDelivery(path: .init(id: webhook, deliveryId: delivery)).accepted.body.json)
        }
    }
}
