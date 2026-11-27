import Foundation
import Marfa

extension PreferencesSync {
    /// Writes `outcome` to this Mac and the item, and records in `adopted` what both now hold, the field write that
    /// waits for its answer, and each setting a store dropped when it read it again.
    ///
    /// `progress` is told once the defaults hold what this step wrote into them, before any write to the item, and again
    /// after each write to the item is queued: with `adopted` as it stands then, and with
    /// the units still to be written, whose base the caller keeps as it reconciled them. A write the copy refuses later then
    /// leaves a record that sends only what that write carried again, and never takes another Mac's value this step wrote
    /// into the defaults for a change of this Mac's.
    func apply(_ outcome: PreferencesMerge.Outcome, to item: PreferencesItem, local: Local, adopted: inout Record.Adopted,
               retrying: Set<PreferenceUnit>, resuming: Set<PreferenceGroup>, from remote: Remote, in copy: any PreferencesCopy,
               progress: ((Record.Adopted, Set<PreferenceUnit>) -> Void)? = nil) async throws
    {
        var outcome = outcome
        try unchanged(since: local, writing: outcome.toLocal, taking: resuming)
        if !resuming.isEmpty {
            let returning = remote.merged.filter { resuming.includes($0.key.group) }
            let replace = Set(local.units.keys.filter { resuming.includes($0.group) }).union(returning.keys)
            outcome.toLocal.formUnion(replace)
            outcome.merged.merge(returning) { _, shared in shared }
            let inherited = Set(returning.keys).subtracting(remote.first.keys)
            if !inherited.isEmpty { adopted.fromOtherItems = (adopted.fromOtherItems ?? []).union(inherited) }
        }
        // A dropped setting the Marfa has not changed keeps what the store left, so it is not set aside again.
        let before = adopted.comparisonBase
        let kept = adopted.frozen.filter { unit, _ in !retrying.contains(unit) && outcome.merged[unit] == before[unit] }
        var written = outcome.merged.filter { PreferenceJSON.value($0.value) != nil }
        for (unit, frozen) in kept { written[unit] = frozen.left }
        var refused: PreferenceUnits = [:]
        for unit in outcome.toLocal where resuming.includes(unit.group) || adopted.frozen[unit]?.rejected != nil {
            guard let value = outcome.merged[unit], kept[unit] == nil,
                  let setting = PreferencesMap.synced.first(where: { $0.owns(unit) }),
                  !setting.reader.accepts(value, unit) else { continue }
            if adopted.frozen[unit]?.rejected != value { setting.setAsideRejected(value, in: defaults) }
            refused[unit] = value
            written[unit] = local.units[unit].flatMap { setting.reader.accepts($0, unit) ? $0 : nil }
        }
        let settings = writeLocal(outcome.toLocal, from: written)
        let held = settings.isEmpty && resuming.isEmpty ? [:] : readLocal().units
        if !settings.isEmpty {
            // A store sets aside what it cannot read, such as a value a later version of the app wrote: that is no change of the
            // person's, so the Marfa keeps it and nothing deletes it or writes its field without it.
            let compared = Set(outcome.merged.keys).union(held.keys).union(outcome.toLocal)
            for setting in settings {
                for unit in compared where setting.owns(unit) && kept[unit] == nil {
                    if let value = refused[unit] {
                        adopted.frozen[unit] = Record.Frozen(left: held[unit], rejected: value)
                    } else if let value = written[unit], held[unit] != value {
                        adopted.frozen[unit] = Record.Frozen(left: held[unit], rejected: resuming.includes(unit.group) ? value : nil)
                    } else {
                        adopted.frozen[unit] = nil
                    }
                }
            }
        }
        adopted.frozenBuild = build
        adopted.base = outcome.merged
        if !resuming.isEmpty {
            // Only what survived the reload can be a shared value that this Mac later deletes.
            adopted.base = resuming.excludingFrom(adopted.base)
            adopted.base.merge(held.filter { resuming.includes($0.key.group) }) { _, value in value }
        }
        for (unit, frozen) in adopted.frozen where frozen.rejected != nil { adopted.base[unit] = nil }
        var unsent = outcome.toRemote
        if !settings.isEmpty { progress?(adopted, unsent) }
        // A field is written whole. Keep the followed item's own members outside this edit.
        var forItem = remote.first
        for unit in outcome.toRemote { forItem[unit] = outcome.merged[unit] }
        let fields = Self.fields(of: forItem, changing: outcome.toRemote)
        if !fields.isEmpty {
            let write = try await copy.update(item.id, fields: fields, readAt: item.version)
            adopted.awaiting[write] = Record.Awaiting(
                run: copy.run, order: adopted.writes, members: Self.members(outcome.merged, in: outcome.toRemote))
            adopted.writes += 1
            unsent = unsent.filter { if case .member = $0 { false } else { true } }
            adopted.fromOtherItems?.subtract(outcome.toRemote.subtracting(unsent))
            progress?(adopted, unsent)
        }
        try await writeRows(outcome.toRemote, of: outcome.merged, to: item, in: copy) { table in
            unsent = unsent.filter { if case .row(table, _, _) = $0 { false } else { true } }
            adopted.fromOtherItems?.subtract(outcome.toRemote.subtracting(unsent))
            progress?(adopted, unsent)
        }
    }

    /// Writes the settings that own `units` into the defaults as `merged` holds them, has the stores read them, and
    /// answers the settings written.
    @discardableResult
    func writeLocal(_ units: Set<PreferenceUnit>, from merged: PreferenceUnits) -> [SyncedSetting] {
        let settings = PreferencesMap.synced.filter { setting in units.contains { setting.owns($0) } }
        guard !settings.isEmpty else { return [] }
        for setting in settings { setting.write(merged, to: defaults, library: library) }
        storesReadAgain()
        return settings
    }

    /// Has the stores, and what reads the defaults only when drawn, read the defaults again after something other than
    /// a store wrote them.
    func storesReadAgain() {
        reload()
        NotificationCenter.default.post(name: Self.appliedNotification, object: self)
    }

    /// One batch for each table that changed: a whole row for each setting written, a delete for each one cleared.
    /// `written` is told of each table once its batch is queued.
    func writeRows(_ units: Set<PreferenceUnit>, of merged: PreferenceUnits, to item: PreferencesItem,
                   in copy: any PreferencesCopy, written: (PreferencesTable) -> Void = { _ in }) async throws
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
            written(table)
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
