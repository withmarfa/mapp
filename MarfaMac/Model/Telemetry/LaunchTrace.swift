import Darwin
import Foundation
import os
import Synchronization

/// How long launch takes, milestone by milestone, from the moment the process began, so the time before `main`
/// counts. Each milestone is a signpost event and the whole is one log line in `launch`, written when the first
/// window shows and the library has either loaded or had nothing to load.
nonisolated final class LaunchTrace: Sendable {
    nonisolated enum Milestone: String, CaseIterable, Sendable {
        /// `Launch.main`, the first of the app's own code that runs once the system has set the process up.
        case appInit
        /// `Libraries` has chosen its mode: whether a server is set, so whether a copy is to be opened.
        case librariesInit
        /// The saved server's copy has been tried: open, or not.
        case copyOpened
        /// The first `.loaded` the library applied: every item the copy held, in the views' hands.
        case firstLoaded
        /// The first main window showing content.
        case windowShown
    }

    static let shared = LaunchTrace()

    nonisolated private struct State {
        var marks: [Milestone: (at: Duration, note: StaticString?)] = [:]
        var nothingToLoad = false
        var logged = false
    }

    private let state = Mutex(State())

    /// When the process began, from the kernel, so the time before `main` counts. Nil if the kernel would not say.
    static let processStart: Date? = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0 else { return nil }
        let began = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(began.tv_sec) + TimeInterval(began.tv_usec) / 1_000_000)
    }()

    /// Records a milestone the first time it is reached; later ones are ignored. `note` is a kind, never a name.
    func mark(_ milestone: Milestone, note: StaticString? = nil, at now: Date = .now) {
        let since = Self.processStart.map { Duration.seconds(now.timeIntervalSince($0)) } ?? .zero
        let (first, finished): (Bool, Finished?) = state.withLock { state in
            guard state.marks[milestone] == nil else { return (false, nil) }
            state.marks[milestone] = (since, note)
            return (true, Self.completed(state) ? Self.finish(&state) : nil)
        }
        guard first else { return }
        Telemetry.event(.launch, milestone.word)
        finished?.tell()
    }

    /// The copy ended without a library to load, as with no server set or a key refused, so `windowShown` alone
    /// completes the launch.
    func settleWithoutLibrary() {
        let finished: Finished? = state.withLock { state in
            state.nothingToLoad = true
            return Self.completed(state) ? Self.finish(&state) : nil
        }
        finished?.tell()
    }

    /// A launch that has completed: its log line and its milestones, told once.
    nonisolated private struct Finished {
        let line: String
        let marks: [(milestone: Milestone, at: Duration, note: StaticString?)]

        func tell() {
            Telemetry.logger(.launch).notice("\(line, privacy: .public)")
            Telemetry.launched(marks)
        }
    }

    private static func completed(_ state: State) -> Bool {
        guard !state.logged, state.marks[.windowShown] != nil else { return false }
        return state.marks[.firstLoaded] != nil || state.nothingToLoad
    }

    private static func finish(_ state: inout State) -> Finished {
        state.logged = true
        let sorted = state.marks.sorted { $0.value.at < $1.value.at }
        let parts = sorted.map { milestone, mark in
            "\(milestone.rawValue)\(mark.note.map { " (\($0.description))" } ?? "") \(mark.at.inMilliseconds) ms"
        }
        return Finished(
            line: "launch since process start: " + parts.joined(separator: ", "),
            marks: sorted.map { ($0.key, $0.value.at, $0.value.note) })
    }
}

extension LaunchTrace.Milestone {
    /// The milestone's name as a signpost and a report give it.
    nonisolated var word: StaticString {
        switch self {
        case .appInit: "appInit"
        case .librariesInit: "librariesInit"
        case .copyOpened: "copyOpened"
        case .firstLoaded: "firstLoaded"
        case .windowShown: "windowShown"
        }
    }
}
