import AppKit
import SwiftUI

/// The open Marfa’s offline files and the controls for exporting or rebuilding its local copy.
struct ConnectionCopySections: View {
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
        if let library, let source = library.downloadedFiles, let connection = host.configuredConnection {
            sections(library: library, source: source, connection: connection)
        }
    }

    private func sections(library: any ItemLibrary, source: any DownloadedFiles, connection: MarfaConnection) -> some View {
        Group {
            files(source)
                .task(id: ObjectIdentifier(library)) {
                    await StoreSize.keepReading { if !isWorking { await read() } }
                }
                .onChange(of: isFilling) { _, filling in
                    guard !filling, !isWorking else { return }
                    Task { await read() }
                }
            SettingsSection("This Mac’s Copy", footer: "An export is an archive that any Marfa can restore.") {
                SettingsRow("Space used") {
                    SettingsValue(verbatim: storeBytes.map(StoreSize.text) ?? String(localized: "Unavailable"))
                }
                exportRow(connection: connection)
                automaticRows
                downloadRow(library: library)
            }
            .alert("Download Everything Again?", isPresented: $isConfirmingDownload) {
                Button("Cancel", role: .cancel) {}
                Button("Download Again") { library.downloadEverythingAgain() }
            } message: {
                Text(Self.downloadMessage(name: name, unsent: host.waitingChanges ?? 0))
            }
        }
    }

    // MARK: Files

    private func files(_ source: any DownloadedFiles) -> some View {
        SettingsSection(
            "Downloaded Files",
            footer: "Attachments are always kept, so they open offline. Opened files are fetched again when you open them, and the least used go first when there’s no room."
        ) {
            if let state = downloads {
                SettingsRow("Keep opened files") {
                    SettingsPopUp(
                        title: "Keep opened files",
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
                    .help(Text(verbatim: budgetLine(state)))
                    .disabled(isWorking)
                    .accessibilityIdentifier("KeepOpenedFiles")
                }
                attachments(state)
                SettingsRow("Opened files") {
                    HStack(spacing: SettingsTokens.Metric.buttonGap) {
                        SettingsValue(verbatim: state.bytes.map(StoreSize.text) ?? String(localized: "Unavailable"))
                        SettingsButton("Clear") { change { try await source.removeDownloadedFiles() } }
                            .disabled(isWorking)
                            .accessibilityIdentifier("RemoveDownloadedFiles")
                    }
                }
            } else if !readFailed {
                SettingsRow("Reading downloaded files…") { ProgressView().controlSize(.small) }
            }
            if readFailed {
                SettingsProblemRow(title: Text("Couldn’t read downloaded files"), line: Text("The app will try again."), actions: [])
            }
            if let actionFailure {
                SettingsRow(verbatim: actionFailure, size: .compact, lines: nil) {}
            }
        }
        .accessibilityIdentifier("LibraryDownloads")
    }

    @ViewBuilder private func attachments(_ state: DownloadedFileState) -> some View {
        if let attachments = state.attachments {
            SettingsRow("Attachments") {
                SettingsValue(verbatim: StoreSize.text(attachments.heldBytes))
            }
            if attachments.missing > 0 {
                SettingsRow(
                    title: Text("Attachments not yet offline"), line: DownloadWording.line(attachments.reasons).map { Text(verbatim: $0) },
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

    private func exportRow(connection: MarfaConnection) -> some View {
        let line = !canAskServer
            ? String(localized: "This Marfa must be reachable.")
            : exported
        return SettingsRow(
            title: Text("Export everything"), line: line.map { Text(verbatim: $0) }, error: exportFailure,
            look: canAskServer ? .normal : .off, lines: nil
        ) {
            HStack(spacing: SettingsTokens.Metric.buttonGap) {
                if isExporting { ProgressView().controlSize(.small) }
                SettingsButton("Export…") { exportEverything(connection: connection) }
                    .disabled(isExporting || isChoosingExportFolder)
                    .accessibilityIdentifier("ExportEverything")
            }
        }
        .accessibilityIdentifier("ExportRow")
    }

    // MARK: Export Automatically

    @ViewBuilder private var automaticRows: some View {
        let automatic = libraries.automaticExport
        let instance = automatic.openInstance
        let plan = automatic.current
        let schedule = plan?.schedule ?? .never
        SettingsRow(title: Text("Export automatically"), line: automaticLine(plan).map { Text(verbatim: $0) }, error: automaticFailure, lines: nil) {
            SettingsPopUp(
                title: "Export automatically",
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
            SettingsRow(title: Text("Export folder"), line: Text(verbatim: (folder.path as NSString).abbreviatingWithTildeInPath), lineGlyph: .folder) {
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

    private func automaticLine(_ plan: ExportPlan?) -> String? {
        guard let plan, plan.schedule != .never, let last = plan.last else { return nil }
        return String(localized: "Last saved \(last.formatted(.dateTime.day().month().year())).")
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

    private func downloadRow(library: any ItemLibrary) -> some View {
        let line = DownloadAgainRow.line(fill: library.syncReport.fill, in: host.state)
        return SettingsRow(
            title: Text("Download everything again"),
            line: Text(verbatim: line).monospacedDigit(),
            look: canAskServer ? .normal : .off
        ) {
            SettingsButton("Download Again") { isConfirmingDownload = true }
                .disabled(isFilling)
                .accessibilityIdentifier("DownloadAgain")
        }
        .accessibilityIdentifier("DownloadAgainRow")
    }

    /// What the alert says before the whole library is fetched again: nothing waiting is lost.
    static func downloadMessage(name: String, unsent: Int) -> String {
        guard unsent > 0 else {
            return String(localized: "The app fetches the whole library from \(name) again. It keeps working while it downloads.")
        }
        return String(localized: "The app fetches the whole library from \(name) again. The \(Words.changes(unsent)) not yet sent stay on this Mac and are sent afterwards.")
    }

    // MARK: Reading

    private func read() async {
        guard let source = library?.downloadedFiles, let connection = host.configuredConnection else { return }
        let bytes = await StoreSize.bytes(of: host.location.directory(for: connection))
        guard !Task.isCancelled, connection == host.configuredConnection else { return }
        storeBytes = bytes
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
        }
    }
}
