import AppKit
import SwiftUI

/// The On This Mac page: the copy of the library the app keeps on this Mac, and what can be done to it. The space it uses, the
/// files opened and attachments kept offline, Export Everything to a folder, and Download Everything Again. What each file
/// step does is `DownloadedFiles`', unchanged; a hydration keeps every change not yet sent (`MarfaSync.rehydrate`).
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
    @State private var isConfirmingDownload = false
    @AppStorage(AutomaticExport.scheduleKey) private var schedule = ExportSchedule.never
    @AppStorage(AutomaticExport.folderKey) private var folderPath = ""

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
                    SettingsButton("Export…") { chooseFolder(for: connection) }
                        .disabled(isExporting)
                        .accessibilityIdentifier("ExportEverything")
                }
            }
            .accessibilityIdentifier("ExportRow")
            automaticRows
        }
    }

    // MARK: Export Automatically

    @ViewBuilder private var automaticRows: some View {
        let folder = folderPath.isEmpty ? nil : URL(filePath: folderPath, directoryHint: .isDirectory)
        SettingsRow(title: Text("Export Automatically"), line: Text(verbatim: automaticLine(folder: folder))) {
            SettingsPopUp(title: "Export Automatically", selection: Binding(get: { schedule }, set: { choose($0) })) {
                Text("Never").tag(ExportSchedule.never)
                Text("Every Day").tag(ExportSchedule.daily)
                Text("Every Week").tag(ExportSchedule.weekly)
            }
            .accessibilityIdentifier("ExportAutomatically")
        }
        .accessibilityIdentifier("ExportAutomaticallyRow")
        if schedule != .never, let folder {
            SettingsRow(title: Text("Export Folder"), line: Text(verbatim: (folder.path as NSString).abbreviatingWithTildeInPath)) {
                SettingsButton("Choose…") { chooseAutomaticFolder { chosen in if chosen { libraries.automaticExport.checkSoon() } } }
                    .accessibilityIdentifier("ExportFolder")
            }
        }
    }

    private func automaticLine(folder: URL?) -> String {
        guard schedule != .never, let folder else { return String(localized: "To a folder you choose.") }
        let to = String(localized: "To “\(folder.lastPathComponent)”.")
        guard let last = libraries.automaticExport.saved[host.configuredConnection?.address.absoluteString ?? ""] else { return to }
        return to + " " + String(localized: "Last saved \(last.formatted(.dateTime.day().month().year())).")
    }

    /// A schedule is turned on only with a folder, asked for the first time; a cancelled chooser leaves it as it was.
    private func choose(_ new: ExportSchedule) {
        guard new != .never, folderPath.isEmpty else {
            schedule = new
            libraries.automaticExport.checkSoon()
            return
        }
        chooseAutomaticFolder { chosen in
            guard chosen else { return }
            schedule = new
            libraries.automaticExport.checkSoon()
        }
    }

    private func chooseAutomaticFolder(then done: @escaping (Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose where the app saves the archive.")
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return done(false) }
            folderPath = folder.path
            done(true)
        }
    }

    private func chooseFolder(for connection: MarfaConnection) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Export")
        panel.message = String(localized: "Choose where to save the archive.")
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            run(exportTo: folder, connection: connection)
        }
    }

    private func run(exportTo folder: URL, connection: MarfaConnection) {
        guard !isExporting else { return }
        isExporting = true
        exportFailure = nil
        exported = nil
        let source = MarfaArchiveSource(calls: MarfaServerCalls(connection: connection, signIns: host.signIns))
        let server = name
        Task {
            defer { isExporting = false }
            do {
                let file = try await LibraryExport.export(from: source, serverName: server, to: folder)
                exported = String(localized: "Saved as “\(file.lastPathComponent)”.")
            } catch let failure as LibraryExport.Failure {
                exportFailure = failure.message
            } catch {
                exportFailure = String(localized: "Couldn’t export.")
            }
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
