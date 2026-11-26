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
/// whole, the defaults stay exactly as they are. Before a step replaces this Mac's settings at once (the first sync,
/// taking another Mac's settings, switching Marfa), it saves a restore point (`restorePoints`), and where the point
/// cannot be saved the step changes nothing and the next one tries again, so the Mac's arrangement can always be brought
/// back. A row no setting here owns, such as one a later version of the app writes, is the Marfa's: this Mac never
/// changes or deletes it.
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

    /// What each Marfa this Mac adopted held after the last step, by instance. Bookkeeping, not a setting.
    nonisolated static let recordKey = "preferencesSync"
    /// Posted after another Mac's settings reach the defaults, for what reads the defaults only when drawn.
    static let appliedNotification = Notification.Name("MarfaMac.PreferencesSync.applied")

    private(set) var standing = Standing.off(.noMarfa)
    var syncs: Bool { standing == .syncing }
    /// The connected Marfa's name, for saying where the settings are kept; nil until the server has named itself.
    var marfaName: String? { copy == nil ? nil : name() }

    @ObservationIgnored let defaults: UserDefaults
    /// The persistent domain `defaults` writes, which a restore point reads; nil where it is not known, as for a test's
    /// defaults that does not say, and then no point is saved, so nothing that needs one changes.
    @ObservationIgnored let domain: String?
    @ObservationIgnored let enabled: Bool
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
    /// Above zero while a removal, or an import, a restore or Reset, is under way: no step runs.
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
    /// The copies of this Mac's settings saved before something replaced them all.
    @ObservationIgnored let restorePoints: RestorePoints
    /// The library the settings kept for each server are read and written for while no copy is followed.
    @ObservationIgnored private let detachedLibrary: @MainActor () -> String
    /// The commands, by raw value, whose shortcut that works in any app the system refused at the stores' last reload.
    @ObservationIgnored let refusedShortcuts: @MainActor () -> Set<String>
    /// The settings, by key, that a library's earlier name still holds (`LibrarySettings.unsettled`), which no step
    /// changes on either side, so nothing deletes what has not yet moved.
    @ObservationIgnored let unsettled: @MainActor (String) -> Set<String>

    /// The running app's version and build.
    nonisolated static var appBuild: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "")+\(info["CFBundleVersion"] as? String ?? "")"
    }

    /// `library` names the library whose settings kept for each server are read and written while no copy is followed,
    /// as with no Marfa connected or a run that never syncs.
    init(defaults: UserDefaults, domain: String? = nil, enabled: Bool, coalescing: Duration = .seconds(1),
         build: String = PreferencesSync.appBuild, restorePoints: RestorePoints = .temporary(),
         library: @escaping @MainActor () -> String = { "" }, refusedShortcuts: @escaping @MainActor () -> Set<String> = { [] },
         unsettled: @escaping @MainActor (String) -> Set<String> = { _ in [] },
         reload: @escaping @MainActor () -> Void) {
        self.defaults = defaults
        self.domain = domain
        self.enabled = enabled
        self.coalescing = coalescing
        self.build = build
        self.restorePoints = restorePoints
        detachedLibrary = library
        self.refusedShortcuts = refusedShortcuts
        self.unsettled = unsettled
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

    /// The library the settings kept for each server belong to now: the followed copy's, else the connected server's.
    var settingsLibrary: String { copy == nil ? detachedLibrary() : library }

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

    // MARK: Replacing on purpose

    /// Runs `change`, which replaces settings on this Mac on purpose (an import, a restore), between steps: steps stop and
    /// one under way ends first, so none writes over what `change` writes with what it read before, or saves its record over
    /// the marks `change` makes (`replaced`). Then a step runs.
    func betweenSteps<T>(_ change: () throws(RestorePoints.Failure) -> T) async throws(RestorePoints.Failure) -> T {
        pending?.cancel()
        pending = nil
        holding += 1
        await run()
        let result = Result(catching: change)
        holding -= 1
        await flush()
        return try result.get()
    }

    /// Runs Reset's `change` between steps, as `betweenSteps` does, for a caller that does not wait: at once where no step is
    /// under way, so the stores show the defaults as this returns, and otherwise once that step ends. `notSaved` runs, and
    /// nothing changes, where `change` throws because its restore point could not be saved.
    func resetBetweenSteps(_ change: @escaping @MainActor () throws(RestorePoints.Failure) -> Void,
                           notSaved: @escaping @MainActor () -> Void) {
        guard running else {
            do { try change() } catch { return notSaved() }
            Task { await flush() }
            return
        }
        pending?.cancel()
        pending = nil
        holding += 1
        Task {
            await run()
            do { try change() } catch { notSaved() }
            holding -= 1
            await flush()
        }
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

    /// This Mac's settings as a step read them, the settings it cannot read, and the members whose value their reader
    /// rejects (`SyncedSetting.Reader`), which are left out of `units`.
    typealias Local = (units: PreferenceUnits, frozen: [SyncedSetting], rejected: Set<PreferenceUnit>)

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
            let holds = PreferenceHolds.read(defaults)
            let local = readLocal()
            if let adopted = record.marfas[instance] {
                if let chosen = originals.first, chosen.id == adopted.item {
                    guard let followed = try await follow(
                        chosen, from: adopted, of: instance, local: local, switched: record.last != instance,
                        winning: record.winning ?? [:], holds: holds, siblings: items.filter(\.isConflictedCopy), in: copy,
                        generation: generation)
                    else { return }
                    record.marfas[instance] = followed
                } else if !originals.isEmpty {
                    // Two Macs made an item at once: the one made first is used from now on.
                    try saveRestorePoint(.adoption)
                    guard let adopted = try await adopt(originals, local: local, in: copy, generation: generation) else { return }
                    record.marfas[instance] = adopted
                } else if adopted.removed == true {
                    item = nil
                    return standing = .off(.removed)
                } else if try await copy.isBinned(adopted.item) {
                    guard generation == self.generation else { return }
                    record = Record.read(defaults)
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
                try saveRestorePoint(originals.isEmpty ? .firstSync : .adoption)
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
            // This step wrote the settings marked to win that it read; a mark made since stays.
            let read = record.winning ?? [:]
            let marked = (Record.read(defaults).winning ?? [:]).filter { key, units in read[key] != units }
            record.winning = marked.isEmpty ? nil : marked
            record.save(defaults)
            took(holds)
            answered = answered.filter { id, _ in record.marfas.values.contains { $0.awaiting[id] != nil } }
            // What an earlier copy on another Mac kept for a place reaches this Mac only through the Marfa.
            EarlierPlace.readIn(in: defaults, synced: record.marfas[instance]?.base ?? [:])
            standing = .syncing
        } catch is Moved {
            again = true
        } catch is RestorePoints.Failure {
            // No point, no replace: everything stays as it was, and the next step tries again.
            Telemetry.logger(.sync).error("A restore point could not be saved, so this app's settings did not sync")
        } catch is CancellationError {
        } catch {
            // A read or a write the copy refused leaves everything as it was; the next change tries again.
            Telemetry.logger(.sync).error("This app's settings could not sync: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// This Mac's settings, and what each setting this Mac cannot read, or that has not yet moved to this library's
    /// name (`unsettled`), owns, which no step changes.
    func readLocal() -> Local {
        var units: PreferenceUnits = [:]
        var frozen: [SyncedSetting] = []
        var rejected: Set<PreferenceUnit> = []
        let held = unsettled(library)
        for setting in PreferencesMap.synced {
            if held.contains(setting.key) {
                frozen.append(setting)
                continue
            }
            switch setting.read(defaults, library: library) {
            case .units(var held):
                if let reader = setting.reader {
                    let refused = held.filter { !reader.reads($0.value) }
                    if !refused.isEmpty { reader.setAside(defaults) }
                    rejected.formUnion(refused.keys)
                    held = held.filter { refused[$0.key] == nil }
                }
                units.merge(held) { first, _ in first }
            case .unreadable: frozen.append(setting)
            }
        }
        return (units, frozen, rejected)
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
            let wasRejected = local.rejected.filter(setting.owns), isRejected = now.rejected.filter(setting.owns)
            if read != held || wasUnreadable != isUnreadable || wasRejected != isRejected { throw Moved() }
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
    /// Marfa's settings are written into them whole. Otherwise this Mac's value of each setting in `winning`
    /// (`Record.winning`) is written wherever it differs from the Marfa's, but for the units its mark leaves out. Once
    /// another Mac's values are in the defaults, and again once each write to the item is queued, the record is saved
    /// with what both hold and the marks of the settings finished cleared, so a later write the copy refuses sends only
    /// its own again, never over a change made since, and never sends another Mac's value back as this Mac's.
    ///
    /// A field write this Mac queued is judged by its answer, not by what reaches the copy first: until it is answered,
    /// no other Mac's value of a member it carries is taken; once the server answers that it kept another Mac's field
    /// and wrote this one to a conflicted copy, each member it carried that this Mac still holds is written again, so
    /// only the same member's later write wins.
    private func follow(_ chosen: PreferencesItem, from adopted: Record.Adopted, of instance: String, local: Local,
                        switched: Bool, winning: [String: Set<PreferenceUnit>], holds: [PreferenceHold],
                        siblings: [PreferencesItem], in copy: any PreferencesCopy, generation: Int) async throws
        -> Record.Adopted?
    {
        var adopted = adopted
        // The defaults hold the Marfa followed before, which this one's settings are about to replace.
        if switched { try saveRestorePoint(.switching) }
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
        // that reads it runs here. A Marfa value this Mac cannot read is no setting an app here could take.
        let retrying = adopted.frozenBuild == build
            ? [] : Set(adopted.frozen.keys.filter { unit in base[unit].map { PreferencesMap.reads(unit, $0) } ?? true })
        var mine = switched ? base : local.units
        if !switched { hold(holds, base: base, local: local, adopted: &adopted) }
        for (unit, frozen) in adopted.frozen where !switched {
            if mine[unit] == frozen.left {
                mine[unit] = base[unit]
            } else if mine[unit] == nil, let held = base[unit], !PreferencesMap.reads(unit, held) {
                // Clearing what this Mac held never deletes a value it cannot read.
                adopted.frozen[unit] = Record.Frozen(left: nil)
                mine[unit] = held
            } else {
                // The person's own change to a dropped setting is theirs to send, so it is no longer held.
                adopted.frozen[unit] = nil
            }
        }
        // A member value its reader rejects is no change of the person's: the Marfa's value, or none, is written over it.
        for unit in local.rejected where !switched { mine[unit] = base[unit] }
        // This Mac holds nothing of a row no setting here owns, which is no deletion of the person's.
        for unit in Set(remote.keys).union(base.keys) where !PreferencesMap.synced.contains(where: { $0.owns(unit) }) {
            mine[unit] = base[unit]
        }
        // Nor is a row this Mac never stored of a setting kept where absent, unless this Mac's value wins on purpose.
        let keptAbsent = PreferencesMap.synced.filter { PreferencesMap.keptWhereAbsent.contains($0.key) }
        let isKeptAbsent = { (unit: PreferenceUnit) in keptAbsent.contains { $0.owns(unit) } }
        let winsHere = { (unit: PreferenceUnit) in
            PreferencesMap.synced.contains { setting in
                setting.owns(unit) && winning[setting.key].map { !$0.contains(unit) } == true
            }
        }
        for unit in Set(remote.keys).union(base.keys) where mine[unit] == nil && isKeptAbsent(unit) && !winsHere(unit) {
            mine[unit] = base[unit]
        }
        var seen = remote
        for unit in holding { seen[unit] = base[unit] }
        let unreadable = local.frozen
        var before = PreferencesMerge.base(base, reclaiming: lost, local: mine, remote: seen)
        let won = switched ? [] : PreferencesMap.synced.filter { winning[$0.key] != nil }
        if !won.isEmpty {
            // What Reset, Import or Restore wrote wins, but never over a value this Mac holds back or does not read.
            let heldBack = Set(adopted.frozen.keys).union(local.rejected)
            before = PreferencesMerge.base(before, winning: { unit in
                !heldBack.contains(unit) && won.contains { $0.owns(unit) && winning[$0.key]?.contains(unit) == false }
            }, local: mine, remote: seen)
        }
        var outcome = PreferencesMerge.reconcile(
            local: mine, remote: seen, base: before, frozen: { unit in unreadable.contains { $0.owns(unit) } })
        outcome.toLocal.formUnion(retrying)
        if !switched {
            outcome.toLocal.formUnion(local.rejected.filter { unit in outcome.merged[unit].map { PreferencesMap.reads(unit, $0) } ?? true })
        }
        // What this Mac lacks of such a setting comes here.
        outcome.toLocal.formUnion(outcome.merged.keys.filter { unit in
            local.units[unit] == nil && isKeptAbsent(unit) && !unreadable.contains { $0.owns(unit) }
        })
        if switched {
            outcome.toLocal.formUnion(Set(local.units.keys).union(outcome.merged.keys).filter { unit in !unreadable.contains { $0.owns(unit) } })
        }
        try await apply(outcome, to: chosen, local: local, adopted: &adopted, retrying: retrying, in: copy) {
            [defaults, before] partial, unsent in
            var record = Record.read(defaults)
            var partial = partial
            // What is still to be written keeps the base it was reconciled against, so the next step decides it as this
            // one did: a member another Mac's write beat is still sent again, though its answer is taken.
            for unit in unsent { partial.base[unit] = before[unit] }
            record.marfas[instance] = partial
            // A switch wrote this Marfa's settings into the defaults before any write to the item.
            if switched { record.last = instance }
            let finished = switched ? Set(winning.keys) : Set(won.filter { !unsent.contains(where: $0.owns) }.map(\.key))
            if var marked = record.winning {
                for key in finished where marked[key] == winning[key] { marked[key] = nil }
                record.winning = marked.isEmpty ? nil : marked
            }
            record.save(defaults)
        }
        // Every write is judged above, by its answer or its conflicted copy, so the copies have nothing left to give.
        for sibling in siblings { _ = try await copy.remove(sibling.id) }
        item = chosen
        return adopted
    }

    /// Holds each row of the Marfa that this Mac lacks because a store set it aside (`PreferenceHolds`), not because
    /// the person removed it: it stays in the Marfa, as a setting the store dropped, until the person sets it here.
    private func hold(_ holds: [PreferenceHold], base: PreferenceUnits, local: Local, adopted: inout Record.Adopted) {
        for hold in holds {
            guard let setting = PreferencesMap.synced.first(where: { $0.key == hold.setting }),
                  !local.frozen.contains(where: { $0.key == setting.key })
            else { continue }
            let missing = base.keys.filter { setting.owns($0) && local.units[$0] == nil && adopted.frozen[$0] == nil }
            for unit in hold.names(missing, library: library) { adopted.frozen[unit] = Record.Frozen(left: nil) }
        }
    }

    /// Clears the holds a finished step read, now that its record keeps what they named. A hold of every library's entry
    /// of a setting kept for each server stays for the libraries not yet followed.
    private func took(_ holds: [PreferenceHold]) {
        guard !holds.isEmpty else { return }
        var left = PreferenceHolds.read(defaults)
        for hold in holds {
            guard let index = left.firstIndex(of: hold) else { continue }
            let perServer = PreferencesMap.synced.first { $0.key == hold.setting }?.isPerServer ?? false
            if !perServer || hold.library == library {
                left.remove(at: index)
            } else if hold.library == nil {
                left[index].taken = (hold.taken ?? []) + [library]
            }
        }
        PreferenceHolds.write(left, to: defaults)
    }
}
