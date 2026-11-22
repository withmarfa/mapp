import Foundation
import Marfa
import os

/// What the window says of how the library stands with its server, in the app's words. The model gives states
/// and counts; this turns them into sentences, with no view in it, so each is tested as state in, words out.
///
/// Nothing is said while everything is in step.
nonisolated struct SyncStatus: Hashable, Sendable {
    nonisolated struct Notice: Hashable, Sendable, Identifiable {
        enum Kind: Hashable, Sendable {
            case keyRefused, unavailable, needsAttention, offline, catchingUp, sending
        }

        let kind: Kind
        var title: String
        /// The short line the sidebar and the Connection page show, with the count that makes the title useful.
        var line: String
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
    private(set) var notices: [Notice] = []

    var primary: Notice? { notices.first }

    init(state: MarfaConnectionState, report: SyncReport, now: Date) {
        guard state != .disconnected else { return }
        let waiting = report.waiting
        switch state {
        case .keyRefused:
            notices.append(Self.keyRefused(waiting: waiting))
        case .unavailable, .otherVersion, .inUse:
            notices.append(Self.unavailable)
        default:
            break
        }
        if !report.problems.isEmpty { notices.append(Self.needsAttention(report.problems.count)) }
        if case .offline = state { notices.append(Self.offline(waiting: waiting)) }
        let isReachable = state == .online || state == .connecting
        if report.phase == .catchingUp, isReachable {
            notices.append(Self.catchingUp)
        } else if isReachable, waiting > 0, let oldest = report.oldestWaiting, now.timeIntervalSince(oldest) >= Self.sendingDelay {
            notices.append(Self.sending(waiting: waiting))
        }
    }

    // MARK: Words

    private static func keyRefused(waiting: Int) -> Notice {
        var detail = Words.signInEnded
        if waiting > 0 { detail += " " + Words.waiting(waiting) }
        let line = waiting > 0 ? Words.keyRefusedLine(waiting) : String(localized: "Signed out")
        return Notice(kind: .keyRefused, title: String(localized: "Signed out"), line: line, detail: detail, symbol: "exclamationmark.triangle", isWarning: true)
    }

    private static var unavailable: Notice {
        Notice(
            kind: .unavailable, title: String(localized: "Library unavailable"), line: String(localized: "Library unavailable"),
            detail: String(localized: "MAPP can’t open the copy of your library on this Mac. Open Settings to see what to do."),
            symbol: "exclamationmark.triangle", isWarning: true)
    }

    private static func needsAttention(_ count: Int) -> Notice {
        Notice(
            kind: .needsAttention, title: String(localized: "Needs attention"), line: Words.needAttentionLine(count),
            detail: Words.needAttention(count),
            symbol: "exclamationmark.triangle", isWarning: true)
    }

    private static func offline(waiting: Int) -> Notice {
        let detail = waiting == 0
            ? String(localized: "Your changes are kept on this Mac and sent when you’re back online.")
            : Words.sentWhenOnline(waiting)
        let line = waiting == 0 ? String(localized: "Offline") : Words.offlineLine(waiting)
        return Notice(kind: .offline, title: String(localized: "Offline"), line: line, detail: detail, symbol: "wifi.slash", isWarning: false)
    }

    private static var catchingUp: Notice {
        Notice(
            kind: .catchingUp, title: String(localized: "Catching up"), line: String(localized: "Catching up"),
            detail: String(localized: "Getting the latest changes from the server."),
            symbol: "arrow.triangle.2.circlepath", isWarning: false)
    }

    private static func sending(waiting: Int) -> Notice {
        Notice(
            kind: .sending, title: Words.sending(waiting), line: Words.sending(waiting), detail: Words.waiting(waiting),
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

    static func waitingToSend(_ count: Int) -> String {
        String(localized: "\(count) changes waiting to send")
    }

    static func needAttentionLine(_ count: Int) -> String {
        String(localized: "\(count) changes need attention")
    }

    static func offlineLine(_ count: Int) -> String {
        String(localized: "Offline, \(count) changes waiting")
    }

    static func keyRefusedLine(_ count: Int) -> String {
        String(localized: "Signed out, \(count) changes waiting")
    }

    static func needAttention(_ count: Int) -> String {
        String(localized: "\(count) changes need your attention.")
    }

    static func notSent(_ count: Int) -> String {
        String(localized: "\(count) changes on this Mac haven’t reached the server.")
    }

    /// Why the copy on this Mac kept a change from the server without sending it. The person can only discard it,
    /// so the way forward is to make the change again.
    static func unsent(_ unsent: SyncProblem.Unsent) -> String {
        switch unsent {
        case .tooLarge(let size, let limit):
            let (sizeText, limitText) = sizes(size, limit)
            return String(localized: "This change is \(sizeText), more than the \(limitText) the server takes at once, so it wasn’t sent. Make it again in smaller parts.")
        case .afterRefusal:
            return String(localized: "It went with an earlier change that wasn’t sent, so it wasn’t sent either. Make it again.")
        case .notSent:
            return String(localized: "MAPP couldn’t send this change.")
        }
    }

    /// Two sizes as Finder shows them, with the exact bytes added where they would otherwise read the same.
    static func sizes(_ size: UInt64, _ limit: UInt64) -> (String, String) {
        let shown = [size, limit].map { Int64(clamping: $0).formatted(.byteCount(style: .file)) }
        guard shown[0] == shown[1] else { return (shown[0], shown[1]) }
        let exact = ByteCountFormatStyle(style: .file, includesActualByteCount: true)
        return (Int64(clamping: size).formatted(exact), Int64(clamping: limit).formatted(exact))
    }

    /// The copy's own reason for not sending a change, as a sentence.
    static func unsentReason(_ reason: String) -> String {
        let sentence = reason.prefix(1).uppercased() + reason.dropFirst()
        return sentence.hasSuffix(".") ? sentence : sentence + "."
    }

    static func moreNotShown(_ count: Int) -> String {
        String(localized: "And \(count) more changes whose text can’t be shown.")
    }

    /// What to tell a person whose copy a different version of the app made, and so cannot be opened. Only that
    /// version can send the changes in it that the server has not taken, so the way forward is through it. A count
    /// that can't be read stays unread after that version sends everything, and the package never removes a copy whose
    /// changes it can't read, so the way out then is to remove the copy's folder.
    static func otherVersion(unsent: UInt64?) -> String {
        let lead = String(localized: "This version of MAPP can’t read the copy of your library on this Mac, because a different version made it.")
        switch unsent {
        case let count?:
            return [
                lead, notSent(Int(clamping: count)),
                String(localized: "They’re still in that copy. To send them, install the previous build of MAPP from TestFlight and connect it to this server if it isn’t already. When it has sent them, and you’ve resolved any it can’t send, update MAPP again."),
            ].joined(separator: " ")
        case nil:
            return [
                lead, String(localized: "MAPP can’t tell whether that copy holds changes that haven’t reached the server."),
                String(localized: "To send any changes it holds, install the previous build of MAPP from TestFlight and connect it to this server if it isn’t already. MAPP can’t remove a copy it can’t count, so when that build has sent everything, update MAPP, choose Disconnect, then Keep Copy and Disconnect, and move the copy’s folder to the Trash. After that, connect to the server again."),
            ].joined(separator: " ")
        }
    }

    /// The package removes a copy only against the list of the changes in it, so a copy whose changes can't be listed
    /// is left for the person, who is shown where it is.
    static func cannotDiscard(folder: String) -> String {
        String(localized: "MAPP can’t read the copy of your library on this Mac, so it can’t tell what the copy holds and won’t discard it. If you remove it yourself, quit MAPP first, then move the folder “\(folder)” to the Trash. Anything in it that hasn’t reached the server is lost.")
    }

    /// Another process holds the copy as its writer, which on this Mac is another copy of MAPP.
    static var inUse: String {
        String(localized: "Another copy of MAPP on this Mac is using your library. Quit the other copy, then quit and reopen this one.")
    }

    /// The package's notice is in English, so the app says it in its own words.
    static var plainHTTPTitle: String {
        String(localized: "This Connection Isn’t Encrypted")
    }

    static func plainHTTP(origin: String) -> String {
        String(localized: "Your sign-in is sent to \(origin) without encryption, so anyone on the network can read it. Use an https address unless this network is private.")
    }

    /// The Keychain would not give the sign-in, which is not the same as there being none or the server ending it.
    static var signInUnreadable: String {
        String(localized: "MAPP couldn’t read this library’s sign-in from the Keychain. Unlock the Keychain and quit and reopen MAPP, or sign in again in Settings.")
    }

    /// How the owner ends an approval the server at `address` may still hold: only they can, with the command line
    /// signed in to that address.
    private static func endApproval(at address: String) -> String {
        String(localized: "To end it, run “marfa apps list” with the command line signed in to \(address) as the owner, find MAPP’s entry, then run “marfa apps revoke <id>”.")
    }

    /// A sign-in that replaced another on the same server, where MAPP could not confirm the older approval ended.
    static var replacedApprovalTitle: String {
        String(localized: "MAPP’s Earlier Approval May Still Stand")
    }

    static func replacedApproval(address: String) -> String {
        String(localized: "MAPP couldn’t confirm that \(address) ended MAPP’s earlier approval.") + " " + String(localized: "Run “marfa apps list” with the command line signed in to \(address) as the owner. Use the approval date to identify the earlier MAPP approval. If you can identify it, run “marfa apps revoke <id>” with that entry’s ID.")
    }

    /// What MAPP is no longer allowed to do after a sign-in the owner approved with fewer permissions than it held.
    static var permissionsLostTitle: String {
        String(localized: "Fewer Permissions Allowed")
    }

    static func permissionsLost(_ lost: Set<InstancePermission>) -> String {
        let list = lost.sorted { $0.rawValue < $1.rawValue }.map(\.allowedTo).formatted(.list(type: .and))
        return String(localized: "MAPP is no longer allowed to \(list). Allow it again from the page that needs it.")
    }

    /// A clean-up sign-out that threw before it forgot or revoked anything, so the sign-in and the approval may both stand.
    static var signOutFailedTitle: String {
        String(localized: "MAPP’s Sign-In May Still Be Kept")
    }

    static func signOutFailed(address: String) -> String {
        String(localized: "MAPP couldn’t drop a sign-in it didn’t use, so the sign-in may still be kept on this Mac and the approval may stand at \(address).") + " " + endApproval(at: address)
    }

    /// A sign-in MAPP dropped, or forgot on this Mac, whose approval it could not confirm the server ended.
    enum ForgottenApproval {
        /// The sign-in of the server the person left.
        case left
        /// The sign-in of the server the person switched away from.
        case previous
        /// A sign-in made for a step that did not go on, such as a switch that was abandoned.
        case abandoned
    }

    static func approvalMayStandTitle(_ which: ForgottenApproval) -> String {
        switch which {
        case .left: String(localized: "Disconnected, but MAPP May Still Be Approved")
        case .previous: String(localized: "Switched Servers, but MAPP May Still Be Approved on the Previous One")
        case .abandoned: String(localized: "MAPP May Still Be Approved")
        }
    }

    /// `address` is the server whose approval may stand: after a switch, the previous one.
    static func approvalMayStand(_ which: ForgottenApproval, address: String) -> String {
        let told = switch which {
        case .left:
            String(localized: "MAPP forgot its sign-in on this Mac, but couldn’t confirm that \(address) ended the approval.")
        case .previous:
            String(localized: "MAPP forgot the previous server’s sign-in on this Mac, but couldn’t confirm that \(address) ended the approval.")
        case .abandoned:
            String(localized: "MAPP dropped a sign-in it didn’t use, but couldn’t confirm that \(address) ended its approval.")
        }
        return told + " " + endApproval(at: address)
    }

    /// The copy could not be opened or made, for a reason the package did not name.
    static var copyCouldNotBeOpened: String {
        String(localized: "MAPP couldn’t make or open the copy of your library on this Mac. Check that MAPP can change its own files, then try again.")
    }

    /// The copy's file is damaged. It says where the copy is, what it holds that no server has taken (`unsent` is nil
    /// where the queue could not be read), and, when setting the damaged copy aside stopped partway, that opening the
    /// library again finishes it.
    static func storeDamaged(folder: String?, unsent: UInt64?, setAsideStopped: Bool) -> String {
        var parts = [String(localized: "The copy of your library on this Mac is damaged, so MAPP can’t open it.")]
        if let folder { parts.append(String(localized: "The copy is in the folder “\(folder)”.")) }
        switch unsent {
        case let count? where count > 0: parts.append(notSent(Int(clamping: count)))
        case 0?: parts.append(String(localized: "It holds no changes that haven’t reached the server."))
        default: parts.append(String(localized: "MAPP couldn’t read whether it holds changes that haven’t reached the server."))
        }
        if setAsideStopped {
            parts.append(String(localized: "MAPP started to set the damaged copy aside and stopped partway. Open the library again to finish it."))
        }
        return parts.joined(separator: " ")
    }

    /// A server whose release is older than the oldest this build works with. Asking again cannot clear it, so
    /// the words say to update the server, never what the server said.
    static func serverTooOld(served: String, oldest: String) -> String {
        String(localized: "This server runs Marfa \(served). Update the server to Marfa \(oldest) or later to use this app.")
    }

    /// A renewal of the sign-in failed and the sign-in stands, so the way forward is to try again, then to check where
    /// the server is, then to sign in again. The package's own text, which can hold the address, is only logged.
    static func renewalRefused(_ reason: RenewalRefusalReason) -> String {
        switch reason {
        case .refused:
            String(localized: "MAPP couldn’t renew its sign-in with the server, because the server didn’t accept the renewal. Try again later. If it keeps happening, check the server’s address in Settings, or sign in again.")
        case .redirected:
            String(localized: "MAPP couldn’t renew its sign-in because the server redirected the request. Check the server address in Settings, then try again. If this keeps happening, sign in again.")
        case .unreadable:
            String(localized: "MAPP couldn’t renew its sign-in with the server, because it couldn’t read the server’s answer. Try again later. If it keeps happening, check the server’s address in Settings, or sign in again.")
        }
    }

    /// The server ended MAPP's sign-in, whatever step met it.
    static var signInEnded: String {
        String(localized: "The server has ended MAPP’s sign-in. Sign in again in Settings.")
    }

    /// MAPP and the server speak different versions of Marfa. Where a write was sent, the server may have made it.
    static func contractMismatch(writeSent: Bool) -> String {
        writeSent
            ? String(localized: "This version of MAPP and the server use different versions of Marfa, and the change may already have been made. Update MAPP or the server, then check the change.")
            : String(localized: "This version of MAPP and the server use different versions of Marfa, so the server didn’t make the change. Update MAPP or the server, then try again.")
    }

    /// The server or the copy stopped a step for a reason MAPP can't resolve itself.
    static var syncFailed: String {
        String(localized: "MAPP ran into a problem it can’t resolve itself. Choose Refresh to try again.")
    }

    /// There is not enough room on this Mac for the copy.
    static var storageFull: String {
        String(localized: "There isn’t enough room on this Mac for the copy of your library. Free some space, then try again.")
    }

    /// The address reaches another Marfa server than the one the open library was made for, which a new sign-in cannot change.
    static var differentServer: String {
        String(localized: "This address reaches a different Marfa server from the one this library was made for, so MAPP left the library as it was.")
    }

    /// The server could not be reached.
    static var serverUnreachable: String {
        String(localized: "MAPP couldn’t reach the server. Check your connection, then try again.")
    }

    /// What to show a person of an error the package raised, in the app's words: what the package, the system or the
    /// server said goes to the log and is never shown.
    static func message(for error: MarfaError) -> String {
        // A string logged without a privacy level is private.
        Telemetry.logger(.library).error("A package step failed: \(String(describing: error))")
        if case .serverTooOld(let served, let oldest, _) = error { return serverTooOld(served: served, oldest: oldest) }
        if error.isKeyRefusal { return signInEnded }
        if case .contractMismatch(_, _, _, let writeSent, _, _) = error { return contractMismatch(writeSent: writeSent) }
        switch error {
        case .storeDamaged(let path, _, let unsent, let setAsideStopped, _):
            return storeDamaged(folder: path.isEmpty ? nil : URL(fileURLWithPath: path).deletingLastPathComponent().path, unsent: unsent, setAsideStopped: setAsideStopped)
        case .noKeychain: return signInUnreadable
        case .renewalRefused(let reason, _): return renewalRefused(reason)
        case .store, .io, .closed: return copyCouldNotBeOpened
        case .wrongServer: return differentServer
        case .storageFull: return storageFull
        case .network, .noConnection: return serverUnreachable
        default: return error.isOffline ? serverUnreachable : syncFailed
        }
    }

    /// The address now reaches another Marfa server than the one this copy was made for, so nothing in the copy is
    /// sent there. The count is of the changes the copy holds that no server has taken; `nil` where it can't be read.
    static func otherServer(unsent: UInt64?) -> String {
        let lead = String(localized: "This address now reaches a different Marfa server from the one this copy of your library was made for, so MAPP has stopped syncing it.")
        let way = String(localized: "To start a new copy from this server, choose Disconnect in Settings, then connect again.")
        switch unsent {
        case let count? where count > 0:
            return [lead, notSent(Int(clamping: count)), way].joined(separator: " ")
        case 0?:
            return [lead, way].joined(separator: " ")
        default:
            return [lead, String(localized: "MAPP can’t tell whether this copy holds changes that haven’t reached a server."), way]
                .joined(separator: " ")
        }
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

    /// What an action that loses the person's text asks before it runs.
    nonisolated struct Confirmation: Hashable, Sendable, Identifiable {
        let action: SyncAction
        var title: String
        var message: String
        var button: String
        /// Puts the text on the clipboard as the action runs.
        var copiesText: Bool

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
                explanation = String(localized: "MAPP doesn’t have permission for “\(grant.name)”. Ask whoever runs the server to allow it, then make the change again.")
            } else if reason?.isTrashed == true {
                explanation = String(localized: "The item is in Recently Deleted on the server, so it can’t be changed. Restore it, then make the change again.")
            } else if let unsent = reason?.unsent {
                explanation = Words.unsent(unsent)
            } else if let message = reason?.message, !message.isEmpty {
                explanation = String(localized: "The server refused it: \(message)")
            } else {
                explanation = String(localized: "The server refused it.")
            }
            details = (reason?.fields ?? [:]).sorted { $0.key < $1.key }.map { "\(entry.fieldLabels[$0.key] ?? $0.key): \($0.value)" }
            if case .notSent(let why)? = reason?.unsent { details.append(Words.unsentReason(why)) }
            if canCopyText { explanation += " " + String(localized: "To keep what you wrote, copy it before you discard this change.") }
        case .blocked(let reason):
            headline = Self.stoppedHeadline(name: name)
            explanation = switch reason {
            case .credentialRefused: String(localized: "It will be sent once you sign in again. Do that in Settings.")
            case .keySpent: String(localized: "The server stopped this change from going through. Try again to send it.")
            case .ancestorUnavailable: String(localized: "It depends on an item that isn’t available any more. Undoing it puts the item back as the server has it.")
            case .conflictUnresolved: String(localized: "It can’t be applied until a conflict on the item is settled. Undoing it puts the item back as the server has it.")
            case .instanceChanged: String(localized: "This change was made for a library the server no longer holds as it was. Try again to send it to the library as it is now, or undo it to put the item back as the server has it.")
            case .recordUnread: String(localized: "This change came from a copy that MAPP could only partly read, so it was held. Try again to send it, or undo it to put the item back as the server has it.")
            case .serverRestored: String(localized: "The server was restored to an earlier point, and this change would put back what the restore removed. Try again to send it anyway, or undo it to keep the item as the server has it.")
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

    /// A write that carried text holds the only copy of it, so losing it is confirmed. Discarding asks the person
    /// to copy it first. Undoing the change copies it for them, since the page then shows the server's text and
    /// the row goes. A conflicted copy goes to Recently Deleted, so discarding it is not confirmed.
    func confirmation(for action: SyncAction) -> Confirmation? {
        guard canCopyText, let offered = actions.first(where: { $0.action == action }) else { return nil }
        switch action {
        case .discard where copy == nil:
            return Confirmation(
                action: action, title: String(localized: "Discard this change?"),
                message: String(localized: "What you wrote is lost unless you copy it first."),
                button: offered.title, copiesText: false)
        case .withdraw:
            return Confirmation(
                action: action, title: String(localized: "Undo this change?"),
                message: String(localized: "The item goes back to how the server has it. What you wrote is copied to the clipboard, so you can paste it back."),
                button: offered.title, copiesText: true)
        default:
            return nil
        }
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

extension InstancePermission {
    /// What holding the permission lets MAPP do, said as the Settings pages say it after "MAPP isn’t allowed to".
    nonisolated var allowedTo: String {
        switch self {
        case .configManage: String(localized: "see and change the server’s settings")
        case .itemsPurge: String(localized: "list and permanently delete deleted items")
        case .schemaWrite: String(localized: "choose a type’s icon and change a type’s fields")
        case .auditRead: String(localized: "read the audit log")
        case .backupsManage: String(localized: "list, make and restore backups")
        case .blobsManage: String(localized: "manage files across the server")
        case .connectorsManage: String(localized: "manage connectors")
        case .grantsManage: String(localized: "list, narrow and revoke other apps’ access")
        case .instanceMaintain: String(localized: "update the server and run its housekeeping")
        case .instanceRead: String(localized: "read the server’s health and status")
        case .keysManage: String(localized: "list, extend and revoke keys")
        case .keysMint: String(localized: "make keys")
        case .signInsManage: String(localized: "manage the owner’s sign-ins and passkeys")
        case .webhooksManage: String(localized: "manage webhooks")
        }
    }
}
