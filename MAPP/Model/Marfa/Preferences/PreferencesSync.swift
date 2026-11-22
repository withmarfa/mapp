import Foundation
import Marfa
import Observation
import os

/// Keeps MAPP's own settings in the connected Marfa's `app.mapp.preferences` item, so every Mac that connects to it uses
/// them.
///
/// The defaults stay the store MAPP's code reads, as this Mac's copy of the Marfa's settings, so a launch reads nothing
/// from the network. Each step compares this Mac's settings and the item's with what both held after the last step
/// (`PreferencesMerge.reconcile`): a change on this Mac is written to the item, coalesced so a slider's drag is one write,
/// and a change from another Mac is written into the defaults, and the stores read them again so open windows follow.
/// What `PreferencesMap` keeps on this Mac is never written.
///
/// Nothing is decided from a copy that is not whole: until the hydration has completed and the item's tables are held
/// whole, the defaults stay exactly as they are. Before the first write or adoption, every synced setting on this Mac is
/// kept in one value (`beforeSyncKey`) until Reset MAPP's Settings, so the Mac's arrangement can always be recovered.
@Observable @MainActor
final class PreferencesSync {
    nonisolated enum Standing: Equatable, Sendable {
        case syncing
        case off(Reason)
    }

    /// Why the settings are not syncing.
    nonisolated enum Reason: Equatable, Sendable {
        /// No Marfa is connected, or this run never syncs (the sample library, the test host, previews).
        case noMarfa
        /// The sign-in does not reach the item: Allow More… asks for `PreferencesType.vendorScope`, and for
        /// `PreferencesType.registeringScope` where the Marfa holds no settings yet.
        case needsPermission
        /// The copy is still filling, or the item's tables are not whole yet.
        case notFilled
        /// The settings were removed from this Marfa, here or on another Mac. Nothing is written until `startAgain()`.
        case removed
    }

    /// Every synced setting as it was on this Mac before the first sync, as JSON by defaults key.
    nonisolated static let beforeSyncKey = "preferencesBeforeSync"
    /// What each Marfa this Mac adopted held after the last step, by instance. Bookkeeping, not a setting.
    nonisolated static let recordKey = "preferencesSync"
    /// Posted after another Mac's settings reach the defaults, for what reads the defaults only when drawn.
    static let appliedNotification = Notification.Name("MAPP.PreferencesSync.applied")

    private(set) var standing = Standing.off(.noMarfa)
    var syncs: Bool { standing == .syncing }
    /// The connected Marfa's name, for saying where the settings are kept; nil until the server has named itself.
    var marfaName: String? { copy == nil ? nil : name() }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let enabled: Bool
    @ObservationIgnored private let coalescing: Duration
    /// Has the stores read the defaults again after another Mac's settings reach them.
    @ObservationIgnored private let reload: @MainActor () -> Void
    @ObservationIgnored private var copy: (any PreferencesCopy)?
    @ObservationIgnored private var name: @MainActor () -> String? = { nil }
    @ObservationIgnored private var library = ""
    /// Bumped on each attach and detach, so a step that awaited across one stops.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var again = false
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    /// The item the settings are in, once a step has found or made it.
    @ObservationIgnored private(set) var item: PreferencesItem?

    init(defaults: UserDefaults, enabled: Bool, coalescing: Duration = .seconds(1), reload: @escaping @MainActor () -> Void) {
        self.defaults = defaults
        self.enabled = enabled
        self.coalescing = coalescing
        self.reload = reload
        guard enabled else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule(after: self?.coalescing ?? .seconds(1)) }
        }
    }

    // MARK: Attaching

    /// Follows `copy`, the open library's, whose settings are kept for `library` where a setting is kept per server.
    func attach(_ copy: any PreferencesCopy, library: String, name: @escaping @MainActor () -> String?) {
        detach()
        guard enabled else { return }
        generation += 1
        self.copy = copy
        self.library = library
        self.name = name
        standing = .off(.notFilled)
        let changes = copy.changes()
        listening = Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                self.schedule(after: .milliseconds(300))
            }
        }
        schedule(after: .zero)
    }

    func detach() {
        generation += 1
        listening?.cancel()
        listening = nil
        pending?.cancel()
        pending = nil
        copy = nil
        item = nil
        standing = .off(.noMarfa)
    }

    /// Writes what changed on this Mac now rather than after the pause, as before the library changes or MAPP quits.
    func flush() async {
        guard copy != nil else { return }
        pending?.cancel()
        pending = nil
        await run()
    }

    // MARK: For Connection's section

    /// Moves every settings item of this Marfa to the bin. The settings on this Mac stay as they are, and nothing is
    /// written to the Marfa until `startAgain()`.
    func remove() async throws {
        guard let copy else { return }
        for held in try await copy.items() { try await copy.remove(held.id) }
        item = nil
        standing = .off(.removed)
    }

    /// Keeps this Mac's settings in the Marfa again after they were removed.
    func startAgain() async throws {
        guard let copy, standing == .off(.removed) else { return }
        let ready = try await copy.readiness()
        guard let instance = ready.instance else { return }
        var record = Record.read(defaults)
        record.marfas[instance] = nil
        record.save(defaults)
        await run()
    }

    // MARK: Steps

    private func schedule(after delay: Duration) {
        guard copy != nil, pending == nil else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            await self.run()
        }
    }

    /// One step at a time; a step asked for while one runs follows it.
    private func run() async {
        guard !running else {
            again = true
            return
        }
        running = true
        repeat {
            again = false
            await step()
        } while again
        running = false
    }

    private func step() async {
        guard let copy else { return }
        let generation = generation
        do {
            let ready = try await copy.readiness()
            guard generation == self.generation else { return }
            guard ready.filled else { return standing = .off(.notFilled) }
            guard ready.holdsType else { return standing = .off(.needsPermission) }
            guard ready.tablesWhole, let instance = ready.instance else { return standing = .off(.notFilled) }
            let items = try await copy.items()
            guard generation == self.generation else { return }
            let originals = items.filter { !$0.isConflictedCopy }
            var record = Record.read(defaults)
            let local = readLocal()
            if let adopted = record.marfas[instance] {
                guard let chosen = originals.first else {
                    item = nil
                    return standing = .off(.removed)
                }
                if chosen.id == adopted.item {
                    let siblings = items.filter(\.isConflictedCopy)
                    let base = try await follow(
                        chosen, from: adopted.base, local: local, switched: record.last != instance, siblings: siblings,
                        in: copy, generation: generation)
                    guard let base else { return }
                    record.marfas[instance]?.base = base
                } else {
                    // Two Macs made an item at once: the one made first is used from now on.
                    guard let base = try await adopt(originals, local: local, in: copy, generation: generation) else { return }
                    record.marfas[instance] = Record.Adopted(item: chosen.id, base: base)
                }
            } else {
                keepBeforeSync()
                let base: PreferenceUnits?
                if originals.isEmpty {
                    base = try await create(local: local, fresh: !record.marfas.isEmpty, in: copy, generation: generation)
                } else {
                    base = try await adopt(originals, local: local, in: copy, generation: generation)
                }
                guard let base, let item else { return }
                record.marfas[instance] = Record.Adopted(item: item.id, base: base)
            }
            record.last = instance
            record.save(defaults)
            standing = .syncing
        } catch is CancellationError {
        } catch {
            // A read or a write the copy refused leaves everything as it was; the next change tries again.
            Telemetry.logger(.sync).error("MAPP's settings could not sync: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// This Mac's settings, and what each setting this Mac cannot read owns, which no step changes.
    private func readLocal() -> (units: PreferenceUnits, frozen: [SyncedSetting]) {
        var units: PreferenceUnits = [:]
        var frozen: [SyncedSetting] = []
        for setting in PreferencesMap.synced {
            switch setting.read(defaults, library: library) {
            case .units(let held): units.merge(held) { first, _ in first }
            case .unreadable: frozen.append(setting)
            }
        }
        return (units, frozen)
    }

    /// The Marfa holds no item yet. A Mac that never synced makes it from its own settings; one that already adopted
    /// another Marfa starts from MAPP's defaults, as a new Marfa should not take another's arrangement.
    private func create(local: (units: PreferenceUnits, frozen: [SyncedSetting]), fresh: Bool, in copy: any PreferencesCopy,
                        generation: Int) async throws -> PreferenceUnits?
    {
        let start = fresh ? [:] : local.units
        if fresh { writeLocal(Set(local.units.keys), from: [:]) }
        let fields = Self.fields(of: start, changing: Set(start.keys))
        let id = try await copy.create(fields: fields)
        guard generation == self.generation else { return nil }
        let made = PreferencesItem(id: id, version: 0, createdAt: "", isConflictedCopy: false)
        try await writeRows(Set(start.keys), of: start, to: made, in: copy)
        item = made
        return start
    }

    /// Takes up the item made first: what it holds wins, and what it lacks is filled from the other items, then from this
    /// Mac, once. The other items are left as they are.
    private func adopt(_ originals: [PreferencesItem], local: (units: PreferenceUnits, frozen: [SyncedSetting]),
                       in copy: any PreferencesCopy, generation: Int) async throws -> PreferenceUnits?
    {
        guard let chosen = originals.first else { return nil }
        let own = try await copy.units(of: chosen.id)
        var others: [PreferenceUnits] = []
        for other in originals.dropFirst() { others.append(try await copy.units(of: other.id)) }
        guard generation == self.generation else { return nil }
        let filled = PreferencesMerge.filling(own, from: others)
        let frozen = local.frozen
        var outcome = PreferencesMerge.adopt(
            remote: filled, local: local.units.filter { unit, _ in !frozen.contains { $0.owns(unit) } })
        outcome.toLocal = outcome.toLocal.filter { unit in !frozen.contains { $0.owns(unit) } }
        outcome.toRemote.formUnion(Set(filled.keys).subtracting(own.keys))
        try await apply(outcome, to: chosen, in: copy)
        item = chosen
        return outcome.merged
    }

    /// The steady step: brings this Mac and the item together against what both held after the last step. After a
    /// switch from another Marfa the defaults hold that Marfa's settings, which are no change of this Mac's, so this
    /// Marfa's settings are written into them whole.
    private func follow(_ chosen: PreferencesItem, from base: PreferenceUnits, local: (units: PreferenceUnits, frozen: [SyncedSetting]),
                        switched: Bool, siblings: [PreferencesItem], in copy: any PreferencesCopy, generation: Int) async throws
        -> PreferenceUnits?
    {
        let remote = try await copy.units(of: chosen.id)
        var conflicted: PreferenceUnits = [:]
        for sibling in siblings {
            conflicted.merge(try await copy.units(of: sibling.id).filter { if case .member = $0.key { true } else { false } }) { first, _ in first }
        }
        guard generation == self.generation else { return nil }
        let mine = switched ? base : local.units
        let frozen = local.frozen
        var outcome = PreferencesMerge.reconcile(
            local: mine, remote: remote,
            base: PreferencesMerge.base(base, reclaiming: conflicted, local: mine, remote: remote),
            frozen: { unit in frozen.contains { $0.owns(unit) } })
        if switched { outcome.toLocal.formUnion(Set(local.units.keys).union(outcome.merged.keys)) }
        try await apply(outcome, to: chosen, in: copy)
        // The members a conflicted copy held are written again above, so the copy has nothing left to give.
        for sibling in siblings { try await copy.remove(sibling.id) }
        item = chosen
        return outcome.merged
    }

    // MARK: Writing

    private func apply(_ outcome: PreferencesMerge.Outcome, to item: PreferencesItem, in copy: any PreferencesCopy) async throws {
        writeLocal(outcome.toLocal, from: outcome.merged)
        let fields = Self.fields(of: outcome.merged, changing: outcome.toRemote)
        if !fields.isEmpty { try await copy.update(item.id, fields: fields, readAt: item.version) }
        try await writeRows(outcome.toRemote, of: outcome.merged, to: item, in: copy)
    }

    /// Writes the settings that own `units` into the defaults as `merged` holds them, and has the stores read them.
    private func writeLocal(_ units: Set<PreferenceUnit>, from merged: PreferenceUnits) {
        let settings = PreferencesMap.synced.filter { setting in units.contains { setting.owns($0) } }
        guard !settings.isEmpty else { return }
        for setting in settings { setting.write(merged, to: defaults, library: library) }
        reload()
        NotificationCenter.default.post(name: Self.appliedNotification, object: self)
    }

    /// One batch for each table that changed: a whole row for each setting written, a delete for each one cleared.
    private func writeRows(_ units: Set<PreferenceUnit>, of merged: PreferenceUnits, to item: PreferencesItem,
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

    /// Keeps every synced setting this Mac holds, once, before anything changes it.
    private func keepBeforeSync() {
        guard defaults.object(forKey: Self.beforeSyncKey) == nil else { return }
        var kept: [String: Any] = [:]
        for key in PreferencesMap.syncedKeys {
            if let value = defaults.object(forKey: key) { kept[key] = PreferenceJSON.json(fromDefaults: value) }
        }
        defaults.set(PreferenceJSON.text(kept) ?? "{}", forKey: Self.beforeSyncKey)
    }

    // MARK: Record

    /// What this Mac knows of each Marfa it adopted, and which it followed last.
    nonisolated struct Record: Codable, Equatable, Sendable {
        struct Adopted: Codable, Equatable, Sendable {
            var item: String
            var base: PreferenceUnits
        }

        var marfas: [String: Adopted] = [:]
        var last: String?

        static func read(_ defaults: UserDefaults) -> Record {
            defaults.data(forKey: PreferencesSync.recordKey).flatMap { try? JSONDecoder().decode(Record.self, from: $0) } ?? Record()
        }

        /// Writes only a change, since every write to the defaults asks for another step.
        func save(_ defaults: UserDefaults) {
            guard self != Record.read(defaults), let data = try? JSONEncoder().encode(self) else { return }
            defaults.set(data, forKey: PreferencesSync.recordKey)
        }
    }
}
