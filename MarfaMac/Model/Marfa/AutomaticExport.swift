import Foundation
import Observation

/// How often Export Automatically writes the archive.
nonisolated enum ExportSchedule: String, CaseIterable, Sendable {
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

/// Export Automatically: the same archive Export Everything writes, into the folder the person chose, when one is due. It
/// is checked at launch and then about every hour while the app runs, with no background agent, so a Mac that is off or an
/// app that is closed exports at its next launch. A failure is told once until an export succeeds, and never touches an
/// earlier export (`LibraryExport` removes only its own partial file).
@Observable @MainActor final class AutomaticExport {
    /// The server the archive comes from, given only while it can answer.
    struct Target {
        let address: String
        let name: String
        let source: any ArchiveSource
    }

    static let scheduleKey = "automaticExportSchedule"
    static let folderKey = "automaticExportFolder"
    static let lastKey = "automaticExportLast"
    /// How long the loop waits after a check that could judge, and after one that could not because the server was not there.
    static let interval: Duration = .seconds(3600)
    static let retryInterval: Duration = .seconds(60)

    /// When the last export of each server (by address) was made.
    private(set) var saved: [String: Date]

    private let defaults: UserDefaults
    private let target: () -> Target?
    private let tell: (String, String) -> Void
    private let now: () -> Date
    private var isRunning = false
    private var toldFailure = false
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(
        defaults: UserDefaults, target: @escaping () -> Target?, tell: @escaping (String, String) -> Void,
        now: @escaping () -> Date = { .now }
    ) {
        self.defaults = defaults
        self.target = target
        self.tell = tell
        self.now = now
        saved = defaults.dictionary(forKey: Self.lastKey) as? [String: Date] ?? [:]
    }

    var schedule: ExportSchedule { defaults.string(forKey: Self.scheduleKey).flatMap(ExportSchedule.init) ?? .never }
    var folder: URL? {
        defaults.string(forKey: Self.folderKey).flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// Starts the checks, once.
    func start() {
        guard loop == nil else { return }
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

    /// Writes the archive if one is due. Answers whether it could judge: false only while the schedule is on and the server
    /// is not there to ask.
    @discardableResult func check() async -> Bool {
        guard !isRunning, schedule != .never, let folder else { return true }
        guard let target = target() else { return false }
        let moment = now()
        guard schedule.isDue(last: saved[target.address], now: moment) else { return true }
        isRunning = true
        defer { isRunning = false }
        do {
            _ = try await LibraryExport.export(from: target.source, serverName: target.name, to: folder, now: moment)
            saved[target.address] = moment
            defaults.set(saved, forKey: Self.lastKey)
            toldFailure = false
        } catch {
            guard !toldFailure else { return true }
            toldFailure = true
            tell(String(localized: "Couldn’t Export Automatically"), error.message)
        }
        return true
    }
}
