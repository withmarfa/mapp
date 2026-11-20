import AppKit
import SwiftUI

/// Reads how the library stands with its server, again as the clock passes: a change made online goes within
/// moments and is not worth a line, so a line about sending waits for the clock.
struct SyncStatusReading<Content: View>: View {
    let host: MarfaHost
    @ViewBuilder let content: (SyncStatus) -> Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: host.report.waiting > 0 ? 1 : 60)) { context in
            content(SyncStatus(state: host.state, report: host.report, now: context.date))
        }
    }
}

/// Reads the foot's sync line, again as the clock passes: each minute after the last sync, so "2 minutes ago" turns
/// to "3" on time, and each second while changes wait, since a line about sending waits for the clock.
struct SyncFootReading<Content: View>: View {
    let host: MarfaHost
    @ViewBuilder let content: (SyncFootLine?) -> Content

    var body: some View {
        let synced = host.lastSynced
        TimelineView(.periodic(from: synced ?? .now, by: host.report.waiting > 0 ? 1 : 60)) { context in
            content(host.hasServer ? SyncFootLine(state: host.state, report: host.report, lastSynced: synced, now: context.date) : nil)
        }
    }
}

extension SyncStatus.Notice {
    /// The colour of the dot beside the item: red where the person has to act, orange where something waits,
    /// and quiet while the app is only catching up.
    var dotColor: Color {
        switch kind {
        case .keyRefused, .unavailable: .red
        case .needsAttention, .offline: .orange
        case .catchingUp, .sending: .secondary
        }
    }
}
