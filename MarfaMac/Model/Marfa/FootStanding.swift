import Foundation

/// What the sidebar's foot reads to say how the library stands: the connection's state, the sync report and the time
/// of the last sync, with where the Marfa runs. The line is worked out again as the clock passes.
nonisolated struct FootStanding: Sendable {
    var state: MarfaConnectionState
    var report: SyncReport
    var lastSynced: Date?
    /// Whether the Marfa is kept on this Mac: its server runs here, or it has none.
    var onThisMac: Bool
    /// Whether the connection is to a server, as against a library the Mac keeps by itself.
    var hasServer: Bool

    /// Nil where there is nothing to say.
    func line(now: Date) -> SyncFootLine? {
        guard hasServer else { return .onThisMac }
        return SyncFootLine(state: state, report: report, lastSynced: lastSynced, now: now, onThisMac: onThisMac)
    }
}

extension FootStanding {
    @MainActor init(host: MarfaHost) {
        let hasServer = host.hasServer
        self.init(
            state: host.state, report: host.report, lastSynced: host.lastSynced,
            onThisMac: !hasServer || host.connection?.isOnThisMac == true, hasServer: hasServer)
        #if DEBUG
        if !hasServer, let sample = Self.launched { self = sample }
        #endif
    }
}

#if DEBUG
nonisolated extension FootStanding {
    /// A Debug build launched with the sample and `-MarfaMacFootLine <state>` stands in each way the foot can: `updated`,
    /// `syncing`, `waiting`, `offline`, `offlineWaiting`, `attention`, `failed`. Any other word, and no argument, is a
    /// Marfa on this Mac.
    static let launchArgument = "-MarfaMacFootLine"
    /// Worked out once, so the times it reads from stay where the launch put them and age with the clock.
    static let launched = sample(argument: launchArgument)

    static func sample(argument flag: String, in arguments: [String] = ProcessInfo.processInfo.arguments, now: Date = .now) -> FootStanding? {
        guard SampleLibrary.isRequested, let at = arguments.firstIndex(of: flag), arguments.indices.contains(at + 1) else { return nil }
        var report = SyncReport(queueRead: true)
        var state = MarfaConnectionState.online
        var lastSynced: Date? = now - 120
        switch arguments[at + 1] {
        case "updated": break
        case "syncing": report.phase = .updating
        case "waiting": (report.waiting, report.oldestWaiting) = (3, now - 60)
        case "offline": (state, lastSynced) = (.offline(reason: nil), now - 3600)
        case "offlineWaiting": (state, report.waiting) = (.offline(reason: nil), 3)
        case "attention":
            let entry = SyncProblemEntry(
                id: .write("sample"), itemID: nil, kind: .refused, change: .edit, reason: nil, content: SyncContent(),
                actions: MarfaProblems.actions(for: .refused))
            report.problems = [entry, entry]
        case "failed": state = .keyRefused
        default: return FootStanding(state: .online, report: report, lastSynced: nil, onThisMac: true, hasServer: false)
        }
        return FootStanding(state: state, report: report, lastSynced: lastSynced, onThisMac: false, hasServer: true)
    }
}
#endif
