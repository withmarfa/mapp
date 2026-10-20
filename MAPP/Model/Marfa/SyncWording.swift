import Foundation

/// What the window says of how the library stands with its server, in the app's words. The model gives states
/// and counts; this turns them into sentences, with no view in it, so each is tested as state in, words out.
///
/// Nothing is said while everything is in step, and nothing at all while the app reads a folder.
nonisolated struct SyncStatus: Hashable, Sendable {
    nonisolated struct Note: Hashable, Sendable, Identifiable {
        enum Kind: Hashable, Sendable {
            case keyRefused, unavailable, needsAttention, offline, catchingUp, sending
        }

        let kind: Kind
        var title: String
        var detail: String
        var symbol: String
        /// Whether it asks something of the person, as against telling them how things stand.
        var isWarning: Bool

        var id: Kind { kind }
    }

    /// How long a change may wait while the server is reachable before the window says it is being sent. A
    /// change made online goes within moments, which is not worth a line.
    static let sendingDelay: TimeInterval = 5

    /// Most important first; the window shows the first and the list of problems shows them all.
    private(set) var notes: [Note] = []

    var isQuiet: Bool { notes.isEmpty }
    var primary: Note? { notes.first }
    /// Whether what the person has to do is in Settings: a key to replace, a library to open.
    var pointsToSettings: Bool { notes.contains { $0.kind == .keyRefused || $0.kind == .unavailable } }

    init(state: MarfaHost.State, report: SyncReport, now: Date) {
        guard state != .disconnected else { return }
        let waiting = report.waiting
        switch state {
        case .keyRefused:
            notes.append(Self.keyRefused(waiting: waiting))
        case .unavailable:
            notes.append(Self.unavailable)
        default:
            break
        }
        if !report.problems.isEmpty { notes.append(Self.needsAttention(report.problems.count)) }
        if case .offline = state { notes.append(Self.offline(waiting: waiting)) }
        let isReachable = state == .online || state == .connecting
        if report.phase == .catchingUp, isReachable {
            notes.append(Self.catchingUp)
        } else if isReachable, waiting > 0, let oldest = report.oldestWaiting, now.timeIntervalSince(oldest) >= Self.sendingDelay {
            notes.append(Self.sending(waiting: waiting))
        }
    }

    // MARK: Words

    private static func keyRefused(waiting: Int) -> Note {
        var detail = String(localized: "The server doesn’t accept your key. Enter a new one in Settings.")
        if waiting > 0 { detail += " " + Words.waiting(waiting) }
        return Note(kind: .keyRefused, title: String(localized: "Key refused"), detail: detail, symbol: "exclamationmark.triangle", isWarning: true)
    }

    private static var unavailable: Note {
        Note(
            kind: .unavailable, title: String(localized: "Library unavailable"),
            detail: String(localized: "MAPP can’t open the copy of your library on this Mac. Open Settings to see what to do."),
            symbol: "exclamationmark.triangle", isWarning: true)
    }

    private static func needsAttention(_ count: Int) -> Note {
        Note(
            kind: .needsAttention, title: String(localized: "Needs attention"), detail: Words.needAttention(count),
            symbol: "exclamationmark.triangle", isWarning: true)
    }

    private static func offline(waiting: Int) -> Note {
        let detail = waiting == 0
            ? String(localized: "Your changes are kept on this Mac and sent when you’re back online.")
            : Words.sentWhenOnline(waiting)
        return Note(kind: .offline, title: String(localized: "Offline"), detail: detail, symbol: "wifi.slash", isWarning: false)
    }

    private static var catchingUp: Note {
        Note(
            kind: .catchingUp, title: String(localized: "Catching up"),
            detail: String(localized: "Getting the latest changes from the server."),
            symbol: "arrow.triangle.2.circlepath", isWarning: false)
    }

    private static func sending(waiting: Int) -> Note {
        Note(
            kind: .sending, title: Words.sending(waiting), detail: Words.waiting(waiting),
            symbol: "arrow.up.circle", isWarning: false)
    }
}

/// Sentences that carry a count, which the String Catalog gives each plural form of.
nonisolated enum Words {
    static func waiting(_ count: Int) -> String {
        String(localized: "\(count) changes are waiting to be sent.")
    }

    static func sentWhenOnline(_ count: Int) -> String {
        String(localized: "\(count) changes will be sent when you’re back online.")
    }

    static func changes(_ count: Int) -> String {
        String(localized: "\(count) changes")
    }

    static func sending(_ count: Int) -> String {
        String(localized: "Sending \(count) changes")
    }

    static func needAttention(_ count: Int) -> String {
        String(localized: "\(count) changes need your attention.")
    }

    static func notSent(_ count: Int) -> String {
        String(localized: "\(count) changes on this Mac haven’t reached the server.")
    }

    static func moreNotShown(_ count: Int) -> String {
        String(localized: "And \(count) more changes whose text can’t be shown.")
    }
}

/// What a person is told about one problem, and what they can do about it. Only the actions the contract allows
/// for the problem are offered, and copying the text, which is always possible.
nonisolated struct ProblemWording: Hashable, Sendable {
    nonisolated struct Action: Hashable, Sendable, Identifiable {
        let action: SyncAction
        var title: String
        var isDestructive: Bool
        /// Reads the server first, so it waits for the server to be reachable.
        var needsServer: Bool

        var id: SyncAction { action }
    }

    var headline: String
    var explanation: String
    /// Each field the server refused, with its reason.
    var details: [String]
    var actions: [Action]
    var canCopyText: Bool
    /// For a conflicted copy: the item it was made from, and the copy.
    var original: ItemID?
    var copy: ItemID?

    /// `title` names an item the library holds, for a write that does not carry a title of its own.
    init(_ entry: SyncProblemEntry, title: (ItemID) -> String?) {
        let name = Self.name(of: entry, title: title)
        canCopyText = !entry.content.plainText.isEmpty
        var details: [String] = []
        let headline: String
        var explanation: String
        switch entry.kind {
        case .conflicted(let sibling, let original):
            let originalName = original.flatMap(title) ?? name
            headline = originalName.map { String(localized: "Your changes to “\($0)” were saved as a copy") }
                ?? String(localized: "Your changes were saved as a copy")
            explanation = String(localized: "The item was changed somewhere else while you were editing it. The server kept that version, and yours is the copy.")
            self.original = original
            copy = sibling
        case .refused:
            headline = Self.refusedHeadline(entry.change, name: name)
            let reason = entry.reason
            if let grant = reason?.grant {
                explanation = String(localized: "Your key doesn’t have permission for “\(grant.name)”. Ask whoever runs the server to allow it, then make the change again.")
            } else if reason?.isTrashed == true {
                explanation = String(localized: "The item is in Recently Deleted on the server, so it can’t be changed. Restore it, then make the change again.")
            } else if let message = reason?.message, !message.isEmpty {
                explanation = String(localized: "The server refused it: \(message)")
            } else {
                explanation = String(localized: "The server refused it.")
            }
            details = (reason?.fields ?? [:]).sorted { $0.key < $1.key }.map { "\(MarfaMapping.label(forField: $0.key)): \($0.value)" }
            if canCopyText { explanation += " " + String(localized: "To keep what you wrote, copy it before you discard this change.") }
        case .blocked(let reason):
            headline = Self.stoppedHeadline(name: name)
            explanation = switch reason {
            case .credentialRefused: String(localized: "It will be sent once the server accepts a key. Enter a new one in Settings.")
            case .keySpent: String(localized: "The server stopped this change from going through. Try again to send it.")
            case .ancestorUnavailable: String(localized: "It depends on an item that isn’t available any more. Undoing it puts the item back as the server has it.")
            case .conflictUnresolved: String(localized: "It can’t be applied until a conflict on the item is settled. Undoing it puts the item back as the server has it.")
            case .failingAlone: String(localized: "This change couldn’t be sent on its own, although the server took other changes. Try again to send it, or undo it to put the item back as the server has it.")
            }
        case .dead:
            headline = Self.stoppedHeadline(name: name)
            explanation = String(localized: "MAPP tried again and again, and the server never took it. Try again, or copy what you wrote first if you want to keep it.")
        }
        self.headline = headline
        self.explanation = explanation
        self.details = details
        actions = entry.actions.map { Self.action($0, for: entry.kind) }
    }

    private static func name(of entry: SyncProblemEntry, title: (ItemID) -> String?) -> String? {
        if let written = entry.content.title?.trimmingCharacters(in: .whitespacesAndNewlines), !written.isEmpty { return written }
        return entry.itemID.flatMap(title)
    }

    private static func refusedHeadline(_ change: SyncProblemEntry.Change, name: String?) -> String {
        switch (change, name) {
        case (.create, let name?): String(localized: "“\(name)” wasn’t created")
        case (.create, nil): String(localized: "A new item wasn’t created")
        case (.edit, let name?): String(localized: "Changes to “\(name)” weren’t sent")
        case (.delete, let name?): String(localized: "“\(name)” wasn’t deleted")
        case (.delete, nil): String(localized: "A deletion wasn’t sent")
        case (.restore, let name?): String(localized: "“\(name)” wasn’t restored")
        case (.restore, nil): String(localized: "A restore wasn’t sent")
        case (_, let name?): String(localized: "A change to “\(name)” wasn’t sent")
        default: String(localized: "A change wasn’t sent")
        }
    }

    private static func stoppedHeadline(name: String?) -> String {
        name.map { String(localized: "A change to “\($0)” is on hold") } ?? String(localized: "A change is on hold")
    }

    private static func action(_ action: SyncAction, for kind: SyncProblemEntry.Kind) -> Action {
        switch action {
        case .discard:
            if case .conflicted = kind {
                Action(action: action, title: String(localized: "Discard Copy"), isDestructive: true, needsServer: false)
            } else {
                Action(action: action, title: String(localized: "Discard"), isDestructive: true, needsServer: false)
            }
        case .tryAgain: Action(action: action, title: String(localized: "Try Again"), isDestructive: false, needsServer: false)
        case .withdraw: Action(action: action, title: String(localized: "Undo Change"), isDestructive: true, needsServer: true)
        case .keep: Action(action: action, title: String(localized: "Keep Copy"), isDestructive: false, needsServer: false)
        }
    }
}
