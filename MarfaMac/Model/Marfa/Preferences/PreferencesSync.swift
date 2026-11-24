import Foundation
import Marfa
import Observation
import os

/// Keeps the app's own settings in the connected Marfa's `app.marfa-mac.preferences` item, so every Mac that connects to it uses
/// them.
///
/// The defaults stay the store the app's code reads, as this Mac's copy of the Marfa's settings, so a launch reads nothing
/// from the network. Each step compares this Mac's settings and the item's with what both held after the last step
/// (`PreferencesMerge.reconcile`): a change on this Mac is written to the item, coalesced so a slider's drag is one write,
/// and a change from another Mac is written into the defaults, and the stores read them again so open windows follow.
/// What `PreferencesMap` keeps on this Mac is never written.
///
/// Nothing is decided from a copy that is not whole: until the hydration has completed and the item's tables are held
/// whole, the defaults stay exactly as they are. Before the first write or adoption, every synced setting on this Mac is
/// kept in one value (`beforeSyncKey`) until Reset This App's Settings, so the Mac's arrangement can always be recovered.
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
        /// The sign-in does not reach the item: Allow More… asks for `PreferencesType.rootScope`, and for
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
    static let appliedNotification = Notification.Name("MarfaMac.PreferencesSync.applied")

    private(set) var standing = Standing.off(.noMarfa)
    var syncs: Bool { standing == .syncing }
    /// The connected Marfa's name, for saying where the settings are kept; nil until the server has named itself.
    var marfaName: String? { copy == nil ? nil : name() }

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored private let enabled: Bool
    @ObservationIgnored private let coalescing: Duration
    /// Has the stores read the defaults again after another Mac's settings reach them.
    @ObservationIgnored let reload: @MainActor () -> Void
    @ObservationIgnored private var copy: (any PreferencesCopy)?
    @ObservationIgnored private var name: @MainActor () -> String? = { nil }
    @ObservationIgnored private(set) var library = ""
    /// Bumped on each attach and detach, so a step that awaited across one stops.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var running = false
    /// Above zero while a removal is under way: no step runs.
    @ObservationIgnored private var holding = 0
    @ObservationIgnored private var again = false
    @ObservationIgnored private var waiting: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    /// The item the settings are in, once a step has found or made it.
    @ObservationIgnored private(set) var item: PreferencesItem?
    /// The answers taken from the copy to field writes, kept until a saved record no longer waits for them.
    @ObservationIgnored private var answered: [String: PreferenceAnswer] = [:]
    /// This app's build, which judged the settings a store dropped (`Record.Adopted.frozen`).
    @ObservationIgnored let build: String

    /// The running app's version and build.
    nonisolated static var appBuild: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "")+\(info["CFBundleVersion"] as? String ?? "")"
    }

    init(defaults: UserDefaults, enabled: Bool, coalescing: Duration = .seconds(1), build: String = PreferencesSync.appBuild,
         reload: @escaping @MainActor () -> Void) {
        self.defaults = defaults
        self.enabled = enabled
        self.coalescing = coalescing
        self.build = build
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

    /// Writes what changed on this Mac now rather than after the pause, as before the library changes or the app quits.
    func flush() async {
        guard copy != nil else { return }
        pending?.cancel()
        pending = nil
        await run()
    }

    // MARK: For Connection's section

    /// Why a removal did not go ahead or did not finish.
    nonisolated enum RemovalError: Error, Equatable {
        /// The queue holds changes that are not the settings', which sending the removal would send too.
        case otherChangesWait
        /// The server did not take the removal; it stays queued and is sent when the copy next reaches the server.
        case notTaken
    }

    /// Moves every settings item of this Marfa to the bin. The settings on this Mac stay as they are, and nothing is
    /// written to the Marfa until `startAgain()`.
    ///
    /// With `confirmed`, it returns only once the server has taken the removal, which a sign-out needs, and throws where
    /// it could not. Sending is of the whole queue, so unless the caller says it may send the library's other changes
    /// (`sendsOtherChanges`), a queue that holds any is left alone and the removal is not made: changes the person
    /// chose to discard never reach the server this way.
    func remove(confirmed: Bool = false, sendsOtherChanges: Bool = true) async throws {
        guard let copy else { return }
        let generation = generation
        pending?.cancel()
        pending = nil
        // A step under way ends first, and none starts until the items are in the bin, so none writes to a binned item
        // or sets the standing over `removed`.
        holding += 1
        defer {
            holding -= 1
            if holding == 0 { schedule(after: .milliseconds(300)) }
        }
        await run()
        guard generation == self.generation else { return }
        let held = try await copy.items()
        if confirmed, !sendsOtherChanges, try await copy.holdsOtherChanges(besides: Set(held.map(\.id))) {
            throw RemovalError.otherChangesWait
        }
        var writes: Set<String> = []
        for settings in held { writes.insert(try await copy.remove(settings.id)) }
        item = nil
        standing = .off(.removed)
        if let instance = try await copy.readiness().instance {
            var record = Record.read(defaults)
            record.marfas[instance]?.removed = true
            record.save(defaults)
        }
        if confirmed {
            do { try await copy.send(writes) } catch { throw RemovalError.notTaken }
        }
    }

    /// Whether any of the writes named (the ones a copy has not sent, as the departure question lists them) is the removal
    /// of the settings from the Marfa.
    func isRemovalWaiting(among writes: Set<String>) async -> Bool {
        guard let copy, !writes.isEmpty, let removals = try? await copy.pendingRemovals() else { return false }
        return !removals.isDisjoint(with: writes)
    }

    /// Keeps this Mac's settings in the Marfa again after they were removed: the next item is made from them, even
    /// where this Mac adopted another Marfa before.
    func startAgain() async throws {
        guard let copy, standing == .off(.removed) else { return }
        let generation = generation
        let ready = try await copy.readiness()
        guard let instance = ready.instance else { return }
        // Waits for a step under way, which saves the record it read, before the record changes.
        await run()
        guard generation == self.generation, standing == .off(.removed) else { return }
        var record = Record.read(defaults)
        record.marfas[instance] = nil
        record.restarting.insert(instance)
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

    /// One step at a time; a step asked for while one runs follows it, and the asker returns once that one has run.
    private func run() async {
        guard !running else {
            again = true
            await withCheckedContinuation { waiting.append($0) }
            return
        }
        running = true
        repeat {
            again = false
            await step()
        } while again
        running = false
        let done = waiting
        waiting = []
        for waiter in done { waiter.resume() }
    }

    /// This Mac's settings as a step read them.
    typealias Local = (units: PreferenceUnits, frozen: [SyncedSetting])

    /// The person changed a setting a step was about to write, after the step read it: the step stops and runs again.
    private struct Moved: Error {}

    private func step() async {
        guard let copy, holding == 0 else { return }
        let generation = generation
        do {
            let ready = try await copy.readiness()
            guard generation == self.generation else { return }
            guard ready.filled else { return standing = .off(.notFilled) }
            guard ready.holdsType else { return standing = .off(.needsPermission) }
            guard ready.tablesWhole, let instance = ready.instance else { return standing = .off(.notFilled) }
            let items = try await copy.items()
            answered.merge(await copy.answers()) { _, later in later }
            guard generation == self.generation else { return }
            let originals = items.filter { !$0.isConflictedCopy }
            var record = Record.read(defaults)
            let local = readLocal()
            if let adopted = record.marfas[instance] {
                if let chosen = originals.first, chosen.id == adopted.item {
                    guard let followed = try await follow(
                        chosen, from: adopted, local: local, switched: record.last != instance,
                        siblings: items.filter(\.isConflictedCopy), in: copy, generation: generation)
                    else { return }
                    record.marfas[instance] = followed
                } else if !originals.isEmpty {
                    // Two Macs made an item at once: the one made first is used from now on.
                    guard let adopted = try await adopt(originals, local: local, in: copy, generation: generation) else { return }
                    record.marfas[instance] = adopted
                } else if adopted.removed == true {
                    item = nil
                    return standing = .off(.removed)
                } else if try await copy.isBinned(adopted.item) {
                    guard generation == self.generation else { return }
                    record.marfas[instance]?.removed = true
                    record.save(defaults)
                    item = nil
                    return standing = .off(.removed)
                } else {
                    // The item went without passing through the bin, as a create discarded offline or a server
                    // restored from before leaves it: this Mac's settings are the Marfa's, so they make it again.
                    guard let made = try await create(local: local, fresh: false, in: copy, generation: generation) else { return }
                    record.marfas[instance] = made
                }
            } else {
                keepBeforeSync()
                let adopted: Record.Adopted?
                if originals.isEmpty {
                    let fresh = !record.marfas.isEmpty && !record.restarting.contains(instance)
                    adopted = try await create(local: local, fresh: fresh, in: copy, generation: generation)
                } else {
                    adopted = try await adopt(originals, local: local, in: copy, generation: generation)
                }
                guard let adopted else { return }
                record.marfas[instance] = adopted
                record.restarting.remove(instance)
            }
            record.last = instance
            record.save(defaults)
            answered = answered.filter { id, _ in record.marfas.values.contains { $0.awaiting[id] != nil } }
            standing = .syncing
        } catch is Moved {
            again = true
        } catch is CancellationError {
        } catch {
            // A read or a write the copy refused leaves everything as it was; the next change tries again.
            Telemetry.logger(.sync).error("This app's settings could not sync: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// This Mac's settings, and what each setting this Mac cannot read owns, which no step changes.
    func readLocal() -> Local {
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

    /// Throws `Moved` where a setting that owns one of `units` is no longer what the step read: a step awaits the copy
    /// between reading this Mac's settings and writing them, and the person's change is the later one.
    func unchanged(since local: Local, writing units: Set<PreferenceUnit>) throws {
        let settings = PreferencesMap.synced.filter { setting in units.contains { setting.owns($0) } }
        guard !settings.isEmpty else { return }
        let now = readLocal()
        for setting in settings {
            let read = local.units.filter { setting.owns($0.key) }
            let held = now.units.filter { setting.owns($0.key) }
            let wasUnreadable = local.frozen.contains { $0.key == setting.key }
            let isUnreadable = now.frozen.contains { $0.key == setting.key }
            if read != held || wasUnreadable != isUnreadable { throw Moved() }
        }
    }

    /// The Marfa holds no item yet: it is made from this Mac's settings. A Mac that already adopted another Marfa
    /// (`fresh`) starts the settings every Marfa shares from the app's defaults, as a new Marfa should not take another's
    /// arrangement, and keeps what it holds for this Marfa alone.
    private func create(local: Local, fresh: Bool, in copy: any PreferencesCopy, generation: Int) async throws -> Record.Adopted? {
        let own = local.units.filter { unit, _ in PreferencesMap.synced.contains { $0.isPerServer && $0.owns(unit) } }
        let start = fresh ? own : local.units
        if fresh {
            let shared = Set(local.units.keys).subtracting(own.keys)
            try unchanged(since: local, writing: shared)
            writeLocal(shared, from: [:])
        }
        let fields = Self.fields(of: start, changing: Set(start.keys))
        let id = try await copy.create(fields: fields)
        guard generation == self.generation else { return nil }
        let made = PreferencesItem(id: id, version: 0, createdAt: "", isConflictedCopy: false)
        try await writeRows(Set(start.keys), of: start, to: made, in: copy)
        item = made
        return Record.Adopted(item: id, base: start, frozenBuild: build)
    }

    /// Takes up the item made first: what it holds wins, and what it lacks is filled from the other items, then from this
    /// Mac, once. The other items are left as they are.
    private func adopt(_ originals: [PreferencesItem], local: Local, in copy: any PreferencesCopy, generation: Int) async throws
        -> Record.Adopted?
    {
        guard let chosen = originals.first else { return nil }
        let own = try await copy.units(of: chosen.id)
        var others: [PreferenceUnits] = []
        for other in originals.dropFirst() { others.append(try await copy.units(of: other.id)) }
        guard generation == self.generation else { return nil }
        let filled = PreferencesMerge.filling(own, from: others)
        _ = setAsideUnreadable(filled, base: [:])
        let frozen = local.frozen
        var outcome = PreferencesMerge.adopt(
            remote: filled, local: local.units.filter { unit, _ in !frozen.contains { $0.owns(unit) } })
        outcome.toLocal = outcome.toLocal.filter { unit in !frozen.contains { $0.owns(unit) } }
        outcome.toRemote.formUnion(Set(filled.keys).subtracting(own.keys))
        var adopted = Record.Adopted(item: chosen.id, base: [:])
        try await apply(outcome, to: chosen, local: local, adopted: &adopted, retrying: [], in: copy)
        item = chosen
        return adopted
    }

    /// The steady step: brings this Mac and the item together against what both held after the last step. After a
    /// switch from another Marfa the defaults hold that Marfa's settings, which are no change of this Mac's, so this
    /// Marfa's settings are written into them whole.
    ///
    /// A field write this Mac queued is judged by its answer, not by what reaches the copy first: until it is answered,
    /// no other Mac's value of a member it carries is taken; once the server answers that it kept another Mac's field
    /// and wrote this one to a conflicted copy, each member it carried that this Mac still holds is written again, so
    /// only the same member's later write wins.
    private func follow(_ chosen: PreferencesItem, from adopted: Record.Adopted, local: Local, switched: Bool,
                        siblings: [PreferencesItem], in copy: any PreferencesCopy, generation: Int) async throws
        -> Record.Adopted?
    {
        var adopted = adopted
        let remote = try await copy.units(of: chosen.id)
        let queued = try await copy.queued()
        var lost: PreferenceUnits = [:]
        var holding: Set<PreferenceUnit> = []
        var unheard: [String] = []
        for (id, write) in adopted.awaiting.sorted(by: { $0.value.order < $1.value.order }) {
            if let answer = answered[id] {
                if answer == .lost { lost.merge(write.members) { _, later in later } }
                adopted.awaiting[id] = nil
            } else if write.run != copy.run, !queued.contains(id) {
                unheard.append(id)
            } else {
                holding.formUnion(write.members.keys)
            }
        }
        if !unheard.isEmpty {
            // Answered while no sync could take the answer, as before a relaunch: a conflicted copy holding a member
            // this Mac sent says the write lost.
            var copies: [PreferenceUnits] = []
            for sibling in try await copy.conflictedCopies(of: chosen.id) { copies.append(try await copy.units(of: sibling.id)) }
            for id in unheard {
                guard let write = adopted.awaiting.removeValue(forKey: id) else { continue }
                lost.merge(write.members.filter { unit, value in copies.contains { $0[unit] == value } }) { _, later in later }
            }
        }
        guard generation == self.generation else { return nil }

        let base = adopted.base
        // A setting the store dropped on reading it stands as the Marfa holds it, until this Mac changes it or an app
        // that reads it runs here.
        let retrying = adopted.frozenBuild == build ? [] : Set(adopted.frozen.keys)
        var mine = switched ? base : local.units
        for (unit, frozen) in adopted.frozen where !switched {
            // The person's own change to a dropped setting is theirs to send, so it is no longer held.
            if mine[unit] == frozen.left { mine[unit] = base[unit] } else { adopted.frozen[unit] = nil }
        }
        mine.merge(setAsideUnreadable(remote, base: base)) { _, unreadable in unreadable }
        var seen = remote
        for unit in holding { seen[unit] = base[unit] }
        let unreadable = local.frozen
        var outcome = PreferencesMerge.reconcile(
            local: mine, remote: seen, base: PreferencesMerge.base(base, reclaiming: lost, local: mine, remote: seen),
            frozen: { unit in unreadable.contains { $0.owns(unit) } })
        outcome.toLocal.formUnion(retrying)
        if switched { outcome.toLocal.formUnion(Set(local.units.keys).union(outcome.merged.keys)) }
        try await apply(outcome, to: chosen, local: local, adopted: &adopted, retrying: retrying, in: copy)
        // Every write is judged above, by its answer or its conflicted copy, so the copies have nothing left to give.
        for sibling in siblings { _ = try await copy.remove(sibling.id) }
        item = chosen
        return adopted
    }

    /// Sets aside each row of `remote` whose value is not JSON and that `base` did not already hold, under its store's
    /// key, and answers every such row. They count as held on this Mac, so a step never writes over or deletes them.
    private func setAsideUnreadable(_ remote: PreferenceUnits, base: PreferenceUnits) -> PreferenceUnits {
        let unreadable = remote.filter { PreferenceJSON.value($0.value) == nil }
        for (unit, text) in unreadable where base[unit] != text {
            guard let kind = PreferencesMap.synced.first(where: { $0.owns(unit) })?.setAsideKind else { continue }
            SyncedSetting.setAside(text, in: kind, defaults)
        }
        return unreadable
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

}
