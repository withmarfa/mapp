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
        let (first, line): (Bool, String?) = state.withLock { state in
            guard state.marks[milestone] == nil else { return (false, nil) }
            state.marks[milestone] = (since, note)
            return (true, Self.completed(state) ? Self.line(&state) : nil)
        }
        guard first else { return }
        milestone.signpost()
        if let line {
            Telemetry.logger(.launch).notice("\(line, privacy: .public)")
        }
    }

    /// The copy ended without a library to load, as with no server set or a key refused, so `windowShown` alone
    /// completes the launch.
    func settleWithoutLibrary() {
        let line: String? = state.withLock { state in
            state.nothingToLoad = true
            return Self.completed(state) ? Self.line(&state) : nil
        }
        if let line { Telemetry.logger(.launch).notice("\(line, privacy: .public)") }
    }

    private static func completed(_ state: State) -> Bool {
        guard !state.logged, state.marks[.windowShown] != nil else { return false }
        return state.marks[.firstLoaded] != nil || state.nothingToLoad
    }

    private static func line(_ state: inout State) -> String {
        state.logged = true
        let parts = state.marks.sorted { $0.value.at < $1.value.at }.map { milestone, mark in
            "\(milestone.rawValue)\(mark.note.map { " (\($0.description))" } ?? "") \(mark.at.inMilliseconds) ms"
        }
        return "launch since process start: " + parts.joined(separator: ", ")
    }
}

private extension LaunchTrace.Milestone {
    nonisolated func signpost() {
        switch self {
        case .appInit: Telemetry.event(.launch, "appInit")
        case .librariesInit: Telemetry.event(.launch, "librariesInit")
        case .copyOpened: Telemetry.event(.launch, "copyOpened")
        case .firstLoaded: Telemetry.event(.launch, "firstLoaded")
        case .windowShown: Telemetry.event(.launch, "windowShown")
        }
    }
}
