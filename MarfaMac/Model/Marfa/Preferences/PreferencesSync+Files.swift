import Foundation

/// Export, Import and restore points: what Settings > General's Export Settings…, Import Settings… and Restore Earlier
/// Settings… call. Export and Import read and write the defaults as the sync does, for `settingsLibrary`; a restore point
/// is the app's own defaults themselves (`SettingsSnapshot`). With no Marfa connected they change this Mac only; where the
/// settings sync, what they wrote wins at the next step (`Record.winning`) for each group this Mac shares.
extension PreferencesSync {
    /// What an import or a restore did.
    nonisolated struct Applied: Equatable, Sendable {
        /// An import counts settings as they sit in the file (`PreferenceUnit`); a restore counts the defaults keys it
        /// put back, and counts each shortcut that works in any app the system refused as skipped besides.
        var applied = 0
        /// Settings left out: ones no setting of this version owns, values the setting cannot store (`SyncedSetting.accepts`),
        /// ones a setting this Mac cannot read owns where it has nowhere to set its stored value aside, and shortcuts that
        /// work in any app that the system would not register, as another app holds the keys.
        var skipped = 0
    }

    /// This Mac's settings, every section, as Export Settings… writes them (`SettingsFile.encoded()`). A setting this Mac
    /// cannot read is left out.
    func settingsFile() -> SettingsFile {
        let library = settingsLibrary
        var units: PreferenceUnits = [:]
        for setting in PreferencesMap.inFiles {
            if case .units(let held) = setting.read(defaults, library: library) { units.merge(held) { first, _ in first } }
        }
        return SettingsFile(units: units, build: build, date: .now)
    }

    /// Replaces the settings of `sections` with the file's, after saving an Import restore point; the other sections are
    /// untouched. A setting missing from a chosen section returns to its default. Every value is checked before any is
    /// written, and one the setting cannot store is skipped, leaving what this Mac held, which does not win. It runs
    /// between sync steps (`betweenSteps`), and a step then runs for the connected copy.
    ///
    /// Throws `RestorePoints.Failure.notSaved`, and changes nothing, where the restore point cannot be saved.
    @discardableResult
    func importSettings(_ file: SettingsFile, sections: Set<SettingsFile.Section>) async throws(RestorePoints.Failure) -> Applied {
        try await betweenSteps { () throws(RestorePoints.Failure) -> Applied in
            try saveRestorePoint(.import)
            return replace(sections, from: file)
        }
    }

    /// The restore points, newest first, for Restore Earlier Settings….
    func listRestorePoints() -> [RestorePoint] { restorePoints.list() }

    /// Puts this Mac's settings back exactly as `point` holds them, removing each one it lacks, after saving a point of
    /// the settings it replaces so the restore can be undone. It runs between sync steps (`betweenSteps`), and a step
    /// then runs for the connected copy.
    ///
    /// Throws `RestorePoints.Failure.unreadable` where the point cannot be read or holds a value the defaults cannot
    /// keep, and `.notSaved` where the new point cannot be saved; either way nothing changes.
    @discardableResult
    func restore(_ point: RestorePoint.ID) async throws(RestorePoints.Failure) -> Applied {
        guard let values = try restorePoints.snapshot(of: point).checked() else { throw .unreadable }
        return try await betweenSteps { () throws(RestorePoints.Failure) -> Applied in
            let domain = try saveRestorePoint(.restoring)
            SettingsSnapshot.write(values, to: defaults, domain: domain)
            replaced(PreferencesMap.synced)
            return Applied(applied: values.count, skipped: refusedShortcuts().count)
        }
    }

    /// Saves a restore point of this Mac's settings as the app's own defaults hold them, before something replaces them
    /// all, and answers the persistent domain it read. Throws `.notSaved` where that domain is not known.
    @discardableResult
    func saveRestorePoint(_ reason: RestorePoint.Reason) throws(RestorePoints.Failure) -> String {
        guard let domain else { throw .notSaved }
        try restorePoints.save(SettingsSnapshot(of: defaults, domain: domain), reason: reason, build: build)
        return domain
    }

    /// A delayed resume needs another point only if the user edited a returning setting in the meantime.
    func protectEditsBeforeResume(_ groups: Set<PreferenceGroup>) throws(RestorePoints.Failure) {
        guard let domain else { throw .notSaved }
        let current = try SettingsSnapshot(of: defaults, domain: domain)
        if let last = restorePoints.list().first(where: { $0.reason == .resumingGroup }),
           let saved = try? restorePoints.snapshot(of: last.id),
           PreferencesMap.synced.allSatisfy({ !groups.includes($0.group) || saved.values[$0.key] == current.values[$0.key] }) {
            return
        }
        try restorePoints.save(current, reason: .resumingGroup, build: build)
    }

    /// Has the stores read the defaults again after `settings` were replaced on this Mac on purpose, and marks them to
    /// win at the next step that follows the Marfa (`Record.winning`), even over another Mac's change not yet taken, but
    /// for the units `except` names by setting key, where this Mac kept what it held.
    func replaced(_ settings: [SyncedSetting], except: [String: Set<PreferenceUnit>] = [:]) {
        storesReadAgain()
        let off = instance.map(groups.off(in:)) ?? []
        let syncing = settings.filter { !off.includes($0.group) }
        guard enabled, !syncing.isEmpty else { return }
        var record = Record.read(defaults)
        var marked = record.winning ?? [:]
        for setting in syncing {
            let left = except[setting.key] ?? []
            // A unit either mark lets win still wins.
            marked[setting.key] = marked[setting.key].map { $0.intersection(left) } ?? left
        }
        record.winning = marked
        record.save(defaults)
    }

    /// Writes each setting of `sections` as the file holds it, through the writer the sync uses, once every value is
    /// checked, and has the stores read them again. Only what was written wins at the next step.
    private func replace(_ sections: Set<SettingsFile.Section>, from file: SettingsFile) -> Applied {
        let library = settingsLibrary
        let units = file.units(in: sections)
        var result = Applied()
        result.skipped = units.keys.count { unit in !PreferencesMap.inFiles.contains { $0.owns(unit) } }
        var writes: [(setting: SyncedSetting, units: PreferenceUnits, setAside: (() -> Void)?)] = []
        for setting in PreferencesMap.inFiles where sections.contains(setting.section) {
            let mine = units.filter { setting.owns($0.key) }
            var setAside: (() -> Void)?
            if setting.read(defaults, library: library) == .unreadable {
                guard let aside = setting.settingStoredAside(in: defaults) else {
                    result.skipped += mine.count
                    continue
                }
                setAside = aside
            }
            let accepted = mine.values.count(where: setting.accepts)
            result.applied += accepted
            result.skipped += mine.count - accepted
            writes.append((setting, mine, setAside))
        }
        for write in writes {
            write.setAside?()
            write.setting.write(write.units, to: defaults, library: library)
        }
        let written = writes.filter { write in PreferencesMap.synced.contains { $0.key == write.setting.key } }
        replaced(written.map(\.setting), except: Dictionary(written.map { write in
            (write.setting.key, Set(write.units.filter { !write.setting.accepts($0.value) }.keys))
        }) { first, second in first.union(second) })
        let refused = refusedShortcuts()
        let unregistered = units.count { unit, text in
            guard sections.contains(PreferencesMap.anyAppShortcuts.section), PreferencesMap.anyAppShortcuts.owns(unit),
                  PreferencesMap.anyAppShortcuts.accepts(text), case .row(_, _, let command) = unit else { return false }
            return refused.contains(command)
        }
        result.applied -= unregistered
        result.skipped += unregistered
        return result
    }
}

nonisolated private extension SyncedSetting {
    /// What sets the stored value aside under the store's own key, as a store does with what it cannot read, so it can be
    /// written over. Nil where the setting has no such key or the value is of a kind its list cannot keep, so the value
    /// must be left alone.
    func settingStoredAside(in defaults: UserDefaults) -> (() -> Void)? {
        guard let kind = setAsideKind, let stored = defaults.object(forKey: key) else { return nil }
        switch kind {
        case .data(let list):
            guard let data = (stored as? Data) ?? (stored as? String).map({ Data($0.utf8) }) else { return nil }
            return { defaults.set((defaults.array(forKey: list) as? [Data] ?? []) + [data], forKey: list) }
        case .string(let list):
            guard let text = (stored as? String) ?? (stored as? Data).flatMap({ String(data: $0, encoding: .utf8) }) else { return nil }
            return { defaults.set((defaults.stringArray(forKey: list) ?? []) + [text], forKey: list) }
        }
    }
}
