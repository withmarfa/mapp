import Marfa
import SwiftUI

struct BackupsPage: View {
    static let allBackups = SettingsSubpage(id: "all-backups", title: String(localized: "All Backups"))

    let host: any MarfaSettingsHost
    let showsAll: Bool
    @State private var model: BackupsModel
    @State private var selection: Set<String> = []
    @Environment(\.settingsNavigation) private var navigation

    /// `model` is the page's own unless a render brings one that holds a state the page cannot be driven into offscreen.
    init(host: any MarfaSettingsHost, showsAll: Bool, model: BackupsModel? = nil) {
        self.host = host
        self.showsAll = showsAll
        _model = State(initialValue: model ?? BackupsModel(context: OwnerContext(host: host)))
    }

    private var backupsHealth: BackupsHealth? { host.health.health?.backups }

    var body: some View {
        content
            .task(id: host.grants.contains(.configManage)) { await load() }
            .onAppear { host.ownerDrafts.register(model) }
            .settingsSheet(presenting: model.sheet != nil, dismiss: { model.close() }) {
                BackupSheet(model: model, serverName: host.serverName)
            }
            .accessibilityIdentifier("BackupsPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .backups, failure: failure, host: host) { Task { await load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else if showsAll {
            if let failure = model.listFailure {
                OwnerFailureState(page: .backups, failure: failure, host: host) { Task { await load() } }
            } else {
                allPage
            }
        } else {
            SettingsPageColumn {
                restored
                attention
                whereAndWhen
                list
            }
        }
    }

    private func load() async {
        let reader = host.health
        async let backups: Void = model.load()
        async let health: Void = reader.load()
        _ = await (backups, health)
    }

    private func backUp() {
        Task {
            await model.backUpNow(reason: backupsHealth?.reason)
            await host.health.load()
        }
    }

    // MARK: Restored

    @ViewBuilder private var restored: some View {
        if let done = model.restored {
            SettingsSection("Restored") {
                SettingsRow(
                    verbatim: String(localized: "Restored the backup from \(UpkeepWording.momentInSentence(done.backup.taken))"),
                    line: String(localized: "Added \(done.outcome.added.formatted()) items. \(done.outcome.alreadyHeld.formatted()) were already here."),
                    lead: .symbol("checkmark.circle")
                ) { SettingsButton("Close") { model.dismissRestored() } }
                if !done.outcome.secretsToSet.isEmpty {
                    let keys = done.outcome.secretsToSet
                    SettingsProblemRow(
                        title: Text(keys.count == 1 ? "1 secret to set again" : "\(keys.count) secrets to set again"),
                        line: Text(verbatim: UpkeepWording.secretsLine(keys, serverName: host.serverName)),
                        actions: UpkeepWording.secretsToSet(keys).known.isEmpty || !host.grants.contains(.configManage)
                            ? [] : [SettingsProblemAction("Show Monitoring") { host.show(.monitoring) }])
                }
            }
        }
    }

    // MARK: Needs attention

    @ViewBuilder private var attention: some View {
        if let health = backupsHealth {
            let failedRun = Self.failedRun(health)
            let problems = Self.otherProblems(health, showingFailedRun: failedRun != nil)
            if failedRun != nil || !problems.isEmpty {
                SettingsSection("Problems") {
                    if let failedRun {
                        SettingsRow(
                            title: Text("The last backup failed"), line: Text(verbatim: failedRun),
                            error: model.backUpError, lead: .tint("exclamationmark.triangle", .orange), lines: nil
                        ) {
                            backUpButton
                        }
                    }
                    ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                        SettingsProblemRow(
                            title: Text(verbatim: problem.title), line: Text(verbatim: problem.line),
                            actions: health.reason == .noDestination && model.settings != nil
                                ? [SettingsProblemAction("Choose Folder…") { model.beginFolder() }] : [])
                    }
                }
            }
        }
    }

    private static func otherProblems(_ health: BackupsHealth, showingFailedRun: Bool) -> [(title: String, line: String)] {
        guard showingFailedRun else { return UpkeepWording.problems(health) }
        var remaining = health
        remaining.state = .ok
        if remaining.reason == .destinationUnusable { remaining.reason = nil }
        remaining.faults.removeAll { fault in
            switch fault {
            case .runFailed, .destinationRefusing: true
            case .damagedParts, .filesWaiting: false
            }
        }
        return UpkeepWording.problems(remaining)
    }

    static func failedRun(_ health: BackupsHealth) -> String? {
        guard health.faults.contains(where: {
            if case .runFailed = $0 { return true }
            return false
        }) else { return nil }
        let reason: String
        switch (health.faults.contains(.destinationRefusing), health.destination) {
        case (true, .folder?):
            reason = String(localized: "Can’t reach the backup folder. Connect its disk, then back up.")
        case (true, .objectStore?):
            reason = String(localized: "The object store isn’t accepting backups. Check the store, then back up.")
        case (true, nil):
            reason = String(localized: "The backup destination isn’t available. Check where backups are kept, then back up.")
        default:
            reason = String(localized: "The server couldn’t finish the backup. Try backing up again.")
        }
        if let failedAt = health.lastFailedAt {
            return String(localized: "\(UpkeepWording.moment(failedAt)). \(reason)")
        }
        return reason
    }

    // MARK: Where and when

    private var hasDestination: Bool { model.hasDestination(reason: backupsHealth?.reason) }

    private var whereAndWhen: some View {
        VStack(spacing: SettingsTokens.Metric.pageSpacing) {
            SettingsSection("Where and When") {
                if let failure = model.settingsFailure {
                    OwnerProblemRow(
                        title: "Couldn’t read backup settings", failure: failure, page: .backups, host: host,
                        retry: { Task { await load() } })
                }
                keepIn
                if host.grants.contains(.configManage), model.place == .folder, let folder = model.settings?.folder {
                    SettingsRow(
                        title: Text("Folder"), line: Text("\(folder), on the machine this Marfa runs on."),
                        lineGlyph: .folder
                    ) {
                        SettingsButton("Change…") { model.beginFolder() }
                            .disabled(model.isChanging || model.settingsFailure != nil)
                    }
                }
                if host.grants.contains(.configManage), let settings = model.settings {
                    SettingsRow("Back up every", line: "Only when something changed.") {
                        SettingsPopUp(
                            title: "Back up every",
                            selection: Binding { settings.intervalSeconds } set: { choice in
                                if let choice { Task { await model.setInterval(choice) } }
                            }
                        ) {
                            if settings.intervalSeconds == nil { Text("Default").tag(nil as Int?) }
                            ForEach(intervals(holding: settings.intervalSeconds), id: \.self) { seconds in
                                Text(verbatim: UpkeepWording.interval(seconds)).tag(Optional(seconds))
                            }
                        }
                        .disabled(model.isChanging || model.settingsFailure != nil)
                    }
                } else if !host.grants.contains(.configManage) {
                    LockedInstanceRow(title: String(localized: "Back up every"), permission: .configManage, host: host)
                }
                lastBackup
            }
            if let failure = model.rowError {
                OwnerProblem(title: "Couldn’t change this", failure: failure, page: .backups, host: host)
            }
        }
    }

    private func intervals(holding current: Int?) -> [Int] {
        guard let current, !UpkeepWording.intervals.contains(current) else { return UpkeepWording.intervals }
        return (UpkeepWording.intervals + [current]).sorted()
    }

    @ViewBuilder private var keepIn: some View {
        if !host.grants.contains(.configManage) {
            SettingsLinkRow(
                verbatim: String(localized: "Keep backups in"), line: Self.destination(backupsHealth),
                lock: String(localized: "Not allowed")
            ) { host.askForMore(naming: InstancePermission.configManage.rawValue) }
            .disabled(host.isAllowingMore)
        } else if model.place == .objectStore {
            SettingsRow("Keep backups in", line: "Set on the machine that runs this Marfa.") { SettingsLockedValue(text: String(localized: "An Object Store")) }
        } else if let place = model.place {
            SettingsRow("Keep backups in") {
                SettingsPopUp(
                    title: "Keep backups in",
                    selection: Binding {
                        place
                    } set: { choice in
                        switch choice {
                        case .folder: if place != .folder { model.beginFolder() }
                        case .nowhere: Task { await model.keepNowhere() }
                        case .objectStore: break
                        }
                    }
                ) {
                    Text("Nowhere").tag(BackupsModel.Place.nowhere)
                    Text("A Folder").tag(BackupsModel.Place.folder)
                }
                .disabled(model.isChanging || model.settingsFailure != nil)
            }
        } else {
            SettingsRow("Keep backups in") { SettingsValue(verbatim: Self.destination(backupsHealth)) }
        }
    }

    /// Where backups go, as the server's health says it where the settings may not be read.
    static func destination(_ backups: BackupsHealth?) -> String {
        switch backups?.destination {
        case .folder?: String(localized: "A Folder")
        case .objectStore?: String(localized: "An Object Store")
        case nil: backups?.reason == .noDestination ? String(localized: "Nowhere") : String(localized: "Couldn’t check")
        }
    }

    private var backUpButton: some View {
        SettingsButton(verbatim: model.backUpButtonTitle, action: backUp)
            .disabled(model.isBackingUp || !hasDestination)
    }

    private var lastBackup: some View {
        let hasFailedRun = backupsHealth.flatMap(Self.failedRun) != nil
        return SettingsRow(
            title: Text("Last backup"), line: Text(verbatim: model.lastBackupLine(health: backupsHealth)),
            error: hasFailedRun ? nil : model.backUpError
        ) {
            if !hasFailedRun { backUpButton }
        }
    }

    // MARK: The backups

    private var columns: [SettingsTableColumn<BackupRecord>] {
        [
            SettingsTableColumn("Taken") { Text(verbatim: UpkeepWording.moment($0.taken)) },
            SettingsTableColumn("Size", width: SettingsTokens.Metric.Column.day, numeric: true) { Text(verbatim: UpkeepWording.size($0.bytes)).foregroundStyle(SettingsTokens.secondaryText) },
        ]
    }

    private var list: some View {
        let preview = SettingsTablePreview(total: model.backups.count)
        return SettingsSection("Backups") {
            if let failure = model.listFailure {
                OwnerProblemRow(title: "Couldn’t read backups", failure: failure, page: .backups, host: host) {
                    Task { await load() }
                }
            } else if model.backups.isEmpty {
                SettingsEmptyCard(
                    symbol: "externaldrive.badge.timemachine", title: Text("No Backups Yet"),
                    line: Text(hasDestination ? "Back Up Now takes the first." : "Choose where to keep backups first."))
            } else {
                ForEach(model.backups.prefix(preview.visibleCount)) { backup in
                    SettingsRow(verbatim: UpkeepWording.moment(backup.taken), line: UpkeepWording.size(backup.bytes)) {
                        SettingsButton("Restore…") { model.beginRestore(backup) }
                    }
                }
                if let count = preview.countLabel {
                    SettingsRow(verbatim: count, size: .compact) {
                        SettingsShowAllButton { navigation?.push(Self.allBackups) }
                    }
                }
            }
        }
    }

    private var allPage: some View {
        SettingsPageTable(
            rows: model.backups, columns: columns, count: Text("\(model.backups.count.formatted()) backups"), selection: $selection,
            filter: { EmptyView() },
            foot: {
                SettingsButton("Restore…", small: true) {
                    if let backup = model.backups.first(where: { selection.contains($0.id) }) { model.beginRestore(backup) }
                }
                .disabled(selection.count != 1)
            }
        )
        .accessibilityIdentifier("BackupsAllPage")
    }
}

struct BackupSheet: View {
    @Bindable var model: BackupsModel
    let serverName: String

    var body: some View {
        switch model.sheet {
        case .folder?: folder
        case .restore(let backup)?: restore(backup)
        case nil: EmptyView()
        }
    }

    private var folder: some View {
        SettingsSheet(
            title: Text("Backup Folder"), line: Text("A folder that already exists on the machine \(serverName) runs on.")
        ) {
            SettingsSheetField(label: "Folder", error: model.sheetError) {
                SettingsField(
                    title: "Folder", text: $model.folderDraft, prompt: "/Volumes/Backups", isError: model.sheetError != nil, isMonospaced: true,
                    width: nil, onSubmit: { Task { await model.saveFolder() } })
            }
        } buttons: {
            SettingsButton("Cancel") { model.close() }
            SettingsButton("Use Folder", role: .confirm) { Task { await model.saveFolder() } }
                .disabled(!model.canSaveFolder)
        }
    }

    private func restore(_ backup: BackupRecord) -> some View {
        SettingsSheet(
            title: Text("Restore the Backup From \(UpkeepWording.moment(backup.taken))"),
            line: Text("It adds what the backup holds and \(serverName) lacks. Items here stay as they are."), isWide: true
        ) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFieldGap) {
                SettingsSection("Not Restored", footer: "\(serverName) asks you to sign in again first.") {
                    ForEach(UpkeepWording.notRestored, id: \.title) { left in
                        SettingsRow(verbatim: left.title, lead: .symbol(left.symbol))
                    }
                }
                if let error = model.sheetError {
                    Text(verbatim: error).settingsFont(.line).foregroundStyle(SettingsTokens.errorRed).fixedSize(horizontal: false, vertical: true)
                }
            }
        } buttons: {
            SettingsButton("Cancel") { model.close() }.disabled(model.isRestoring)
            SettingsButton(model.isRestoring ? "Restoring…" : "Restore", role: .confirm, reserving: "Restoring…") { Task { await model.restore() } }
                .disabled(model.isRestoring)
        }
    }
}
