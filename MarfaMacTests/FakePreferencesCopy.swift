import Foundation
import Marfa
@testable import MarfaMac

/// A working copy's preferences held in memory, which a test fills, changes as another Mac would, and reads back.
actor FakePreferencesCopy: PreferencesCopy {
    struct Held {
        var version: Int64 = 1
        var createdAt: String
        var conflicted = false
        var fields: [PreferencesField: [String: String]] = [:]
        var rows: [PreferencesTable: [String: (key: String, setting: String, value: String)]] = [:]
        var trashed = false
    }

    var readinessValue = PreferencesReadiness(filled: true, holdsType: true, tablesWhole: true, instance: "instance-1")
    private(set) var held: [String: Held] = [:]
    private(set) var creates = 0
    private(set) var updates: [[PreferencesField]] = []
    private(set) var batches: [PreferencesTable: Int] = [:]
    private(set) var removed: [String] = []
    private(set) var sends = 0
    /// Whether the server takes what is sent; false stands for a server that does not answer.
    var delivers = true
    /// Writes the library queued, which the settings do not own, until a send takes them.
    private(set) var libraryWrites: Set<String> = []
    /// The library's writes a send has taken.
    private(set) var sentLibraryWrites: Set<String> = []
    /// Removals queued and not yet taken, by write id.
    private(set) var queuedRemovals: [String: String] = [:]
    /// Writes made to an item already in the bin.
    private(set) var writesToBinned = 0
    /// The item list still shows the copy's state from before the removal.
    private var showsBinnedItems = false

    func showBinnedItems(_ show: Bool) { showsBinnedItems = show }

    private var pausedItems: CheckedContinuation<Void, Never>?
    private var pausesNextItems = false
    private var isPaused = false
    private var made = 0
    private nonisolated let stream = AsyncStream<String?>.makeStream()
    /// Runs once, the next time an item's settings are read, as a person's change made while a step reads.
    private var duringRead: (@MainActor () -> Void)?
    /// The id of each field write, in the order queued.
    private(set) var writeIDs: [String] = []
    /// Whether the next field write is answered as taken the moment it is queued. A test of a conflict answers it itself.
    private var answersAtOnce = true
    private var unanswered: Set<String> = []
    private var answersHeld: [String: PreferenceAnswer] = [:]
    /// Names this opened copy; `reopen()` names another, as a relaunch does.
    private(set) nonisolated(unsafe) var runValue = "run-1"
    nonisolated var run: String { runValue }

    /// Whether the next create is refused, as a copy refuses a write, so the step tries again later.
    private var refusesNextCreate = false

    func refuseNextCreate() { refusesNextCreate = true }

    /// The table whose next batch is refused, as a copy refuses a write, after the writes before it were queued.
    private var refusesNextWrite: PreferencesTable?

    func refuseNextWrite(to table: PreferencesTable) { refusesNextWrite = table }

    /// Leaves the next field write unanswered until the test answers it.
    func holdNextAnswer() { answersAtOnce = false }

    /// The server answers a field write, and the copy tells of it.
    func answer(_ write: String, _ answer: PreferenceAnswer) {
        unanswered.remove(write)
        answersHeld[write] = answer
        stream.continuation.yield(nil)
    }

    /// The copy is opened again, as after a relaunch: answers not yet taken are gone with the engine that took them,
    /// and each unanswered write has left the queue.
    func reopen() {
        runValue = "run-\(UUID().uuidString)"
        answersHeld = [:]
        unanswered = []
    }

    /// Has `change` run the next time a step reads an item's settings.
    func whileReading(_ change: @escaping @MainActor () -> Void) { duringRead = change }

    /// The item goes from the copy without passing through the bin, as a discarded create or a restored server leaves it.
    func forget(_ id: String) { held[id] = nil }

    func set(_ readiness: PreferencesReadiness) { readinessValue = readiness }

    /// A change the person made to the library, queued and not yet sent.
    func queueLibraryWrite(_ id: String = "library-write") { libraryWrites.insert(id) }

    /// The next read of the items waits until `resume()`, as a step does while the copy answers slowly.
    func pauseNextItems() { pausesNextItems = true }

    var isHoldingItems: Bool { isPaused }

    func resume() {
        isPaused = false
        pausedItems?.resume()
        pausedItems = nil
    }

    /// An item another Mac made, with its settings.
    @discardableResult
    func add(_ units: PreferenceUnits, createdAt: String = "2026-01-01T00:00:00Z", conflicted: Bool = false) -> String {
        made += 1
        let id = "item-\(made)"
        var item = Held(createdAt: createdAt, conflicted: conflicted)
        Self.put(units, in: &item)
        held[id] = item
        return id
    }

    /// Another Mac changes `id` and the copy tells of it.
    func change(_ id: String, _ units: PreferenceUnits, removing: [PreferenceUnit] = []) {
        guard var item = held[id] else { return }
        Self.put(units, in: &item)
        for unit in removing {
            switch unit {
            case .member(let field, let name): item.fields[field]?[name] = nil
            case .row(let table, let setting, let key): item.rows[table]?[PreferencesMerge.rowID(table, setting: setting, key: key)] = nil
            }
        }
        item.version += 1
        held[id] = item
        stream.continuation.yield(id)
    }

    private static func put(_ units: PreferenceUnits, in item: inout Held) {
        for (unit, text) in units {
            switch unit {
            case .member(let field, let name): item.fields[field, default: [:]][name] = text
            case .row(let table, let setting, let key):
                item.rows[table, default: [:]][PreferencesMerge.rowID(table, setting: setting, key: key)] = (key, setting, text)
            }
        }
    }

    func unitsHeld(_ id: String) -> PreferenceUnits {
        guard let item = held[id] else { return [:] }
        var units: PreferenceUnits = [:]
        for (field, members) in item.fields { for (name, text) in members { units[.member(field, name)] = text } }
        for (table, rows) in item.rows { for row in rows.values { units[.row(table, setting: row.setting, key: row.key)] = row.value } }
        return units
    }

    var activeIDs: [String] { held.filter { !$0.value.trashed }.keys.sorted() }

    // MARK: PreferencesCopy

    func readiness() async throws -> PreferencesReadiness { readinessValue }

    func items() async throws -> [PreferencesItem] {
        if pausesNextItems {
            pausesNextItems = false
            isPaused = true
            await withCheckedContinuation { pausedItems = $0 }
        }
        return held.filter { showsBinnedItems || !$0.value.trashed }
            .map { PreferencesItem(id: $0.key, version: $0.value.version, createdAt: $0.value.createdAt, isConflictedCopy: $0.value.conflicted) }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    func isBinned(_ item: String) async throws -> Bool { held[item]?.trashed == true }

    func conflictedCopies(of item: String) async throws -> [PreferencesItem] {
        try await items().filter(\.isConflictedCopy)
    }

    func queued() async throws -> Set<String> { unanswered }

    func answers() async -> [String: PreferenceAnswer] {
        defer { answersHeld = [:] }
        return answersHeld
    }

    func units(of item: String) async throws -> PreferenceUnits {
        if let change = duringRead {
            duringRead = nil
            await change()
        }
        return unitsHeld(item)
    }

    func create(fields: [PreferencesField: JSONObject]) async throws -> String {
        if refusesNextCreate {
            refusesNextCreate = false
            throw MarfaError.invalid(message: "the copy refused the create")
        }
        creates += 1
        made += 1
        let id = "item-\(made)"
        var item = Held(createdAt: "2026-06-0\(made)T00:00:00Z")
        for (field, object) in fields { item.fields[field] = Self.members(object) }
        held[id] = item
        return id
    }

    func update(_ item: String, fields: [PreferencesField: JSONObject], readAt version: Int64) async throws -> String {
        updates.append(fields.keys.sorted { $0.rawValue < $1.rawValue })
        if held[item]?.trashed == true { writesToBinned += 1 }
        let write = "write-\(writeIDs.count + 1)"
        writeIDs.append(write)
        for (field, object) in fields { held[item]?.fields[field] = Self.members(object) }
        held[item]?.version += 1
        if answersAtOnce { answersHeld[write] = .taken } else { unanswered.insert(write) }
        answersAtOnce = true
        return write
    }

    func write(_ operations: [RowOperation], to table: PreferencesTable, of item: String) async throws {
        if refusesNextWrite == table {
            refusesNextWrite = nil
            throw MarfaError.invalid(message: "the copy refused the write")
        }
        batches[table, default: 0] += 1
        if held[item]?.trashed == true { writesToBinned += 1 }
        for operation in operations {
            switch operation {
            case .put(let id?, let values):
                held[item]?.rows[table, default: [:]][id] = (values["key"]?.string ?? "", values["setting"]?.string ?? "", values["value"]?.string ?? "")
            case .delete(let id): held[item]?.rows[table]?[id] = nil
            default: break
            }
        }
    }

    func remove(_ item: String) async throws -> String {
        removed.append(item)
        held[item]?.trashed = true
        let write = "removal-\(removed.count)"
        queuedRemovals[write] = item
        return write
    }

    func pendingRemovals() async throws -> Set<String> { Set(queuedRemovals.keys) }

    func holdsOtherChanges(besides items: Set<String>) async throws -> Bool { !libraryWrites.isEmpty }

    /// A send takes the whole queue, as a drain does, when the server answers.
    func send(_ writes: Set<String>) async throws {
        sends += 1
        guard delivers else { throw MarfaError.invalid(message: "the server did not answer") }
        sentLibraryWrites.formUnion(libraryWrites)
        libraryWrites = []
        queuedRemovals = [:]
    }

    func setDelivers(_ delivers: Bool) { self.delivers = delivers }

    nonisolated func changes() -> AsyncStream<String?> { stream.stream }

    private static func members(_ object: JSONObject) -> [String: String] {
        var members: [String: String] = [:]
        for member in object { members[member.key] = (try? member.value.json()).flatMap(PreferenceJSON.canonical) }
        return members
    }
}
