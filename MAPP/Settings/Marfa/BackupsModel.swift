import Foundation
import Marfa
import Observation

/// The Backups page: where the server keeps its backups and how often it takes one, the backups it holds with Restore on each,
/// and Back Up Now. Every call needs the server and is never queued. A restore asks first and needs a recent sign-in, which the
/// call shows in place; cancelled there, nothing is restored and the sheet stays. A folder typed and refused stays in its sheet.
@Observable @MainActor final class BackupsModel: OwnerDraftHolding {
    enum Sheet: Hashable {
        case folder
        case restore(BackupRecord)
    }

    private let context: OwnerContext

    private(set) var backups: [BackupRecord] = []
    /// Where and how often, which only a sign-in holding `config.manage` reads; nil without it.
    private(set) var settings: UpkeepSettings?
    /// Why the backups could not be read: the page says so in place of itself.
    private(set) var failure: OwnerFailure?
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    private(set) var sheet: Sheet?
    var folderDraft = ""
    /// Why the last folder or interval change, or the last restore, was refused, until the next one.
    private(set) var sheetError: String?
    private(set) var rowError: OwnerFailure?
    private(set) var isChanging = false

    private(set) var isBackingUp = false
    /// Why the last Back Up Now did not finish, under the Last Backup row.
    private(set) var backUpError: String?
    private(set) var isRestoring = false
    /// What the last restore did, shown at the top of the page until the next one.
    private(set) var restored: (backup: BackupRecord, outcome: BackupRestored)?

    init(context: OwnerContext) {
        self.context = context
    }

    // MARK: Reading

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            backups = try await context.calls.backups()
            failure = nil
        } catch {
            let error = UpkeepWording.owned(error)
            failure = error
            await context.learn(from: error)
            return
        }
        guard context.grants().contains(.configManage) else {
            settings = nil
            return
        }
        do {
            settings = try await context.calls.upkeepSettings()
        } catch {
            let error = UpkeepWording.owned(error)
            settings = nil
            await context.learn(from: error)
        }
    }

    /// The newest backup, which Last Backup tells.
    var latest: BackupRecord? { backups.first }

    /// Whether the server has nowhere to keep a backup, from the settings where they are read and from `reason` (the server's
    /// own health) where they are not.
    func hasDestination(reason: BackupsHealth.Reason?) -> Bool {
        if let settings { return settings.folder != nil || settings.objectStore }
        return reason != .noDestination
    }

    // MARK: Changing where and how often

    /// What the Keep Backups In pop-up shows.
    enum Place: Hashable { case nowhere, folder, objectStore }

    var place: Place? {
        guard let settings else { return nil }
        if settings.objectStore { return .objectStore }
        return settings.folder == nil ? .nowhere : .folder
    }

    func beginFolder() {
        folderDraft = settings?.folder ?? ""
        sheetError = nil
        sheet = .folder
    }

    var trimmedFolder: String { folderDraft.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The server takes an absolute path with no `..` in it.
    var folderIsValid: Bool {
        let path = trimmedFolder
        return path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    var canSaveFolder: Bool { !isChanging && folderIsValid && trimmedFolder != settings?.folder }

    func saveFolder() async {
        guard canSaveFolder, let settings else { return }
        sheetError = nil
        if await change(settings, .init(folder: .set(trimmedFolder)), refused: String(localized: "The server didn’t accept that folder. It must already exist on the machine it runs on."), line: { self.sheetError = $0 }) { sheet = nil }
    }

    func keepNowhere() async {
        guard let settings, settings.folder != nil else { return }
        rowError = nil
        _ = await change(settings, .init(folder: .remove), refused: nil, line: { _ in })
    }

    func setInterval(_ seconds: Int) async {
        guard let settings, settings.intervalSeconds != seconds else { return }
        rowError = nil
        _ = await change(settings, .init(intervalSeconds: seconds), refused: nil, line: { _ in })
    }

    /// Sends one change and reads the answer in. Whether it was kept.
    private func change(_ held: UpkeepSettings, _ change: UpkeepSettingsChange, refused: String?, line: (String) -> Void) async -> Bool {
        isChanging = true
        defer { isChanging = false }
        do {
            settings = try await context.calls.change(held, change)
            return true
        } catch {
            var said: String?
            if case .refused = error { said = refused }
            let error = UpkeepWording.owned(error)
            rowError = error
            line(said ?? OwnerWording.line(error, on: .backups))
            if error == .conflict || error == .instanceChanged { settings = try? await context.calls.upkeepSettings() }
            await context.learn(from: error)
            return false
        }
    }

    // MARK: Back Up Now

    func backUpNow(reason: BackupsHealth.Reason?) async {
        guard !isBackingUp else { return }
        guard hasDestination(reason: reason) else {
            backUpError = String(localized: "Choose where to keep backups first.")
            return
        }
        isBackingUp = true
        backUpError = nil
        defer { isBackingUp = false }
        do {
            let taken = try await context.calls.backUpNow()
            if taken.filesLost > 0 { backUpError = String(localized: "It was taken, but some files weren’t in it.") }
            backups = (try? await context.calls.backups()) ?? backups
        } catch {
            let error = UpkeepWording.owned(error)
            backUpError = OwnerWording.line(error, on: .backups)
            await context.learn(from: error)
        }
    }

    // MARK: Restore

    func beginRestore(_ backup: BackupRecord) {
        guard !isRestoring else { return }
        sheetError = nil
        sheet = .restore(backup)
    }

    func close() {
        guard !isRestoring, !isChanging else { return }
        sheet = nil
        sheetError = nil
    }

    func restore() async {
        guard case .restore(let backup)? = sheet, !isRestoring else { return }
        isRestoring = true
        sheetError = nil
        defer { isRestoring = false }
        do {
            let outcome = try await context.calls.restore(backup)
            restored = (backup, outcome)
            sheet = nil
            backups = (try? await context.calls.backups()) ?? backups
        } catch {
            let error = UpkeepWording.owned(error)
            // The sheet stays, so the owner can try again; a cancelled sign-in restores nothing.
            sheetError = OwnerWording.line(error, on: .backups)
            await context.learn(from: error)
        }
    }

    func dismissRestored() { restored = nil }

    /// A folder typed in its sheet and not sent goes back to the person when Settings closes.
    func takeDrafts() -> [OwnerDraft] {
        guard sheet == .folder, !trimmedFolder.isEmpty, trimmedFolder != settings?.folder else { return [] }
        defer { sheet = nil }
        return [.typed(title: String(localized: "Backup Folder Not Kept"), text: trimmedFolder)]
    }
}
