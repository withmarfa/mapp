import Foundation

/// The dot after the instance's name at the foot of the sidebar. Nothing shows while the server is reachable, so
/// the dot only ever says something is wrong or not yet known.
nonisolated enum SidebarStatusDot: Hashable, Sendable {
    /// Showing the copy, not yet heard from the server.
    case connecting
    /// The server cannot be reached, or the copy cannot be used.
    case trouble

    init?(_ state: MarfaHost.State) {
        switch state {
        case .disconnected, .online: return nil
        case .connecting: self = .connecting
        case .offline, .keyRefused, .unavailable, .otherVersion, .inUse: self = .trouble
        }
    }
}
