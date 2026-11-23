import SwiftUI

/// The Folders page: the synced folders, each opening a page of its own with the copies that keep it and what each last
/// reported. It only reads. A folder is made, changed and stopped with the command line.
struct FoldersPage: View {
    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: FoldersModel
    @Environment(\.settingsPush) private var push
    @Environment(\.settingsBack) private var back

    init(host: any MarfaSettingsHost, subpage: SettingsSubpage?) {
        self.host = host
        self.subpage = subpage
        _model = State(initialValue: FoldersModel(context: OwnerContext(host: host)))
    }

    static func subpage(for folder: OwnerFolder) -> SettingsSubpage {
        SettingsSubpage(id: "folder:" + folder.id, title: folder.title)
    }

    private var openID: String? {
        guard let id = subpage?.id, id.hasPrefix("folder:") else { return nil }
        return String(id.dropFirst(7))
    }

    var body: some View {
        content
            .task(id: host.serverAddress) { await model.load() }
            .accessibilityIdentifier("FoldersPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .folders, failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else if let id = openID {
            if let folder = model.folder(id) {
                FolderDetail(model: model, folder: folder, host: host)
            } else {
                SettingsPageState(
                    symbol: "folder", title: Text("This Folder Is Gone"),
                    line: Text("It was stopped, here or somewhere else."), action: ("Back", back))
            }
        } else {
            list
        }
    }

    private var list: some View {
        SettingsPageColumn {
            SettingsSection(
                name: Text("Folders"),
                footer: Text("Folders are made with the command line. Only folders MAPP may read are listed.")
            ) {
                if model.folders.isEmpty {
                    SettingsEmptyCard(
                        symbol: "folder", title: Text("No Folders"),
                        line: Text("Nothing is kept in step with a folder yet."))
                }
                ForEach(model.folders) { folder in
                    let report = model.reports[folder.id]
                    let condition = model.condition(of: folder)
                    SettingsLinkRow(
                        verbatim: folder.title, line: report.map { FoldersModel.copies($0.copies.count) },
                        lead: .tile("folder.fill", .blue), value: condition?.title, dot: condition.map(Self.dot)
                    ) { push(Self.subpage(for: folder)) }
                }
            }
            if let cut = model.cutLine { SettingsNote(verbatim: cut) }
        }
    }

    static func dot(_ condition: FoldersModel.Condition) -> Color {
        switch condition.tone {
        case .ok: SettingsTokens.ok
        case .warning: SettingsTokens.warning
        case .quiet: SettingsTokens.tertiaryText
        }
    }
}

/// One folder's page: what needs attention, then each copy that keeps it.
private struct FolderDetail: View {
    let model: FoldersModel
    let folder: OwnerFolder
    let host: any MarfaSettingsHost

    var body: some View {
        SettingsPageColumn {
            if let report = model.reports[folder.id] {
                SettingsHead(
                    symbol: "folder.fill", tone: .blue, title: Text(verbatim: folder.title),
                    line: Text(verbatim: FoldersModel.copies(report.copies.count)))
                attention(report)
                copies(report)
            } else if let failure = model.reportFailures[folder.id] {
                SettingsHead(symbol: "folder.fill", tone: .blue, title: Text(verbatim: folder.title))
                OwnerProblem(title: "Couldn’t Read This Folder", failure: failure, page: .folders, host: host, retry: { Task { await model.loadReport(folder.id) } })
            } else {
                OwnerLoading()
            }
        }
        .task(id: folder.id) { await model.loadReport(folder.id) }
    }

    @ViewBuilder private func attention(_ report: FolderReport) -> some View {
        let held = report.copies.filter(FoldersModel.needsAttention)
        if !held.isEmpty {
            SettingsSection("Needs Attention") {
                ForEach(held) { copy in
                    if copy.pausedRemovals > 0 {
                        SettingsProblemRow(
                            title: Text(verbatim: FoldersModel.removalsTitle(copy.pausedRemovals, signIn: copy.signIn)),
                            line: Text(verbatim: FoldersModel.removalsLine), actions: [])
                    }
                    ForEach(copy.problems, id: \.code) { problem in
                        SettingsProblemRow(
                            title: Text(verbatim: FoldersModel.title(of: problem)),
                            line: Text(verbatim: FoldersModel.problemLine(signIn: copy.signIn)), actions: [])
                    }
                }
            }
        }
    }

    private func copies(_ report: FolderReport) -> some View {
        SettingsSection(
            name: Text("Copies"), line: Text("Named by the sign-in that keeps each one."),
            footer: Text("Change this folder’s ignore patterns, limits and files with the command line: \(Text.settingsCode("marfa folders")).")
        ) {
            if report.copies.isEmpty {
                SettingsEmptyCard(
                    symbol: "externaldrive", title: Text("No Copies"),
                    line: Text("No sign-in has reported keeping this folder yet."))
            }
            ForEach(report.copies) { copy in
                let condition = FoldersModel.condition(of: copy)
                SettingsRow(verbatim: copy.signIn, line: FoldersModel.reported(ageSeconds: copy.ageSeconds)) {
                    // A copy under Needs Attention is not told again here.
                    if !FoldersModel.needsAttention(copy) { SettingsValue(verbatim: condition.title, dot: FoldersPage.dot(condition)) }
                }
            }
        }
    }
}
