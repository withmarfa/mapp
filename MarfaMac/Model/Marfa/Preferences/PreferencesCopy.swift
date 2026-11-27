import Foundation
import Marfa

/// An `app.marfa-mac.preferences` item as the copy holds it.
nonisolated struct PreferencesItem: Equatable, Sendable {
    let id: String
    let version: Int64
    /// When the server made it, which picks the item the app uses where two Macs made one at once.
    let createdAt: String
    /// Whether the server made it from a write that lost a conflict (`conflicted-copy`).
    let isConflictedCopy: Bool
}

/// How far the copy is from holding the settings whole.
nonisolated struct PreferencesReadiness: Equatable, Sendable {
    /// The last hydration completed.
    var filled = false
    /// The copy's slice holds the type: the sign-in reaches it.
    var holdsType = false
    /// Every table of every item outside the bin is held whole. The copy never fills a binned item's tables.
    var tablesWhole = false
    /// The Marfa the copy follows, by its instance, which an adoption is recorded under.
    var instance: String?
}

/// What the preferences sync asks of the working copy, apart from the copy so it can be tested without one. Every
/// write is queued and shown at once, so it works offline.
nonisolated protocol PreferencesCopy: Sendable {
    /// Names this opened copy, so a write queued under another, whose answer no sync here can take, is told apart.
    var run: String { get }
    func readiness() async throws -> PreferencesReadiness
    /// The items of the type outside the bin, oldest first.
    func items() async throws -> [PreferencesItem]
    /// Whether `item` is in the bin, as removing the settings leaves it.
    func isBinned(_ item: String) async throws -> Bool
    /// The conflicted copies the server made of `item`'s writes, outside the bin.
    func conflictedCopies(of item: String) async throws -> [PreferencesItem]
    /// The settings `item` holds: each field's members and each table's rows.
    func units(of item: String) async throws -> PreferenceUnits
    /// Makes the item with these fields, and answers its id.
    func create(fields: [PreferencesField: JSONObject]) async throws -> String
    /// Writes whole fields, merged by the server against the version they were read at, and answers the queued
    /// write's id.
    func update(_ item: String, fields: [PreferencesField: JSONObject], readAt version: Int64) async throws -> String
    /// The ids of the writes the queue still holds.
    func queued() async throws -> Set<String>
    /// The answers to writes to the settings that arrived since the last take, by write.
    func answers() async -> [String: PreferenceAnswer]
    /// Writes one batch of rows to a table, all of them or none.
    func write(_ operations: [RowOperation], to table: PreferencesTable, of item: String) async throws
    /// Moves an item to the bin, and answers the id of the queued write that does it.
    func remove(_ item: String) async throws -> String
    /// Moves only these settings items to the bin on the server, all together.
    func removeFromMarfa(_ items: [String]) async throws
    /// The queued writes that move a settings item to the bin and have no answer yet.
    func pendingRemovals() async throws -> Set<String>
    /// Whether the queue holds a write the server has not answered that is not one of these items' own, such as the
    /// library's: sending the queue sends it too.
    func holdsOtherChanges(besides items: Set<String>) async throws -> Bool
    /// Sends the queue and returns once the server has taken every one of `writes`; throws where it did not. A drain
    /// sends the whole queue, so what happens to any other write does not count.
    func send(_ writes: Set<String>) async throws
    /// Each change the copy names: the item it changed, or nil for a refresh such as a fill of tables or an answer.
    func changes() -> AsyncStream<String?>
}

/// The copy's own: the package's working copy, and the answers its engine takes.
nonisolated struct WorkingCopyPreferences: PreferencesCopy {
    let copy: WorkingCopy
    let answerFeed: PreferenceAnswers
    /// Asks the library's sync to send what the copy has queued, which a write does not by itself: the sync sends when the
    /// copy reconnects and after a write of the library's own.
    let sendSoon: @Sendable () async -> Void

    init(copy: WorkingCopy, answers: PreferenceAnswers, sendSoon: @escaping @Sendable () async -> Void = {}) {
        self.copy = copy
        answerFeed = answers
        self.sendSoon = sendSoon
    }

    var run: String { answerFeed.run }

    /// The most rows a batch or a page may hold.
    static let batchLimit = 1000

    func readiness() async throws -> PreferencesReadiness {
        let status = try await MarfaEngine.asking { try await copy.status() }
        var readiness = PreferencesReadiness(
            filled: status.hydration == .complete, holdsType: status.sliceTypes.contains(PreferencesType.id),
            instance: status.instanceId)
        guard readiness.filled, readiness.holdsType else { return readiness }
        var held = try await MarfaEngine.asking { try await copy.tables.held() }
        let wanted = Set(PreferencesTable.allCases.map(\.rawValue))
        let chosen = Set(held.choices.filter { $0.type == PreferencesType.id }.map(\.table))
        if !wanted.isSubset(of: chosen) {
            for table in wanted.subtracting(chosen) {
                _ = try await MarfaEngine.asking { try await copy.tables.hold(table, ofType: PreferencesType.id) }
            }
            held = try await MarfaEngine.asking { try await copy.tables.held() }
        }
        readiness.tablesWhole = Self.tablesWhole(held.tables, of: Set(try await items().map(\.id)))
        return readiness
    }

    /// The core records an owed entry for each chosen table the item's type declares. The caller excludes binned
    /// items because the core skips their fills.
    static func tablesWhole(_ held: [HeldTable], of items: Set<String>) -> Bool {
        let wanted = Set(PreferencesTable.allCases.map(\.rawValue))
        var whole: [String: Set<String>] = [:]
        for table in held where table.state == .whole && items.contains(table.itemId) {
            whole[table.itemId, default: []].insert(table.table)
        }
        return items.allSatisfy { wanted.isSubset(of: whole[$0] ?? []) }
    }

    func items() async throws -> [PreferencesItem] {
        let rows = try await MarfaEngine.asking { try await copy.items.list(ListFilters(types: [PreferencesType.id])) }.rows
        return rows.filter { $0.state == .active }.map(Self.item).sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    private static func item(_ row: Marfa.Item) -> PreferencesItem {
        PreferencesItem(
            id: row.id, version: row.version, createdAt: row.createdAt, isConflictedCopy: row.tags.contains(MarfaProblems.conflictedCopyTag))
    }

    func isBinned(_ item: String) async throws -> Bool {
        let rows = try await MarfaEngine.asking { try await copy.items.get([item], includingBin: true) }.rows
        return rows.contains { $0.id == item && $0.state == .trashed }
    }

    func conflictedCopies(of item: String) async throws -> [PreferencesItem] {
        try await MarfaEngine.asking { try await copy.items.conflictedCopies(of: item) }.map(Self.item)
    }

    func units(of item: String) async throws -> PreferenceUnits {
        var units: PreferenceUnits = [:]
        guard let held = try await MarfaEngine.asking({ try await copy.items.get(item) }) else { return units }
        for field in PreferencesField.allCases {
            guard case .object(let members)? = held.properties[field.rawValue] else { continue }
            for member in members {
                guard let text = (try? member.value.json()).flatMap(PreferenceJSON.canonical) else { continue }
                units[.member(field, member.key)] = text
            }
        }
        for table in PreferencesTable.allCases {
            var cursor: String?
            repeat {
                let page = try await MarfaEngine.asking {
                    try await copy.tables.rows(of: item, in: table.rawValue, RowsQuery(limit: Self.batchLimit, cursor: cursor))
                }.value
                for row in page.rows {
                    guard let key = row.values["key"]?.string, let setting = row.values["setting"]?.string,
                          let value = row.values["value"]?.string
                    else { continue }
                    units[.row(table, setting: setting, key: key)] = PreferenceJSON.canonical(value) ?? value
                }
                cursor = page.nextCursor
            } while cursor != nil
        }
        return units
    }

    func create(fields: [PreferencesField: JSONObject]) async throws -> String {
        let properties = JSONObject(PreferencesField.allCases.compactMap { field in fields[field].map { (field.rawValue, .object($0)) } })
        let queued = try await MarfaEngine.asking { try await copy.items.create(Draft(type: PreferencesType.id, properties: properties)) }
        guard let id = queued.itemId else { throw MarfaError.invalid(message: "the create named no item") }
        await sendSoon()
        return id
    }

    func update(_ item: String, fields: [PreferencesField: JSONObject], readAt version: Int64) async throws -> String {
        let properties = JSONObject(PreferencesField.allCases.compactMap { field in fields[field].map { (field.rawValue, .object($0)) } })
        let queued = try await MarfaEngine.asking { try await copy.items.updateAsRead(item, Edit(properties: properties, baseVersion: version)) }
        await sendSoon()
        return queued.id
    }

    func queued() async throws -> Set<String> {
        Set(try await MarfaEngine.asking { try await copy.queue.all() }.map(\.id))
    }

    func answers() async -> [String: PreferenceAnswer] { answerFeed.take() }

    func write(_ operations: [RowOperation], to table: PreferencesTable, of item: String) async throws {
        var rest = operations[...]
        while !rest.isEmpty {
            let batch = Array(rest.prefix(Self.batchLimit))
            rest = rest.dropFirst(Self.batchLimit)
            _ = try await MarfaEngine.asking { try await copy.tables.write(batch, to: table.rawValue, of: item) }
        }
        await sendSoon()
    }

    func remove(_ item: String) async throws -> String {
        let queued = try await MarfaEngine.asking { try await copy.items.delete(item) }
        await sendSoon()
        return queued.id
    }

    func removeFromMarfa(_ items: [String]) async throws {
        guard !items.isEmpty else { return }
        let preview = try await MarfaEngine.asking { try await copy.items.previewTrash(ids: items) }
        guard preview.count == items.count, preview.items.allSatisfy({ $0.count == 1 && !$0.truncated }) else {
            throw PreferencesSync.RemovalError.takesOtherItems
        }
        _ = try await MarfaEngine.asking { try await copy.items.trash(preview) }
    }

    func pendingRemovals() async throws -> Set<String> {
        let writes = try await MarfaEngine.asking { try await copy.queue.all() }.filter { $0.kind == .deleteItem && $0.verdict == nil }
        let named = writes.compactMap(\.itemId)
        guard !named.isEmpty else { return [] }
        let rows = try await MarfaEngine.asking { try await copy.items.get(named, includingBin: true) }.rows
        let ours = Set(rows.filter { $0.type == PreferencesType.id }.map(\.id))
        return Set(writes.filter { $0.itemId.map(ours.contains) ?? false }.map(\.id))
    }

    func holdsOtherChanges(besides items: Set<String>) async throws -> Bool {
        try await MarfaEngine.asking { try await copy.queue.all() }.contains { write in
            write.verdict == nil && !write.waiting && !(write.itemId.map(items.contains) ?? false)
        }
    }

    func send(_ writes: Set<String>) async throws {
        let report = try await MarfaEngine.asking { try await copy.queue.drain() }
        let held = try await MarfaEngine.asking { try await copy.queue.all() }
        var answers: [String: Verdict?] = [:]
        for write in held { answers.updateValue(write.verdict, forKey: write.id) }
        for told in report.verdicts { answers.updateValue(told.verdict, forKey: told.id) }
        guard Self.taken(writes, answers: answers) else {
            throw MarfaError.invalid(message: "the server did not take every write asked for")
        }
    }

    /// Whether every one of `writes` was answered as applied. `answers` holds the verdict of each write the queue still
    /// holds or the drain reported; a write in neither was answered and cleared. Another write's refusal says nothing.
    static func taken(_ writes: Set<String>, answers: [String: Verdict?]) -> Bool {
        writes.allSatisfy { write in
            guard let answer = answers[write] else { return true }
            switch answer {
            case .accepted, .merged, .conflicted: return true
            default: return false
            }
        }
    }

    func changes() -> AsyncStream<String?> {
        let changes = copy.changes()
        let arrivals = answerFeed.arrivals()
        return AsyncStream { continuation in
            let task = Task {
                for await change in changes { continuation.yield(change.itemId) }
                continuation.finish()
            }
            let answered = Task {
                for await _ in arrivals { continuation.yield(nil) }
            }
            continuation.onTermination = { _ in
                task.cancel()
                answered.cancel()
            }
        }
    }
}
