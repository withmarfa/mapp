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

/// Export Automatically for one Marfa: how often, into which folder, and when it last ran.
nonisolated struct ExportPlan: Codable, Equatable, Sendable {
    /// The Marfa it was set for: its instance id once the app has learnt it, else only its address.
    var instance: String?
    var address: String
    var schedule: ExportSchedule
    var folder: String?
    var last: Date?

    var folderURL: URL? { folder.map { URL(filePath: $0, directoryHint: .isDirectory) } }

    /// The plan set for the Marfa at `address` whose instance id is `instance`, where the app knows it. A plan that holds
    /// an id is that Marfa's alone, at any address; one that holds none is the address's until the id is learnt.
    static func index(in plans: [ExportPlan], address: String, instance: String?) -> Int? {
        if let instance, let index = plans.firstIndex(where: { $0.instance == instance }) { return index }
        return plans.firstIndex { $0.instance == nil && $0.address == address }
    }
}

/// Export Automatically: the same archive Export Everything writes, into the folder the person chose for the Marfa that is
/// open, when one is due. Each Marfa has its own plan, so another Marfa shows Never until it is set there. It is checked at
/// launch and then about every hour while the app runs, with no background agent, so a Mac that is off or an app that is
/// closed exports at its next launch. Each distinct failure is told once, and an export never touches an earlier one
/// (`LibraryExport` removes only its own temporary file). A quit or a reset stops an export that is running.
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

    static let plansKey = "automaticExportPlans"
    /// How long the loop waits after a check that could judge, and after one that could not because the server was not there.
    static let interval: Duration = .seconds(3600)
    static let retryInterval: Duration = .seconds(60)

    /// Every Marfa's plan.
    private(set) var plans: [ExportPlan]
    /// The instance id at each address, as learnt in this run.
    private var instances: [String: String] = [:]

    private let defaults: UserDefaults
    private let marfa: () -> Marfa?
    private let tell: (String, String) -> Void
    private let now: () -> Date
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var running: (task: Task<Result<URL, LibraryExport.Failure>, Never>, partial: URL)?
    /// Raised by a reset, so an export that began before it writes nothing back.
    @ObservationIgnored private var era = 0
    /// The kind of thing last told, so the same failure, or the same lack, is not told again at every check.
    @ObservationIgnored private var told: String?
    @ObservationIgnored private var stopped = false

    init(
        defaults: UserDefaults, marfa: @escaping () -> Marfa?, tell: @escaping (String, String) -> Void,
        now: @escaping () -> Date = { .now }
    ) {
        self.defaults = defaults
        self.marfa = marfa
        self.tell = tell
        self.now = now
        plans = defaults.data(forKey: Self.plansKey).flatMap { try? JSONDecoder().decode([ExportPlan].self, from: $0) } ?? []
    }

    /// The plan of the Marfa that is open, or nil where none was set for it.
    var current: ExportPlan? {
        guard let marfa = marfa() else { return nil }
        return ExportPlan.index(in: plans, address: marfa.address, instance: instances[marfa.address]).map { plans[$0] }
    }

    /// Learns the open Marfa's instance id, so its plan is found by it, and binds to it a plan set before it was known.
    @discardableResult func learn() async -> Marfa? {
        guard let marfa = marfa() else { return nil }
        let era = era
        guard let instance = await marfa.instance(), era == self.era else { return marfa }
        instances[marfa.address] = instance
        if let index = ExportPlan.index(in: plans, address: marfa.address, instance: instance),
            plans[index].instance != instance || plans[index].address != marfa.address
        {
            plans[index].instance = instance
            plans[index].address = marfa.address
            save()
        }
        return marfa
    }

    /// Sets the open Marfa's schedule, and its folder where one is given.
    func set(_ schedule: ExportSchedule, folder: URL? = nil) {
        guard let marfa = marfa() else { return }
        let instance = instances[marfa.address]
        if let index = ExportPlan.index(in: plans, address: marfa.address, instance: instance) {
            plans[index].schedule = schedule
            if let folder { plans[index].folder = folder.path }
        } else {
            plans.append(.init(instance: instance, address: marfa.address, schedule: schedule, folder: folder?.path))
        }
        save()
    }

    /// Starts the checks, once.
    func start() {
        guard loop == nil, !stopped else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let judged = await check()
                try? await Task.sleep(for: judged ? Self.interval : Self.retryInterval)
            }
        }
    }

    /// Checks now, as a choice in Settings does, without waiting for the hour.
    func checkSoon() {
        Task { await check() }
    }

    /// Writes the archive if one is due. Answers whether it could judge: false only while the open Marfa's schedule is on
    /// and its server is not there to ask.
    @discardableResult func check() async -> Bool {
        guard running == nil, !stopped, let marfa = await learn(), running == nil, !stopped else { return true }
        let instance = instances[marfa.address]
        guard let plan = ExportPlan.index(in: plans, address: marfa.address, instance: instance).map({ plans[$0] }),
            plan.schedule != .never, let folder = plan.folderURL
        else { return true }
        guard let source = marfa.source else { return false }
        let moment = now()
        guard plan.schedule.isDue(last: plan.last, now: moment) else { return true }
        let id = UUID()
        let task = Task { () -> Result<URL, LibraryExport.Failure> in
            do throws(LibraryExport.Failure) {
                return .success(try await LibraryExport.export(from: source, serverName: marfa.name, to: folder, now: moment, id: id))
            } catch {
                return .failure(error)
            }
        }
        let era = era
        running = (task, LibraryExport.partialFile(in: folder, id: id))
        let result = await task.value
        running = nil
        guard era == self.era, !task.isCancelled else { return true }
        switch result {
        case .success:
            if let index = ExportPlan.index(in: plans, address: marfa.address, instance: instance) {
                plans[index].last = moment
                save()
            }
            told = nil
        case .failure(let failure):
            tellOnce(String(localized: "Couldn’t Export Automatically"), failure.message, kind: failure.message)
        }
        return true
    }

    /// Puts every plan back to Never, with the defaults `MacSettings.reset` cleared, and stops an export that is running so
    /// it writes nothing back.
    func reset() {
        era += 1
        plans = []
        told = nil
        running?.task.cancel()
    }

    /// Stops the checks for good and the export that is running, as the app quits. Waits up to `limit` for the export to
    /// remove its temporary file, and removes it itself after that.
    func stop(within limit: Duration) async {
        stopped = true
        loop?.cancel()
        loop = nil
        guard let running else { return }
        let task = running.task
        task.cancel()
        let ended = await withCheckedContinuation { continuation in
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
        if !ended { try? FileManager.default.removeItem(at: running.partial) }
    }

    /// Tells what happened unless it is of the `kind` told last: a failure by its line, a lack by its count.
    private func tellOnce(_ title: String, _ message: String, kind: String) {
        guard told != kind else { return }
        told = kind
        tell(title, message)
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(plans), forKey: Self.plansKey)
    }
}
