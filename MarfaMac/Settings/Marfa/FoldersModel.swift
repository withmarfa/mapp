import Foundation
import Marfa
import Observation

/// The Folders page: the synced folders the server lists, each with what its copies last reported. The page only reads:
/// reading and changing a folder's settings and files is the command line's, as the server's own folder doors are not part
/// of the client this app uses.
@Observable @MainActor final class FoldersModel {
    /// How a folder or a copy stands, in the words a row says at its trailing edge.
    struct Condition: Equatable {
        enum Tone: Equatable { case ok, warning, quiet }

        let title: String
        let tone: Tone
    }

    private let context: OwnerContext

    private(set) var folders: [OwnerFolder] = []
    /// How many folders the server holds, which is more than `folders` where the overview cut its list.
    private(set) var total = 0
    private(set) var reports: [String: FolderReport] = [:]
    /// Why a folder's report could not be read, by the folder's id.
    private(set) var reportFailures: [String: OwnerFailure] = [:]
    private let loader = OwnerLoader()
    var failure: OwnerFailure? { loader.failure }
    var hasLoaded: Bool { loader.hasLoaded }

    init(context: OwnerContext) {
        self.context = context
    }

    func folder(_ id: String) -> OwnerFolder? { folders.first { $0.id == id } }

    /// Reads the list, which the page shows at once, then each folder's report a few at a time.
    func load() async {
        await loader.load(in: context, primary: { () throws(OwnerFailure) in
            let listing = try await context.calls.folders()
            folders = listing.folders
            total = listing.total
        }, showBeforeFinishing: true, after: {
            let calls = context.calls
            await readEach(
                of: folders.map(\.id),
                read: { id -> Result<FolderReport, OwnerFailure> in
                    do throws(OwnerFailure) { return .success(try await calls.folderReport(id)) } catch { return .failure(error) }
                },
                take: { id, answer in await take(answer, for: id) })
        })
    }

    func loadReport(_ id: String) async {
        do throws(OwnerFailure) {
            await take(.success(try await context.calls.folderReport(id)), for: id)
        } catch {
            await take(.failure(error), for: id)
        }
    }

    private func take(_ answer: Result<FolderReport, OwnerFailure>, for id: String) async {
        switch answer {
        case .success(let report):
            reports[id] = report
            reportFailures[id] = nil
        case .failure(let error):
            reportFailures[id] = error
            if error == .notFound { folders.removeAll { $0.id == id } }
            await context.learn(from: error)
        }
    }

    /// Where the list was cut, how many are shown and where the rest are listed; nil when it holds them all.
    var cutLine: String? {
        guard total > folders.count else { return nil }
        let shown = folders.count
        return String(localized: "Showing \(shown) of \(total). The rest are listed by marfa folders inventory.")
    }

    // MARK: Words

    /// "2 copies.", the line under a folder.
    static func copies(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "No copies yet.")
        case 1: String(localized: "1 copy.")
        default: String(localized: "\(count) copies.")
        }
    }

    /// How a folder stands, from all its copies; nil where its report is not read.
    func condition(of folder: OwnerFolder) -> Condition? {
        reports[folder.id].map { Self.condition(of: $0) }
    }

    static func condition(of report: FolderReport) -> Condition {
        guard !report.copies.isEmpty else { return Condition(title: String(localized: "No copies"), tone: .quiet) }
        return condition(
            pausedRemovals: report.pausedRemovals, problems: report.copies.contains { !$0.problems.isEmpty },
            uploads: report.pendingUploads, downloads: report.pendingDownloads, starting: report.copies.contains(where: \.firstSyncWaiting))
    }

    static func condition(of copy: FolderCopy) -> Condition {
        condition(
            pausedRemovals: copy.pausedRemovals, problems: !copy.problems.isEmpty, uploads: copy.pendingUploads,
            downloads: copy.pendingDownloads, starting: copy.firstSyncWaiting)
    }

    private static func condition(pausedRemovals: Int, problems: Bool, uploads: Int, downloads: Int, starting: Bool) -> Condition {
        if pausedRemovals > 0 {
            let title = pausedRemovals == 1 ? String(localized: "1 removal waits") : String(localized: "\(pausedRemovals) removals wait")
            return Condition(title: title, tone: .warning)
        }
        if problems { return Condition(title: String(localized: "Needs attention"), tone: .warning) }
        if starting { return Condition(title: String(localized: "Waiting to start"), tone: .quiet) }
        switch (uploads, downloads) {
        case (0, 0): return Condition(title: String(localized: "Up to date"), tone: .ok)
        case (let sending, 0): return Condition(title: String(localized: "\(sending) to send"), tone: .quiet)
        case (0, let receiving): return Condition(title: String(localized: "\(receiving) to receive"), tone: .quiet)
        case (let sending, let receiving): return Condition(title: String(localized: "\(sending + receiving) waiting"), tone: .quiet)
        }
    }

    /// The title of a copy's removals that wait, which its row in Needs Attention gives.
    static func removalsTitle(_ count: Int, signIn: String) -> String {
        count == 1 ? String(localized: "1 Removal Waits on \(signIn)") : String(localized: "\(count) Removals Wait on \(signIn)")
    }

    /// Whether a copy is listed under a folder's Needs Attention.
    static func needsAttention(_ copy: FolderCopy) -> Bool { copy.pausedRemovals > 0 || !copy.problems.isEmpty }

    /// "Reported 20 minutes ago.", the line under a copy.
    static func reported(ageSeconds: Int, now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let text = formatter.localizedString(for: Date(timeInterval: -TimeInterval(ageSeconds), since: now), relativeTo: now)
        return String(localized: "Reported \(text).")
    }

    /// What a problem a copy reports comes to, as a row says it. The server keeps a code and a count, never a file.
    static func title(of problem: FolderProblem) -> String {
        let count = problem.count
        switch problem.code {
        case .conflict: return count == 1 ? String(localized: "1 Conflicted Copy") : String(localized: "\(count) Conflicted Copies")
        case .refused: return count == 1 ? String(localized: "1 File the Server Refused") : String(localized: "\(count) Files the Server Refused")
        case .credentialRefused: return String(localized: "The Server Refused This Copy’s Sign-In")
        case .unreadable: return count == 1 ? String(localized: "1 File or Folder Can’t Be Read") : String(localized: "\(count) Files or Folders Can’t Be Read")
        case .heldFile: return count == 1 ? String(localized: "1 File Is Held Back") : String(localized: "\(count) Files Are Held Back")
        case .unavailable: return String(localized: "This Copy Can’t Reach the Server")
        case .rootGone: return String(localized: "The Folder Is Missing Where This Copy Is Kept")
        case .settingsInvalid: return String(localized: "This Copy’s Settings File Can’t Be Used")
        case .unwatched: return String(localized: "This Copy Isn’t Watching for Changes")
        case .paused: return String(localized: "Syncing Is Paused")
        }
    }

    /// The words under a copy's removals that wait: where they are decided, since only the copy that holds the files can.
    static let removalsLine = String(localized: "Review them where it runs.")

    /// The words under a copy's problem: which copy reports it and where it is looked into.
    static func problemLine(signIn: String) -> String {
        String(localized: "Reported by \(signIn). Review it where that copy runs.")
    }
}
