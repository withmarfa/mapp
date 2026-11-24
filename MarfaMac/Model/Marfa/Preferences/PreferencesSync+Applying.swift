import Foundation
import Marfa

extension PreferencesSync {
    /// Writes `outcome` to this Mac and the item, and records in `adopted` what both now hold, the field write that
    /// waits for its answer, and each setting a store dropped when it read it again.
    func apply(_ outcome: PreferencesMerge.Outcome, to item: PreferencesItem, local: Local, adopted: inout Record.Adopted,
               retrying: Set<PreferenceUnit>, in copy: any PreferencesCopy) async throws
    {
        // A dropped setting the Marfa has not changed keeps what the store left, so it is not set aside again.
        let kept = adopted.frozen.filter { unit, _ in !retrying.contains(unit) && outcome.merged[unit] == adopted.base[unit] }
        var written = outcome.merged.filter { PreferenceJSON.value($0.value) != nil }
        for (unit, frozen) in kept { written[unit] = frozen.left }
        try unchanged(since: local, writing: outcome.toLocal)
        let settings = writeLocal(outcome.toLocal, from: written)
        if !settings.isEmpty {
            // A store sets aside what it cannot read, such as a value a later version of the app wrote: that is no change of the
            // person's, so the Marfa keeps it and nothing deletes it or writes its field without it.
            let held = readLocal().units
            for setting in settings {
                for unit in Set(outcome.merged.keys).union(held.keys) where setting.owns(unit) && kept[unit] == nil {
                    if let value = written[unit], held[unit] != value {
                        adopted.frozen[unit] = Record.Frozen(left: held[unit])
                    } else {
                        adopted.frozen[unit] = nil
                    }
                }
            }
        }
        adopted.frozenBuild = build
        adopted.base = outcome.merged
        let fields = Self.fields(of: outcome.merged, changing: outcome.toRemote)
        if !fields.isEmpty {
            let write = try await copy.update(item.id, fields: fields, readAt: item.version)
            adopted.awaiting[write] = Record.Awaiting(
                run: copy.run, order: adopted.writes, members: Self.members(outcome.merged, in: outcome.toRemote))
            adopted.writes += 1
        }
        try await writeRows(outcome.toRemote, of: outcome.merged, to: item, in: copy)
    }

    /// Writes the settings that own `units` into the defaults as `merged` holds them, has the stores read them, and
    /// answers the settings written.
    @discardableResult
    func writeLocal(_ units: Set<PreferenceUnit>, from merged: PreferenceUnits) -> [SyncedSetting] {
        let settings = PreferencesMap.synced.filter { setting in units.contains { setting.owns($0) } }
        guard !settings.isEmpty else { return [] }
        for setting in settings { setting.write(merged, to: defaults, library: library) }
        reload()
        NotificationCenter.default.post(name: Self.appliedNotification, object: self)
        return settings
    }

    /// One batch for each table that changed: a whole row for each setting written, a delete for each one cleared.
    func writeRows(_ units: Set<PreferenceUnit>, of merged: PreferenceUnits, to item: PreferencesItem,
                   in copy: any PreferencesCopy) async throws
    {
        var operations: [PreferencesTable: [RowOperation]] = [:]
        for unit in units.sorted(by: { "\($0)" < "\($1)" }) {
            guard case .row(let table, let setting, let key) = unit else { continue }
            let id = PreferencesMerge.rowID(table, setting: setting, key: key)
            if let value = merged[unit] {
                operations[table, default: []].append(
                    .put(id: id, values: ["key": .string(key), "setting": .string(setting), "value": .string(value)]))
            } else {
                operations[table, default: []].append(.delete(id: id))
            }
        }
        for table in PreferencesTable.allCases {
            guard let batch = operations[table], !batch.isEmpty else { continue }
            try await copy.write(batch, to: table, of: item.id)
        }
    }

    /// Each field that holds a member in `changing`, whole, as `merged` holds it; a field left with no member is empty.
    static func fields(of merged: PreferenceUnits, changing: Set<PreferenceUnit>) -> [PreferencesField: JSONObject] {
        var fields: [PreferencesField: JSONObject] = [:]
        for unit in changing {
            guard case .member(let field, _) = unit, fields[field] == nil else { continue }
            let members = merged.compactMap { unit, text -> (String, JSONValue)? in
                guard case .member(field, let name) = unit, let value = try? JSONValue(json: text) else { return nil }
                return (name, value)
            }.sorted { $0.0 < $1.0 }
            fields[field] = JSONObject(members)
        }
        return fields
    }

    /// The field members of `units` that `changed` names, as `units` holds them.
    private static func members(_ units: PreferenceUnits, in changed: Set<PreferenceUnit>) -> PreferenceUnits {
        units.filter { unit, _ in
            if case .member = unit { changed.contains(unit) } else { false }
        }
    }
}
