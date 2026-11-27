import Foundation
import Observation

/// The words of the audit log: what an entry did, and when.
nonisolated enum ActivityWording {
    /// What an entry did, in a short sentence. An action the contract does not name is put into words from its own.
    static func what(_ action: String) -> String {
        known[action] ?? humanized(action)
    }

    private static func humanized(_ action: String) -> String {
        let words = action.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// When an entry happened: the time today, "Yesterday", or the day.
    static func when(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let date else { return "" }
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(.dateTime.hour().minute()) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        return calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(.dateTime.day().month(.abbreviated)) : date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private static let known: [String: String] = [
        "item.create": String(localized: "Made an item"),
        "item.update": String(localized: "Changed an item"),
        "item.tag": String(localized: "Tagged an item"),
        "item.untag": String(localized: "Removed a tag"),
        "item.tags.replace": String(localized: "Replaced an item’s tags"),
        "extension.set": String(localized: "Changed an item’s extension data"),
        "extension.delete": String(localized: "Removed an item’s extension data"),
        "item.transition": String(localized: "Moved an item to another status"),
        "item.delete": String(localized: "Moved an item to Recently Deleted"),
        "items.trash": String(localized: "Moved items to Recently Deleted"),
        "item.restore": String(localized: "Restored an item"),
        "item.purge": String(localized: "Permanently deleted an item"),
        "items.bulk": String(localized: "Wrote items in bulk"),
        "items.tombstones": String(localized: "Settled a source’s removed items"),
        "view.create": String(localized: "Made a view"),
        "view.update": String(localized: "Changed a view"),
        "view.delete": String(localized: "Deleted a view"),
        "folder.create": String(localized: "Made a folder"),
        "folder.update": String(localized: "Changed a folder"),
        "folder.revoke": String(localized: "Stopped syncing a folder"),
        "edge.create": String(localized: "Made a link"),
        "edge.update": String(localized: "Changed a link"),
        "edge.delete": String(localized: "Deleted a link"),
        "edges.bulk": String(localized: "Wrote links in bulk"),
        "rows.write": String(localized: "Changed table rows"),
        "rows.undo": String(localized: "Undid a table change"),
        "type.register": String(localized: "Made a type"),
        "type.replace": String(localized: "Changed a type"),
        "type.delete": String(localized: "Deleted a type"),
        "type.icon.set": String(localized: "Changed a type’s icon"),
        "type.icon.clear": String(localized: "Cleared a type’s icon"),
        "edge_type.register": String(localized: "Made a link type"),
        "edge_type.update": String(localized: "Changed a link type"),
        "edge_type.delete": String(localized: "Deleted a link type"),
        "source.update": String(localized: "Changed a source"),
        "export.run": String(localized: "Exported items"),
        "restore_archive": String(localized: "Restored an archive"),
        "blob.upload": String(localized: "Added a file"),
        "mcp.file_fetch": String(localized: "Fetched a file from a web address"),
        "items.bulk_action": String(localized: "Queued a bulk action"),
        "items.bulk_action.chunk": String(localized: "Ran part of a bulk action"),
        "items.bulk_action.cancel": String(localized: "Cancelled a bulk action"),
        "key.create": String(localized: "Made a key"),
        "key.update": String(localized: "Changed a key"),
        "key.revoke": String(localized: "Revoked a key"),
        "owner.claimed": String(localized: "Claimed this server"),
        "instance.update.started": String(localized: "Started an update"),
        "instance.clock.confirmed": String(localized: "Confirmed the clock"),
        "config.update": String(localized: "Changed the settings"),
        "webhook.create": String(localized: "Made a webhook"),
        "webhook.update": String(localized: "Changed a webhook"),
        "webhook.delete": String(localized: "Deleted a webhook"),
        "webhook.delivery.redeliver": String(localized: "Sent a webhook delivery again"),
        "connector.register": String(localized: "Registered a connector"),
        "connector.delete": String(localized: "Deleted a connector"),
        "connector_state.delete": String(localized: "Cleared a connector’s state"),
        "inbound_endpoint.create": String(localized: "Made an inbound address"),
        "inbound_endpoint.retire": String(localized: "Retired an inbound address"),
        "backup_folder.adopt": String(localized: "Adopted the backup folder"),
        "items.trash_purged": String(localized: "Emptied old items"),
        "items.feed_expired": String(localized: "Moved expired feed items to Recently Deleted"),
        "item.versions_thinned": String(localized: "Thinned old versions"),
        "item.enrich": String(localized: "Read a file’s text"),
        "keys.purged": String(localized: "Removed old revoked keys"),
        "blob.purge": String(localized: "Removed an unused file"),
        "blob.copy_struck": String(localized: "Struck a damaged file copy"),
        "blob.copy_dropped": String(localized: "Dropped a file copy"),
        "blob.copy_replicated": String(localized: "Copied a file to another store"),
        "auth.grants.purged": String(localized: "Removed old disconnected apps"),
        "auth.grant.retired": String(localized: "Retired an idle app"),
        "auth.clients.purged": String(localized: "Removed idle app registrations"),
        "auth.sign_in.success": String(localized: "Signed in"),
        "auth.sign_in.failed": String(localized: "A sign-in was refused"),
        "auth.sign_in.ended": String(localized: "Signed out"),
        "auth.client.created": String(localized: "An app registered"),
        "auth.device_code.issued": String(localized: "Issued a device code"),
        "auth.code.issued": String(localized: "Issued a sign-in code"),
        "auth.scopes.narrowed": String(localized: "Narrowed an approval"),
        "auth.grant.created": String(localized: "Approved an app"),
        "auth.grant.reused": String(localized: "Reused an approval"),
        "auth.grant.revoked": String(localized: "Disconnected an app"),
        "auth.token.issued": String(localized: "Issued an access token"),
        "auth.refresh.replayed": String(localized: "Refused a reused token"),
        "owner.password.changed": String(localized: "Changed the password"),
        "instance.setup_code.issued": String(localized: "Issued a setup code"),
        "instance.setup_code.exchanged": String(localized: "Used a setup code"),
    ]
}

/// A column of the log. The order is the page that is loaded: the server has no sort of its own.
enum ActivityColumn: Int, CaseIterable, Hashable, Sendable {
    case when, who, what, address
}

/// Which way the loaded page is listed. When starts newest first; any other column starts at A.
struct ActivityOrder: Equatable, Sendable {
    var column: ActivityColumn = .when
    var ascending = false

    /// Whether `column` is the one in force, and which way. Nil on the others, so only one heading shows a direction.
    func ascending(for column: ActivityColumn) -> Bool? {
        self.column == column ? ascending : nil
    }
}

/// The Activity page: the server's audit log, newest first, a page at a time. The server gives no count and no way back, so
/// the model keeps where each page it has shown began, and Newer returns to those.
@Observable @MainActor final class ActivityModel {
    static let pageSize = 20

    private let context: OwnerContext
    private let calls: any InstanceCalls

    var kind: ActivityKind?
    var search = ""
    var order = ActivityOrder()

    private(set) var entries: [ActivityEntry] = []
    private(set) var hasNext = false
    /// Which page is shown, from 0 for the newest.
    private(set) var pageIndex = 0
    private(set) var failure: OwnerFailure?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// Where each page shown began: the first is the newest page, which has none.
    private var starts: [String?] = [nil]
    private var next: String?
    private var generation = 0

    init(context: OwnerContext, calls: any InstanceCalls) {
        self.context = context
        self.calls = calls
    }

    /// What the filter asks for, so a page can read the log again when it changes.
    var filterKey: String { (kind?.rawValue ?? "") + "\u{0}" + search.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isFiltered: Bool { kind != nil || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The loaded page in `order`. The server's own order stays in `entries`.
    var listed: [ActivityEntry] {
        let order = order
        return entries.sorted { lhs, rhs in
            let compared = Self.compare(lhs, rhs, by: order.column)
            if compared == .orderedSame {
                // When keeps the server's order. A stable sort needs false both ways; an id tie-break would reorder equals.
                return order.column == .when ? false : lhs.id < rhs.id
            }
            let ascending = compared == .orderedAscending
            return order.ascending ? ascending : !ascending
        }
    }

    /// "Newest first" for the order the log opens in, and a short line for any other.
    var orderLabel: String {
        switch (order.column, order.ascending) {
        case (.when, false): String(localized: "Newest first")
        case (.when, true): String(localized: "Oldest first")
        case (_, true): String(localized: "A to Z")
        case (_, false): String(localized: "Z to A")
        }
    }

    /// The heading that was clicked: the same column changes direction, and a new one starts at A, or newest first for When.
    func toggleSort(_ column: ActivityColumn) {
        if order.column == column {
            order.ascending.toggle()
        } else {
            order = ActivityOrder(column: column, ascending: column != .when)
        }
    }

    /// "1 to 20" for the page shown.
    var range: String? {
        guard !entries.isEmpty else { return nil }
        let first = pageIndex * Self.pageSize + 1
        return String(localized: "\((first).formatted()) to \((first + entries.count - 1).formatted())")
    }

    /// Reads the newest page again, under the filter as it is. Where that read fails the rows of the filter before it are not
    /// kept: they would sit under the new filter's page.
    func reload() async {
        starts = [nil]
        pageIndex = 0
        await read(at: 0, clearingOnFailure: true)
    }

    /// Whether there is another page to go to, or one to come back to.
    var isPaged: Bool { hasNext || pageIndex > 0 }

    func older() async {
        guard hasNext, let next, !isLoading else { return }
        starts.append(next)
        await read(at: starts.count - 1)
    }

    func newer() async {
        guard pageIndex > 0, !isLoading else { return }
        await read(at: pageIndex - 1)
    }

    private func read(at index: Int, clearingOnFailure: Bool = false) async {
        generation += 1
        let mine = generation
        isLoading = true
        defer { if mine == generation { isLoading = false } }
        do throws(OwnerFailure) {
            let page = try await calls.activity(
                ActivityQuery(kind: kind, search: search, limit: Self.pageSize, cursor: starts[index]))
            guard mine == generation else { return }
            entries = page.entries
            next = page.next
            hasNext = page.next != nil
            pageIndex = index
            starts = Array(starts.prefix(index + 1))
            failure = nil
        } catch {
            guard mine == generation else { return }
            let refused = if case .notPermitted = error { true } else { false }
            starts = Array(starts.prefix(pageIndex + 1))
            if clearingOnFailure || refused {
                entries = []
                next = nil
                hasNext = false
            }
            failure = error
            hasLoaded = true
            await context.learn(from: error)
            return
        }
        hasLoaded = true
    }

    /// A missing date is the oldest. Who uses the name the page shows, so a missing actor is Unknown. What is those words, not the server's key.
    private static func compare(_ lhs: ActivityEntry, _ rhs: ActivityEntry, by column: ActivityColumn) -> ComparisonResult {
        switch column {
        case .when:
            let left = lhs.date ?? .distantPast
            let right = rhs.date ?? .distantPast
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        case .who:
            return who(lhs.who).localizedStandardCompare(who(rhs.who))
        case .what:
            return ActivityWording.what(lhs.action).localizedStandardCompare(ActivityWording.what(rhs.action))
        case .address:
            return (lhs.address ?? "").localizedStandardCompare(rhs.address ?? "")
        }
    }

    private static func who(_ name: String?) -> String { name ?? String(localized: "Unknown") }
}
