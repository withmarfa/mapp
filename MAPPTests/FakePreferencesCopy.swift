import Foundation
import Marfa
@testable import MAPP

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
    private var made = 0
    private nonisolated let stream = AsyncStream<String?>.makeStream()

    func set(_ readiness: PreferencesReadiness) { readinessValue = readiness }

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
        held.filter { !$0.value.trashed }
            .map { PreferencesItem(id: $0.key, version: $0.value.version, createdAt: $0.value.createdAt, isConflictedCopy: $0.value.conflicted) }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    func units(of item: String) async throws -> PreferenceUnits { unitsHeld(item) }

    func create(fields: [PreferencesField: JSONObject]) async throws -> String {
        creates += 1
        made += 1
        let id = "item-\(made)"
        var item = Held(createdAt: "2026-06-0\(made)T00:00:00Z")
        for (field, object) in fields { item.fields[field] = Self.members(object) }
        held[id] = item
        return id
    }

    func update(_ item: String, fields: [PreferencesField: JSONObject], readAt version: Int64) async throws {
        updates.append(fields.keys.sorted { $0.rawValue < $1.rawValue })
        for (field, object) in fields { held[item]?.fields[field] = Self.members(object) }
        held[item]?.version += 1
    }

    func write(_ operations: [RowOperation], to table: PreferencesTable, of item: String) async throws {
        batches[table, default: 0] += 1
        for operation in operations {
            switch operation {
            case .put(let id?, let values):
                held[item]?.rows[table, default: [:]][id] = (values["key"]?.string ?? "", values["setting"]?.string ?? "", values["value"]?.string ?? "")
            case .delete(let id): held[item]?.rows[table]?[id] = nil
            default: break
            }
        }
    }

    func remove(_ item: String) async throws {
        removed.append(item)
        held[item]?.trashed = true
    }

    nonisolated func changes() -> AsyncStream<String?> { stream.stream }

    private static func members(_ object: JSONObject) -> [String: String] {
        var members: [String: String] = [:]
        for member in object { members[member.key] = (try? member.value.json()).flatMap(PreferenceJSON.canonical) }
        return members
    }
}
