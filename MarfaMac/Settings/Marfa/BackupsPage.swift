import Marfa
import SwiftUI

/// The Backups page: where the server keeps its backups and how often it takes one, Back Up Now, and the backups it holds with
/// Show All opens a list where the owner can select a backup to restore.
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
            .task(id: host.serverAddress) {
                await model.load()
                await host.health.load()
            }
            .onAppear { host.ownerDrafts.register(model) }
            .settingsSheet(presenting: model.sheet != nil, dismiss: { model.close() }) {
                BackupSheet(model: model, serverName: host.serverName)
            }
            .accessibilityIdentifier("BackupsPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .backups, failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else if showsAll {
            allPage
        } else {
            SettingsPageColumn {
                restored
                attention
                whereAndWhen
                list
            }
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
        let problems = backupsHealth.map(UpkeepWording.problems) ?? []
        if !problems.isEmpty {
            SettingsSection("Needs Attention") {
                ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                    SettingsProblemRow(
                        title: Text(verbatim: problem.title), line: Text(verbatim: problem.line),
                        actions: backupsHealth?.reason == .noDestination && model.settings != nil
                            ? [SettingsProblemAction("Choose Folder…") { model.beginFolder() }] : [])
                }
            }
        }
    }

    // MARK: Where and when

    private var hasDestination: Bool { model.hasDestination(reason: backupsHealth?.reason) }

    private var whereAndWhen: some View {
        VStack(spacing: SettingsTokens.Metric.pageSpacing) {
            SettingsSection("Where and When") {
                if let failure = model.settingsFailure {
                    OwnerProblemRow(
                        title: "Couldn’t read backup settings", failure: failure, page: .backups, host: host,
                        retry: { Task { await model.load() } })
                }
                keepIn
                if model.place == .folder, let folder = model.settings?.folder {
                    SettingsRow(
                        verbatim: String(localized: "Folder"), line: String(localized: "\(folder), on the machine \(host.serverName) runs on."),
                        lead: .symbol("folder")
                    ) {
                        SettingsButton("Change…") { model.beginFolder() }
                    }
                }
                if let settings = model.settings {
                    SettingsRow("Back Up Every", line: "Only when something changed.") {
                        SettingsPopUp(
                            title: "Back Up Every",
                            selection: Binding { settings.intervalSeconds } set: { choice in Task { await model.setInterval(choice) } }
                        ) {
                            ForEach(intervals(holding: settings.intervalSeconds), id: \.self) { seconds in
                                Text(verbatim: UpkeepWording.interval(seconds)).tag(seconds)
                            }
                        }
                        .disabled(model.isChanging || model.settingsFailure != nil)
                    }
                }
                if hasDestination { lastBackup }
            }
            if let failure = model.rowError {
                OwnerProblem(title: "Couldn’t change this", failure: failure, page: .backups, host: host)
            }
        }
    }

    private func intervals(holding current: Int) -> [Int] {
        UpkeepWording.intervals.contains(current) ? UpkeepWording.intervals : (UpkeepWording.intervals + [current]).sorted()
    }

    @ViewBuilder private var keepIn: some View {
        if model.place == .objectStore {
            SettingsRow("Keep Backups In", line: "Set on the machine \(host.serverName) runs on.") { SettingsLockedValue(text: String(localized: "An Object Store")) }
        } else if let place = model.place {
            SettingsRow("Keep Backups In") {
                SettingsPopUp(
                    title: "Keep Backups In",
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
            SettingsRow("Keep Backups In") { SettingsValue(verbatim: Self.destination(backupsHealth)) }
        }
    }

    /// Where backups go, as the server's health says it where the settings may not be read.
    static func destination(_ backups: BackupsHealth?) -> String {
        switch backups?.destination {
        case .folder?: String(localized: "A Folder")
        case .objectStore?: String(localized: "An Object Store")
        case nil: backups?.reason == .noDestination ? String(localized: "Nowhere") : String(localized: "Couldn’t Check")
        }
    }

    private var lastBackup: some View {
        let taken = model.latest?.taken ?? backupsHealth?.lastBackup
        return SettingsRow(
            verbatim: String(localized: "Last Backup"), line: taken.map { UpkeepWording.moment($0) + "." } ?? String(localized: "None yet."),
            error: model.backUpError
        ) {
            SettingsButton(model.isBackingUp ? "Backing Up…" : "Back Up Now", reserving: "Backing Up…") {
                Task { await model.backUpNow(reason: backupsHealth?.reason) }
            }
            .disabled(model.isBackingUp)
        }
    }

    // MARK: The backups

    private var columns: [SettingsTableColumn<BackupRecord>] {
        [
            SettingsTableColumn("Taken") { Text(verbatim: UpkeepWording.moment($0.taken)) },
            SettingsTableColumn("Size", width: SettingsTokens.Metric.Column.day, numeric: true) { Text(verbatim: UpkeepWording.size($0.bytes)).foregroundStyle(SettingsTokens.secondaryText) },
        ]
    }

    @ViewBuilder private var list: some View {
        SettingsSection(name: Text("Backups of \(host.serverName)")) {
            if model.backups.isEmpty {
                SettingsEmptyCard(
                    symbol: "externaldrive.badge.timemachine", title: Text("No Backups Yet"),
                    line: Text(hasDestination ? "Back Up Now takes the first." : "The first is taken once there is somewhere to keep it."))
            } else {
                SettingsSectionTable(
                    rows: model.backups, columns: columns,
                    action: SettingsRowAction(title: "Restore…") { model.beginRestore($0) },
                    showAll: { navigation?.push(Self.allBackups) })
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
            SettingsButton("Use Folder…", role: .confirm) { Task { await model.saveFolder() } }
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
            SettingsButton(model.isRestoring ? "Restoring…" : "Restore…", role: .confirm, reserving: "Restoring…") { Task { await model.restore() } }
                .disabled(model.isRestoring)
        }
    }
}
