import Foundation
import Marfa
import Observation

/// The Folders page: the synced folders the server lists, each with what its copies last reported and its settings, which
/// the page changes in place through the working copy. Each change is sent on the version the person saw when they began
/// it: a change made somewhere else since is told and never written over, a read arriving meanwhile leaves what is being
/// typed alone, and a refused change keeps what was typed.
@Observable @MainActor final class FoldersModel: OwnerDraftHolding {
    /// How a folder or a copy stands, in the words a row says at its trailing edge.
    struct Condition: Equatable {
        enum Tone: Equatable { case ok, warning, quiet }

        let title: String
        let tone: Tone
    }

    /// A setting of a folder's page that is changed in place, under which a refusal is told.
    enum Setting: Hashable {
        case title, ignore, include, removalLimit, additionLimit, stopSyncing
    }

    /// Stop Syncing, or a looser safety limit, waiting on the owner's answer. Nothing is sent before it.
    struct Question: Identifiable, Equatable {
        enum Kind: Equatable {
            case stop
            /// A limit raised to `files`, which pauses less.
            case loosen(Setting, files: UInt64)
        }

        let id = UUID()
        let folder: String
        let kind: Kind
        let title: String
        let message: String
        let button: String
    }

    private let context: OwnerContext
    private let folderCalls: any FolderCalls

    private(set) var folders: [OwnerFolder] = []
    /// How many folders the server holds, which is more than `folders` where the overview cut its list.
    private(set) var total = 0
    private(set) var reports: [String: FolderReport] = [:]
    /// Why a folder's report could not be read, by the folder's id.
    private(set) var reportFailures: [String: OwnerFailure] = [:]
    /// Each folder's settings as last read or answered, by the folder's id.
    private(set) var settings: [String: FolderSettingsReading] = [:]
    private(set) var settingsFailures: [String: OwnerFailure] = [:]
    private let loader = OwnerLoader()
    var failure: OwnerFailure? { loader.failure }
    var hasLoaded: Bool { loader.hasLoaded }

    /// The folder whose page is open, which the drafts below belong to.
    private(set) var editing: String?
    /// A pattern being added to Ignore or Include; nil while the row only offers to add one.
    var ignoreDraft: String?
    var includeDraft: String?
    var removalDraft = ""
    var additionDraft = ""
    var renameDraft = ""
    private(set) var isRenaming = false
    /// The reading each change under way began on, whose version it is sent on.
    private var bases: [Setting: FolderSettingsReading] = [:]
    /// Why a change was not kept, by the setting it was made in.
    private(set) var errors: [Setting: String] = [:]
    /// The settings whose change was refused, which only Return sends again.
    private var refused: Set<Setting> = []
    private(set) var sending: Set<Setting> = []
    private(set) var question: Question?
    /// The folder just stopped here, so its page goes back.
    private(set) var stopped: String?

    init(context: OwnerContext, folderCalls: any FolderCalls) {
        self.context = context
        self.folderCalls = folderCalls
    }

    func folder(_ id: String) -> OwnerFolder? { folders.first { $0.id == id } }

    /// Reads the list, which the page shows at once, then each folder's report and settings a few at a time.
    func load() async {
        await loader.load(in: context, primary: { () throws(OwnerFailure) in
            let listing = try await context.calls.folders()
            folders = listing.folders
            total = listing.total
        }, showBeforeFinishing: true, after: {
            let calls = context.calls
            let folderCalls = folderCalls
            await readEach(
                of: folders.map(\.id),
                read: { id -> (Result<FolderReport, OwnerFailure>, Result<FolderSettingsReading, OwnerFailure>) in
                    let report: Result<FolderReport, OwnerFailure>
                    do throws(OwnerFailure) { report = .success(try await calls.folderReport(id)) } catch { report = .failure(error) }
                    let read: Result<FolderSettingsReading, OwnerFailure>
                    do throws(OwnerFailure) { read = .success(try await folderCalls.settings(of: id)) } catch { read = .failure(error) }
                    return (report, read)
                },
                take: { id, answers in
                    await takeReport(answers.0, for: id)
                    await takeSettings(answers.1, for: id)
                })
        })
    }

    /// Reads one folder again, for its page.
    func loadFolder(_ id: String) async {
        do throws(OwnerFailure) {
            await takeReport(.success(try await context.calls.folderReport(id)), for: id)
        } catch {
            await takeReport(.failure(error), for: id)
        }
        await readSettings(id)
    }

    func loadReport(_ id: String) async {
        do throws(OwnerFailure) {
            await takeReport(.success(try await context.calls.folderReport(id)), for: id)
        } catch {
            await takeReport(.failure(error), for: id)
        }
    }

    private func readSettings(_ id: String) async {
        do throws(OwnerFailure) {
            await takeSettings(.success(try await folderCalls.settings(of: id)), for: id)
        } catch {
            await takeSettings(.failure(error), for: id)
        }
    }

    private func takeReport(_ answer: Result<FolderReport, OwnerFailure>, for id: String) async {
        switch answer {
        case .success(let report):
            reports[id] = report
            reportFailures[id] = nil
        case .failure(let error):
            reportFailures[id] = error
            if error == .notFound { forget(id) }
            await context.learn(from: error)
        }
    }

    private func takeSettings(_ answer: Result<FolderSettingsReading, OwnerFailure>, for id: String) async {
        switch answer {
        case .success(let read):
            guard !read.isStopped else { return forget(id) }
            settings[id] = read
            settingsFailures[id] = nil
            if let index = folders.firstIndex(where: { $0.id == id }), !read.title.isEmpty { folders[index].title = read.title }
            if editing == id { fillLimits(from: read) }
        case .failure(let error):
            settingsFailures[id] = error
            if error == .notFound { forget(id) }
            await context.learn(from: error)
        }
    }

    /// A folder stopped or removed elsewhere leaves the list, and its page says it is gone.
    private func forget(_ id: String) {
        folders.removeAll { $0.id == id }
        settings[id] = nil
    }

    // MARK: A folder's page

    /// Opens `id`'s page: the drafts are its own, and what another folder's page held goes.
    func open(_ id: String) {
        guard editing != id else { return }
        editing = id
        ignoreDraft = nil
        includeDraft = nil
        errors = [:]
        refused = []
        bases = [:]
        isRenaming = false
        question = nil
        if let read = settings[id] { fillLimits(from: read) }
    }

    /// Shows each limit as read, but where the person has typed one: what they typed stays, with the reading they began on.
    private func fillLimits(from read: FolderSettingsReading) {
        for setting in [Setting.removalLimit, .additionLimit] {
            let now = String(Self.limit(setting, of: read))
            if let base = bases[setting], limitDraft(setting) != String(Self.limit(setting, of: base)), limitDraft(setting) != now {
                continue
            }
            setLimitDraft(setting, now)
            bases[setting] = read
            errors[setting] = nil
            refused.remove(setting)
        }
    }

    private func limitDraft(_ setting: Setting) -> String { setting == .removalLimit ? removalDraft : additionDraft }

    private func setLimitDraft(_ setting: Setting, _ text: String) {
        if setting == .removalLimit { removalDraft = text } else { additionDraft = text }
    }

    private static func limit(_ setting: Setting, of read: FolderSettingsReading) -> UInt64 {
        setting == .removalLimit ? read.removalLimit : read.additionLimit
    }

    func beginRename() {
        guard let id = editing, let read = settings[id] else { return }
        renameDraft = read.title
        bases[.title] = read
        errors[.title] = nil
        isRenaming = true
    }

    func cancelRename() {
        isRenaming = false
        bases[.title] = nil
        errors[.title] = nil
    }

    var canRename: Bool { !renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending.contains(.title) }

    func rename() async {
        let title = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canRename, let base = bases[.title] else { return }
        guard title != base.title else { return cancelRename() }
        if await send(.title(title), in: .title, on: base) { cancelRename() }
    }

    func beginAdding(to setting: Setting) {
        guard let read = editingSettings else { return }
        switch setting {
        case .ignore: ignoreDraft = ignoreDraft ?? ""
        case .include: includeDraft = includeDraft ?? ""
        default: return
        }
        if bases[setting] == nil { bases[setting] = read }
        errors[setting] = nil
        refused.remove(setting)
    }

    /// Adds what was typed to Ignore or Include, exactly as typed: a space in a pattern is part of it. An empty pattern
    /// adds nothing and ends the adding. Leaving the field (`explicitly` false) sends nothing a refusal holds, which only
    /// Return sends again.
    func addPattern(to setting: Setting, explicitly: Bool = true) async {
        guard let base = bases[setting] else { return }
        let pattern = (setting == .ignore ? ignoreDraft : includeDraft) ?? ""
        guard !pattern.isEmpty else { return endAdding(setting) }
        guard explicitly || !refused.contains(setting) else { return }
        let held = Self.patterns(setting, of: base)
        guard !held.contains(pattern) else {
            errors[setting] = String(localized: "It’s in the list already.")
            return
        }
        let change: FolderSettingChange = setting == .ignore ? .ignore(held + [pattern]) : .include(held + [pattern])
        if await send(change, in: setting, on: base) { endAdding(setting) }
    }

    func endAdding(_ setting: Setting) {
        if setting == .ignore { ignoreDraft = nil } else { includeDraft = nil }
        bases[setting] = nil
        errors[setting] = nil
        refused.remove(setting)
    }

    /// Removes the one entry at `index` of the list `shown` holds, on its version, leaving any equal entry.
    func removePattern(at index: Int, from setting: Setting, in shown: FolderSettingsReading) async {
        var kept = Self.patterns(setting, of: shown)
        guard kept.indices.contains(index) else { return }
        kept.remove(at: index)
        await send(setting == .ignore ? .ignore(kept) : .include(kept), in: setting, on: shown)
    }

    private static func patterns(_ setting: Setting, of read: FolderSettingsReading) -> [String] {
        setting == .ignore ? read.ignore : read.include
    }

    /// Sends the limit typed, where it differs from the one the person began on; a number the server cannot take is refused
    /// before. A larger limit pauses less, so it asks first. Leaving the field (`explicitly` false) sends nothing a refusal
    /// holds, so a change made elsewhere is written over only by Return.
    func commitLimit(_ setting: Setting, explicitly: Bool = true) async {
        guard let id = editing, setting == .removalLimit || setting == .additionLimit, let base = bases[setting] ?? settings[id] else {
            return
        }
        guard explicitly || !refused.contains(setting) else { return }
        guard let files = UInt64(limitDraft(setting).trimmingCharacters(in: .whitespaces)), files <= Self.largestLimit else {
            errors[setting] = Self.rangeLine
            return
        }
        let held = Self.limit(setting, of: base)
        guard files != held else {
            errors[setting] = nil
            refused.remove(setting)
            if let read = settings[id] { fillLimits(from: read) }
            return
        }
        guard files < held else {
            let kind = Question.Kind.loosen(setting, files: files)
            if question?.kind != kind { question = Self.loosening(setting, folder: id, from: held, to: files) }
            return
        }
        await sendLimit(setting, files: files, on: base)
    }

    /// Only the number of files changes; the rest of the threshold is sent as the person saw it.
    private func sendLimit(_ setting: Setting, files: UInt64, on base: FolderSettingsReading) async {
        let change: FolderSettingChange =
            if setting == .removalLimit {
                .removalThreshold(RemovalThreshold(files: files, fraction: base.removalThreshold.fraction, ceiling: base.removalThreshold.ceiling))
            } else {
                .additionThreshold(AdditionThreshold(files: files, fraction: base.additionThreshold.fraction))
            }
        await send(change, in: setting, on: base)
    }

    /// The largest whole number a folder's limit takes.
    static let largestLimit: UInt64 = 9_007_199_254_740_991

    static var rangeLine: String { String(localized: "Enter a whole number from 0 to \(largestLimit.formatted()).") }

    /// Sends one change on the version `base` holds and takes the answer. A change made elsewhere since is told with what
    /// it is now, which the next send is based on, and what was typed stays to be sent again.
    @discardableResult
    private func send(_ change: FolderSettingChange, in setting: Setting, on base: FolderSettingsReading) async -> Bool {
        guard !sending.contains(setting) else { return false }
        sending.insert(setting)
        defer { sending.remove(setting) }
        errors[setting] = nil
        refused.remove(setting)
        do throws(OwnerFailure) {
            let answer = try await folderCalls.change(base.id, change, baseVersion: base.version)
            if bases[setting] != nil { bases[setting] = answer }
            await takeSettings(.success(answer), for: base.id)
            return true
        } catch {
            errors[setting] = Self.line(error)
            refused.insert(setting)
            if error == .notFound { forget(base.id) }
            if error == .conflict {
                await readSettings(base.id)
                if let now = settings[base.id] {
                    errors[setting] = Self.conflictLine(setting, now: now)
                    if bases[setting] != nil { bases[setting] = now }
                }
            }
            await context.learn(from: error)
            return false
        }
    }

    private var editingSettings: FolderSettingsReading? { editing.flatMap { settings[$0] } }

    // MARK: Stop Syncing

    /// Asks before stopping. Nothing is sent until the owner agrees.
    func askToStop() {
        guard let id = editing, let title = settings[id]?.title ?? folder(id)?.title else { return }
        errors[.stopSyncing] = nil
        question = Question(
            folder: id, kind: .stop, title: String(localized: "Stop syncing \(title)?"),
            message: String(localized: "Each copy stops the next time it syncs. You can’t sync this folder again. Its items stay in Marfa and its files stay on disk. Push any unsent changes from each copy before stopping. Afterward, use marfa folders remove to detach each directory and keep its files as plain files."),
            button: String(localized: "Stop Syncing"))
    }

    /// The question before a limit is raised, naming the limit the person saw and the one typed.
    private static func loosening(_ setting: Setting, folder: String, from held: UInt64, to files: UInt64) -> Question {
        let kind = Question.Kind.loosen(setting, files: files)
        let button = String(localized: "Raise Limit")
        return if setting == .removalLimit {
            Question(
                folder: folder, kind: kind, title: String(localized: "Allow more removals before pausing?"),
                message: String(localized: "Pause Removals Over changes from \(held) to \(files) files. More files can then be removed at once before a copy stops to ask."),
                button: button)
        } else {
            Question(
                folder: folder, kind: kind, title: String(localized: "Allow more additions before pausing?"),
                message: String(localized: "Pause Additions Over changes from \(held) to \(files) files. More new files can then be added at once before a copy stops to ask."),
                button: button)
        }
    }

    /// Keeping things as they were puts a raised limit back as it was read.
    func cancelQuestion() {
        guard let asked = question else { return }
        question = nil
        if case .loosen(let setting, _) = asked.kind, asked.folder == editing {
            errors[setting] = nil
            refused.remove(setting)
            if let base = bases[setting] { setLimitDraft(setting, String(Self.limit(setting, of: base))) }
            if let id = editing, let read = settings[id] { fillLimits(from: read) }
        }
    }

    func confirm(_ asked: Question) async {
        question = nil
        if case .loosen(let setting, let files) = asked.kind {
            guard asked.folder == editing, let base = bases[setting] else { return }
            return await sendLimit(setting, files: files, on: base)
        }
        guard !sending.contains(.stopSyncing) else { return }
        sending.insert(.stopSyncing)
        defer { sending.remove(.stopSyncing) }
        do throws(OwnerFailure) {
            try await folderCalls.stopSyncing(asked.folder)
        } catch {
            // A stop whose answer was lost may have been made: the folder is read again to tell.
            await readSettings(asked.folder)
            guard folder(asked.folder) == nil else {
                errors[.stopSyncing] = Self.line(error)
                await context.learn(from: error)
                return
            }
        }
        forget(asked.folder)
        reports[asked.folder] = nil
        total = max(0, total - 1)
        stopped = asked.folder
    }

    // MARK: Drafts

    func takeDrafts() -> [OwnerDraft] {
        guard let id = editing, let read = settings[id] else { return [] }
        var drafts: [OwnerDraft] = []
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if isRenaming, !name.isEmpty, name != read.title {
            drafts.append(.typed(title: String(localized: "Folder Not Renamed"), text: name))
        }
        for typed in [ignoreDraft, includeDraft].compactMap(\.self) where !typed.isEmpty {
            drafts.append(.typed(title: String(localized: "Pattern Not Added"), text: typed))
        }
        for setting in [Setting.removalLimit, .additionLimit] {
            let typed = limitDraft(setting)
            let held = String(Self.limit(setting, of: bases[setting] ?? read))
            if typed != held, !typed.isEmpty { drafts.append(.typed(title: String(localized: "Limit Not Changed"), text: typed)) }
        }
        isRenaming = false
        ignoreDraft = nil
        includeDraft = nil
        question = nil
        errors = [:]
        refused = []
        bases = [:]
        fillLimits(from: read)
        return drafts
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
        count == 1 ? String(localized: "1 removal waits on \(signIn)") : String(localized: "\(count) removals wait on \(signIn)")
    }

    /// The current file-count threshold may differ from the one used in the copy’s last report.
    static func removalsLine(limit: UInt64?) -> String {
        guard let limit else { return String(localized: "Review them where it runs.") }
        return String(localized: "The current file-count threshold is \(limit). Review the removals where this copy runs.")
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

    /// The words under a copy's problem: which copy reports it and where it is looked into.
    static func problemLine(signIn: String) -> String {
        String(localized: "Reported by \(signIn). Review it where that copy runs.")
    }

    /// What a refused change says under its setting.
    static func line(_ failure: OwnerFailure) -> String {
        if failure == .notFound { return String(localized: "This folder was stopped somewhere else.") }
        return OwnerWording.line(failure, on: .folders)
    }

    /// What a change refused because the same setting changed elsewhere says, with what it is now, so sending it again is
    /// the owner's choice.
    static func conflictLine(_ setting: Setting, now: FolderSettingsReading) -> String {
        switch setting {
        case .title:
            String(localized: "It was renamed “\(now.title)” somewhere else, so yours wasn’t kept. Rename again to use yours.")
        case .removalLimit:
            String(localized: "It was changed to \(now.removalLimit) somewhere else, so yours wasn’t kept. Press Return to use yours.")
        case .additionLimit:
            String(localized: "It was changed to \(now.additionLimit) somewhere else, so yours wasn’t kept. Press Return to use yours.")
        case .ignore, .include:
            String(localized: "The list changed somewhere else, so the app read it again. Nothing was changed.")
        case .stopSyncing:
            OwnerWording.line(.conflict)
        }
    }

    /// What a folder holds, as the list and the Folder section say it: its types and its tier.
    static func holds(_ read: FolderSettingsReading, plural: (String) -> String) -> String {
        let types = types(read, plural: plural)
        return switch read.tier {
        case .library?, nil: String(localized: "\(types) in the library.")
        case .feed?: String(localized: "\(types) in the feed.")
        case .all?: String(localized: "\(types) in the library and the feed.")
        }
    }

    /// The types a folder holds, as its Folder section says them.
    static func types(_ read: FolderSettingsReading, plural: (String) -> String) -> String {
        read.types.isEmpty ? String(localized: "Everything") : read.types.map(plural).formatted(.list(type: .and))
    }

    /// The tier a folder holds from.
    static func tier(_ read: FolderSettingsReading) -> String {
        switch read.tier {
        case .library?, nil: String(localized: "Library")
        case .feed?: String(localized: "Feed")
        case .all?: String(localized: "Library and Feed")
        }
    }
}
