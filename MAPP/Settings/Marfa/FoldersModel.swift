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
    private(set) var reports: [String: FolderReport] = [:]
    /// Why a folder's report could not be read, by the folder's id.
    private(set) var reportFailures: [String: OwnerFailure] = [:]
    private(set) var failure: OwnerFailure?
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    init(context: OwnerContext) {
        self.context = context
    }

    func folder(_ id: String) -> OwnerFolder? { folders.first { $0.id == id } }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            folders = try await context.calls.folders()
            failure = nil
        } catch {
            failure = error
            await context.learn(from: error)
            return
        }
        for folder in folders { await loadReport(folder.id) }
    }

    func loadReport(_ id: String) async {
        do {
            reports[id] = try await context.calls.folderReport(id)
            reportFailures[id] = nil
        } catch {
            reportFailures[id] = error
            if error == .notFound { folders.removeAll { $0.id == id } }
            await context.learn(from: error)
        }
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
        guard !report.copies.isEmpty else { return Condition(title: String(localized: "No Copies"), tone: .quiet) }
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
        if problems { return Condition(title: String(localized: "Needs Attention"), tone: .warning) }
        if starting { return Condition(title: String(localized: "Waiting to Start"), tone: .quiet) }
        switch (uploads, downloads) {
        case (0, 0): return Condition(title: String(localized: "Up to date"), tone: .ok)
        case (let sending, 0): return Condition(title: String(localized: "\(sending) to send"), tone: .quiet)
        case (0, let receiving): return Condition(title: String(localized: "\(receiving) to receive"), tone: .quiet)
        case (let sending, let receiving): return Condition(title: String(localized: "\(sending + receiving) waiting"), tone: .quiet)
        }
    }

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
        case .conflict: return count == 1 ? String(localized: "1 conflicted copy") : String(localized: "\(count) conflicted copies")
        case .refused: return count == 1 ? String(localized: "1 file the server refused") : String(localized: "\(count) files the server refused")
        case .credentialRefused: return String(localized: "The server refused this copy’s sign-in")
        case .unreadable: return count == 1 ? String(localized: "1 file or folder can’t be read") : String(localized: "\(count) files or folders can’t be read")
        case .heldFile: return count == 1 ? String(localized: "1 file is held back") : String(localized: "\(count) files are held back")
        case .unavailable: return String(localized: "This copy can’t reach the server")
        case .rootGone: return String(localized: "The folder is missing where this copy is kept")
        case .settingsInvalid: return String(localized: "This copy’s settings file can’t be used")
        case .unwatched: return String(localized: "This copy isn’t watching for changes")
        case .paused: return String(localized: "Syncing is paused")
        }
    }

    /// The words under a copy's removals that wait: where they are decided, since only the copy that holds the files can.
    static let removalsLine = String(localized: "Review them where the copy is kept, with the command line: marfa folders confirm or marfa folders restore.")
}
