import AppKit
import SwiftUI

/// Shows the space used by the local copy and its offline files, with controls for exports and downloads.
struct OnThisMacPage: View {
    let openConnection: () -> Void
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library
    @State private var downloads: DownloadedFileState?
    @State private var storeBytes: UInt64?
    @State private var isWorking = false
    @State private var readFailed = false
    @State private var actionFailure: String?
    @State private var isExporting = false
    @State private var exportFailure: String?
    @State private var exported: String?
    @State private var isChoosingExportFolder = false
    @State private var automaticFailure: String?
    @State private var isConfirmingDownload = false

    private static let sizes: [UInt64] = [1, 5, 10, 25, 100].map { $0 * 1_000_000_000 }

    private var host: MarfaHost { libraries.host }
    private var name: String { LibraryDescription.name(libraries) }
    private var canAskServer: Bool { host.state == .online }
    private var isFilling: Bool { DownloadAgainRow.isFilling(library?.syncReport.fill, in: host.state) }

    var body: some View {
        Group {
            if let library, library.downloadedFiles != nil, let connection = host.configuredConnection {
                page(library: library, connection: connection)
            } else {
                SettingsPageState(
                    symbol: "laptopcomputer", title: Text("No Marfa Open"),
                    line: Text("Connect to a Marfa in Connection to see what the app keeps of it."),
                    action: ("Open Connection…", openConnection))
            }
        }
        .accessibilityIdentifier("OnThisMacPage")
    }

    private func page(library: any ItemLibrary, connection: MarfaConnection) -> some View {
        SettingsPageColumn {
            SettingsHead(
                symbol: "laptopcomputer", tone: .gray, title: Text("\(name) on This Mac"),
                line: Text(verbatim: headLine)
            )
            .accessibilityIdentifier("LibrarySummary")
            files(library.downloadedFiles)
            export(connection: connection)
            startAgain(library: library)
        }
        .alert("Download Everything Again?", isPresented: $isConfirmingDownload) {
            Button("Cancel", role: .cancel) {}
            Button("Download Again") { library.downloadEverythingAgain() }
        } message: {
            Text(Self.downloadMessage(name: name, unsent: host.waitingChanges ?? 0))
        }
        .task(id: ObjectIdentifier(library)) {
            let directory = libraries.host.location.directory(for: connection)
            await StoreSize.keepSumming { await sum(directory: directory) }
        }
        .onChange(of: isFilling) { _, filling in
            guard !filling else { return }
            let directory = libraries.host.location.directory(for: connection)
            Task { await sum(directory: directory) }
        }
    }

    private var headLine: String {
        let kept = String(localized: "Kept here so the app works offline and searches fast.")
        return storeBytes.map { "\(StoreSize.text($0)). \(kept)" } ?? kept
    }

    // MARK: Files

    @ViewBuilder private func files(_ source: (any DownloadedFiles)?) -> some View {
        if let source {
            SettingsSection("Files") {
                if let state = downloads {
                    SettingsRow(title: Text("Keep Opened Files"), line: Text(verbatim: budgetLine(state))) {
                        SettingsPopUp(
                            title: "Keep Opened Files",
                            selection: Binding(get: { state.budget }, set: { budget in change { try await source.setBudget(budget) } })
                        ) {
                            Text("Automatic").tag(DownloadBudget.automatic)
                            ForEach(Self.sizes, id: \.self) { bytes in
                                Text(StoreSize.text(bytes)).tag(DownloadBudget.bytes(bytes))
                            }
                            if case .bytes(let bytes) = state.budget, !Self.sizes.contains(bytes) {
                                Text(StoreSize.text(bytes)).tag(state.budget)
                            }
                            Text("Keep All Downloads").tag(DownloadBudget.keepAll)
                        }
                        .disabled(isWorking)
                        .accessibilityIdentifier("KeepOpenedFiles")
                    }
                    attachments(state)
                    SettingsRow(
                        title: Text("Opened Files"),
                        line: Text("\(state.bytes.map(StoreSize.text) ?? String(localized: "Unavailable")), fetched again when you open them.")
                    ) {
                        SettingsButton("Clear") { change { try await source.removeDownloadedFiles() } }
                            .disabled(isWorking)
                            .accessibilityIdentifier("RemoveDownloadedFiles")
                    }
                } else if !readFailed {
                    SettingsRow("Reading Downloaded Files…") { ProgressView().controlSize(.small) }
                }
                if readFailed {
                    SettingsProblemRow(title: Text("Couldn’t Read Downloaded Files"), line: Text("The app will try again."), actions: [])
                }
                if let actionFailure {
                    SettingsRow(verbatim: actionFailure, size: .compact, lines: nil) {}
                }
            }
            .accessibilityIdentifier("LibraryDownloads")
        }
    }

    @ViewBuilder private func attachments(_ state: DownloadedFileState) -> some View {
        if let attachments = state.attachments {
            SettingsRow("Attachments", line: "Always kept, so they open offline.") {
                SettingsValue(verbatim: StoreSize.text(attachments.heldBytes))
            }
            if attachments.missing > 0 {
                SettingsRow(
                    title: Text("Attachments Not Yet Offline"), line: DownloadWording.line(attachments.reasons).map { Text(verbatim: $0) },
                    lines: nil
                ) {
                    SettingsValue(verbatim: attachments.missing.formatted())
                }
            }
        } else {
            SettingsRow("Attachment counts aren’t available.", size: .compact) {}
        }
    }

    private func budgetLine(_ state: DownloadedFileState) -> String {
        let standing = String(localized: "The least used go first when there’s no room.")
        guard state.budget == .automatic, let limit = state.limit else { return standing }
        return String(localized: "Up to \(StoreSize.text(limit)) now. \(standing)")
    }

    // MARK: Export

    private func export(connection: MarfaConnection) -> some View {
        let line = !canAskServer
            ? String(localized: "Needs \(name) to answer.")
            : exported ?? String(localized: "An archive \(name), or any Marfa, can restore.")
        return SettingsSection("Export") {
            SettingsRow(
                title: Text("Export Everything"), line: Text(verbatim: line), error: exportFailure, look: canAskServer ? .normal : .off
            ) {
                HStack(spacing: SettingsTokens.Metric.buttonGap) {
                    if isExporting { ProgressView().controlSize(.small) }
                    SettingsButton("Export…") { exportEverything(connection: connection) }
                        .disabled(isExporting || isChoosingExportFolder)
                        .accessibilityIdentifier("ExportEverything")
                }
            }
            .accessibilityIdentifier("ExportRow")
            automaticRows
        }
    }

    // MARK: Export Automatically

    @ViewBuilder private var automaticRows: some View {
        let automatic = libraries.automaticExport
        let instance = automatic.openInstance
        let plan = automatic.current
        let schedule = plan?.schedule ?? .never
        SettingsRow(title: Text("Export Automatically"), line: Text(verbatim: automaticLine(plan)), error: automaticFailure) {
            SettingsPopUp(
                title: "Export Automatically",
                selection: Binding(get: { schedule }, set: { new in if let instance { choose(new, plan: plan, for: instance) } })
            ) {
                Text("Never").tag(ExportSchedule.never)
                Text("Every Day").tag(ExportSchedule.daily)
                Text("Every Week").tag(ExportSchedule.weekly)
            }
            // A plan belongs to a Marfa by its instance id, so it can be set once the copy knows it.
            .disabled(instance == nil)
            .accessibilityIdentifier("ExportAutomatically")
        }
        .accessibilityIdentifier("ExportAutomaticallyRow")
        .task(id: host.configuredConnection) { await automatic.learn() }
        if schedule != .never, let folder = plan?.folder, let instance {
            SettingsRow(title: Text("Export Folder"), line: Text(verbatim: (folder.path as NSString).abbreviatingWithTildeInPath)) {
                SettingsButton("Choose…") {
                    chooseAutomaticFolder { chosen in
                        automatic.set(schedule, folder: chosen, for: instance)
                        automatic.checkSoon()
                    }
                }
                .accessibilityIdentifier("ExportFolder")
            }
        }
    }

    private func automaticLine(_ plan: ExportPlan?) -> String {
        guard let plan, plan.schedule != .never, let folder = plan.folder else { return String(localized: "To a folder you choose.") }
        let to = String(localized: "To “\(folder.url.lastPathComponent)”.")
        guard let last = plan.last else { return to }
        return to + " " + String(localized: "Last saved \(last.formatted(.dateTime.day().month().year())).")
    }

    /// A schedule is turned on only with a folder, asked for the first time for this Marfa; a cancelled or refused chooser
    /// leaves it as it was, and a folder chosen after another Marfa opened is not kept.
    private func choose(_ new: ExportSchedule, plan: ExportPlan?, for instance: String) {
        let automatic = libraries.automaticExport
        guard new != .never, plan?.folder == nil else {
            automaticFailure = nil
            automatic.set(new, for: instance)
            automatic.checkSoon()
            return
        }
        chooseAutomaticFolder { folder in
            automatic.set(new, folder: folder, for: instance)
            automatic.checkSoon()
        }
    }

    /// Asks for the folder, checks it, and calls `done` only with one chosen that an export can write to; a refused folder
    /// is told on the row.
    private func chooseAutomaticFolder(then done: @escaping (ExportFolder) -> Void) {
        Task {
            guard let folder = await Self.chooseFolder(
                prompt: String(localized: "Choose"), message: String(localized: "Choose where the app saves the archive."))
            else { return }
            switch await LibraryExport.choose(folder) {
            case .success(let chosen):
                automaticFailure = nil
                done(chosen)
            case .failure(let failure):
                automaticFailure = failure.message
            }
        }
    }

    private static func chooseFolder(prompt: String, message: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = message
        return await withCheckedContinuation { continuation in
            panel.begin { response in continuation.resume(returning: response == .OK ? panel.url : nil) }
        }
    }

    private func exportEverything(connection: MarfaConnection) {
        guard !isExporting, !isChoosingExportFolder else { return }
        isChoosingExportFolder = true
        exportFailure = nil
        exported = nil
        let source = MarfaArchiveSource(calls: MarfaServerCalls(connection: connection, signIns: host.signIns))
        let server = name
        let automatic = libraries.automaticExport
        Task {
            defer {
                isChoosingExportFolder = false
                isExporting = false
            }
            let result = await Self.exportEverything(
                from: source, serverName: server, instance: { await automatic.learn() },
                folder: {
                    let folder = await Self.chooseFolder(
                        prompt: String(localized: "Export"), message: String(localized: "Choose where to save the archive."))
                    isExporting = folder != nil
                    return folder
                })
            switch result {
            case .success(let line): exported = line
            case .failure(let failure): exportFailure = failure.message
            case nil: break
            }
        }
    }

    /// Exports the archive of the Marfa the copy says it is when Export… is pressed, `instance`, asked before the
    /// `folder` chooser opens, so a Marfa opened or answering at the address afterwards is refused. Answers the line to
    /// show, or nil where no folder was chosen. Where the copy can't yet say which Marfa it is, it refuses before asking.
    static func exportEverything(
        from source: any ArchiveSource, serverName: String, instance: () async -> String?, folder: () async -> URL?
    ) async -> Result<String, LibraryExport.Failure>? {
        guard let instance = await instance() else {
            return .failure(.init(message: String(localized: "Couldn’t export. The app can’t yet tell which Marfa \(serverName) is.")))
        }
        guard let folder = await folder() else { return nil }
        do {
            let export = try await LibraryExport.export(from: source, serverName: serverName, to: folder, instance: instance)
            let saved = String(localized: "Saved as “\(export.file.lastPathComponent)”.")
            return .success(LibraryExport.lacking(export, serverName: serverName).map { "\(saved) \($0)" } ?? saved)
        } catch {
            return .failure(error)
        }
    }

    // MARK: Start again

    private func startAgain(library: any ItemLibrary) -> some View {
        SettingsSection("Start Again") {
            SettingsRow(
                title: Text("Download Everything Again"),
                line: Text(verbatim: DownloadAgainRow.line(name: name, fill: library.syncReport.fill, in: host.state)).monospacedDigit(),
                look: canAskServer ? .normal : .off
            ) {
                SettingsButton("Download Again…") { isConfirmingDownload = true }
                    .disabled(isFilling)
                    .accessibilityIdentifier("DownloadAgain")
            }
            .accessibilityIdentifier("DownloadAgainRow")
        }
    }

    /// What the alert says before the whole library is fetched again: nothing waiting is lost.
    static func downloadMessage(name: String, unsent: Int) -> String {
        guard unsent > 0 else {
            return String(localized: "The app fetches the whole library from \(name) again. It keeps working while it downloads.")
        }
        return String(localized: "The app fetches the whole library from \(name) again. The \(Words.changes(unsent)) not yet sent stay on this Mac and are sent afterwards.")
    }

    // MARK: Reading

    /// The folder's size and the files' state, summed when the page appears, after each step that changes them, when a
    /// fill ends and then at `StoreSize.interval`.
    private func sum(directory: URL) async {
        guard !isWorking else { return }
        storeBytes = await StoreSize.bytes(of: directory)
        await read()
    }

    private func read() async {
        guard let source = library?.downloadedFiles else { return }
        do {
            downloads = try await source.read()
            readFailed = false
        } catch {
            readFailed = true
        }
    }

    private func change(_ action: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await action()
                actionFailure = nil
            } catch let failure as SourceFailure {
                actionFailure = failure.message
            } catch {
                actionFailure = String(localized: "Couldn’t change downloaded files. Check the current limit and try again.")
            }
            await read()
            if let connection = host.configuredConnection { storeBytes = await StoreSize.bytes(of: host.location.directory(for: connection)) }
        }
    }
}
