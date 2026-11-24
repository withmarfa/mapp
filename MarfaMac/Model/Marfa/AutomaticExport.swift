import Foundation
import Observation

/// How often Export Automatically writes the archive.
nonisolated enum ExportSchedule: String, CaseIterable, Codable, Sendable {
    case never, daily, weekly

    /// Whether an export is due: none is made for `never`, and one is made at once where none was made yet.
    func isDue(last: Date?, now: Date) -> Bool {
        let interval: TimeInterval
        switch self {
        case .never: return false
        case .daily: interval = 24 * 3600
        case .weekly: interval = 7 * 24 * 3600
        }
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval
    }
}

/// Export Automatically for one Marfa, known by its instance id: how often, into which folder, and when it last ran.
nonisolated struct ExportPlan: Codable, Equatable, Sendable {
    var instance: String
    var schedule: ExportSchedule
    /// The folder as it was when chosen, so an export never writes to a folder moved or replaced since.
    var folder: ExportFolder?
    var last: Date?
    /// Changes at every choice, so an export begun under an earlier choice writes nothing back.
    var revision = UUID()
}

/// Export Automatically: the same archive Export Everything writes, into the folder the person chose for the Marfa that is
/// open, when one is due. A plan belongs to one Marfa by its instance id, so another Marfa shows Never until it is set
/// there, and an archive of another Marfa is never saved under it. It is checked at launch and then about every hour while
/// the app runs, with no background agent, so a Mac that is off or an app that is closed exports at its next launch; until
/// the copy knows its instance id or the server answers, it checks again within a minute, also after a choice in Settings.
/// A folder moved or replaced since it was chosen receives nothing until it is chosen again. Each kind of failure is told
/// once until an export succeeds. Reset, a restore that changes the plans, Quit and a new choice close the running
/// export's gate, waiting at most for a move under way, and prevent it from updating the plan.
@Observable @MainActor final class AutomaticExport {
    /// The Marfa that is open.
    struct Marfa {
        let address: String
        let name: String
        /// Its instance id, as the copy on this Mac knows it.
        let instance: () async -> String?
        /// The archive, given only while the server can answer.
        let source: (any ArchiveSource)?
    }

    private struct Running {
        let gate: ExportGate
        let task: Task<Result<LibraryExport.Exported, LibraryExport.Failure>, Never>
        let instance: String
        let revision: UUID
    }

    static let plansKey = "automaticExportPlans"
    /// How long the loop waits after a check that could judge, and after one that could not because the Marfa's id or its
    /// server was not there yet.
    static let interval: Duration = .seconds(3600)
    static let retryInterval: Duration = .seconds(30)

    /// Every Marfa's plan.
    private(set) var plans: [ExportPlan]
    /// The instance id at each address, as learnt in this run.
    private var instances: [String: String] = [:]

    private let defaults: UserDefaults
    private let marfa: () -> Marfa?
    private let tell: (String, String) -> Void
    private let now: () -> Date
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var running: Running?
    /// Raised by a reset, so a check that began before it does nothing.
    @ObservationIgnored private var era = 0
    /// Every kind of failure told since the last export that was saved, and the lack of the last one saved.
    @ObservationIgnored private var told: Set<String> = []
    @ObservationIgnored private var stopped = false

    init(
        defaults: UserDefaults, marfa: @escaping () -> Marfa?, tell: @escaping (String, String) -> Void,
        now: @escaping () -> Date = { .now }
    ) {
        self.defaults = defaults
        self.marfa = marfa
        self.tell = tell
        self.now = now
        plans = Self.plans(in: defaults)
    }

    private static func plans(in defaults: UserDefaults) -> [ExportPlan] {
        defaults.data(forKey: plansKey).flatMap { try? JSONDecoder().decode([ExportPlan].self, from: $0) } ?? []
    }

    /// Reads the plans again, as a restore or a settings file wrote them. Where they changed, a running export stops, as
    /// for Reset, so it never writes its time over a restored plan. A sync that left them as they were changes nothing.
    func reload() {
        let read = Self.plans(in: defaults)
        guard read != plans else { return }
        plans = read
        if let running { stop(running) }
    }

    /// The open Marfa's instance id, once learnt.
    var openInstance: String? { marfa().flatMap { instances[$0.address] } }

    /// The plan of the Marfa that is open, or nil where none was set for it.
    var current: ExportPlan? { openInstance.flatMap(plan(for:)) }

    /// Learns the open Marfa's instance id. Answers nil where the copy can't tell it yet, or where a reset or another Marfa
    /// came while it asked.
    @discardableResult func learn() async -> String? {
        guard let marfa = marfa() else { return nil }
        let era = era
        guard let instance = await marfa.instance(), era == self.era, self.marfa()?.address == marfa.address else { return nil }
        instances[marfa.address] = instance
        return instance
    }

    /// Sets the schedule of the Marfa `instance`, and its folder where one is given, while it is the one open. An export
    /// running under its earlier choice stops.
    func set(_ schedule: ExportSchedule, folder: ExportFolder? = nil, for instance: String) {
        guard openInstance == instance else { return }
        if let index = plans.firstIndex(where: { $0.instance == instance }) {
            plans[index].schedule = schedule
            if let folder { plans[index].folder = folder }
            plans[index].revision = UUID()
        } else {
            plans.append(.init(instance: instance, schedule: schedule, folder: folder))
        }
        save()
        if let running, running.instance == instance { stop(running) }
    }

    /// Starts the checks, once.
    func start() {
        guard loop == nil, !stopped else { return }
        checkLoop(after: .zero)
    }

    /// Checks after `delay`, and then again after the hour, or soon where the check could not judge.
    private func checkLoop(after delay: Duration) {
        loop?.cancel()
        loop = Task { [weak self] in
            var delay = delay
            while true {
                if delay > .zero {
                    do { try await Task.sleep(for: delay) } catch { return }
                }
                guard let self, !Task.isCancelled else { return }
                delay = await check() ? Self.interval : Self.retryInterval
            }
        }
    }

    /// Checks now, as a choice in Settings does, without waiting for the hour. Where it could not judge, the checks
    /// started at launch come again after the short retry.
    func checkSoon() {
        Task {
            guard !(await check()), loop != nil, !stopped else { return }
            checkLoop(after: Self.retryInterval)
        }
    }

    /// Writes the archive if one is due. Answers whether it could judge: false while a plan is on and the open Marfa's
    /// instance id or its server is not there yet, or the server did not answer, so the loop asks again soon.
    @discardableResult func check() async -> Bool {
        guard running == nil, !stopped, plans.contains(where: { $0.schedule != .never }) else { return true }
        let era = era
        guard let address = marfa()?.address else { return false }
        guard let instance = await learn() else { return era != self.era }
        // A reset, a quit, another Marfa or another check while the id was asked ends this one.
        guard era == self.era, running == nil, !stopped, let marfa = marfa(), marfa.address == address,
            let plan = plan(for: instance), plan.schedule != .never, let folder = plan.folder
        else { return true }
        let moment = now()
        guard plan.schedule.isDue(last: plan.last, now: moment) else { return true }
        guard let source = marfa.source else { return false }
        let gate = ExportGate()
        let task = Task { () -> Result<LibraryExport.Exported, LibraryExport.Failure> in
            do throws(LibraryExport.Failure) {
                return .success(
                    try await LibraryExport.export(
                        from: source, serverName: marfa.name, to: folder.url, expecting: folder, now: moment, instance: instance,
                        gate: gate))
            } catch {
                return .failure(error)
            }
        }
        running = Running(gate: gate, task: task, instance: instance, revision: plan.revision)
        let result = await task.value
        running = nil
        guard era == self.era, !gate.isClosed,
            let index = plans.firstIndex(where: { $0.instance == instance && $0.revision == plan.revision })
        else { return true }
        switch result {
        case .success(let exported):
            plans[index].last = moment
            save()
            // A saved export ends every failure told; a lack stays told until its count changes.
            told = exported.notCarried > 0 ? told.filter { $0 == "lacking \(exported.notCarried)" } : []
            if let lack = LibraryExport.lacking(exported, serverName: marfa.name) {
                let line = String(localized: "Saved “\(exported.file.lastPathComponent)” in “\(folder.url.lastPathComponent)”.") + " " + lack
                tellOnce(String(localized: "Exported Without Some Files"), line, kind: "lacking \(exported.notCarried)")
            }
        case .failure(let failure):
            tellOnce(String(localized: "Couldn’t Export Automatically"), failure.message, kind: failure.message)
            if failure.unreachable { return false }
        }
        return true
    }

    /// Puts every plan back to Never, with the defaults `MacSettings.reset` cleared.
    func reset() {
        era += 1
        plans = []
        told = []
        if let running { stop(running) }
    }

    /// Stops the checks and cancels the running export. Waits up to `limit` for the task to finish before quitting.
    func stop(within limit: Duration) async {
        stopped = true
        loop?.cancel()
        loop = nil
        guard let running else { return }
        stop(running)
        let task = running.task
        _ = await withCheckedContinuation { continuation in
            let first = Libraries.FirstOf()
            Task {
                _ = await task.value
                first.resume(continuation, with: true)
            }
            Task {
                try? await Task.sleep(for: limit)
                first.resume(continuation, with: false)
            }
        }
    }

    private func stop(_ running: Running) {
        running.gate.close()
        running.task.cancel()
    }

    private func plan(for instance: String) -> ExportPlan? {
        plans.first { $0.instance == instance }
    }

    /// Tells what happened unless a thing of the same `kind` was told since the last export saved.
    private func tellOnce(_ title: String, _ message: String, kind: String) {
        guard told.insert(kind).inserted else { return }
        tell(title, message)
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(plans), forKey: Self.plansKey)
    }
}
