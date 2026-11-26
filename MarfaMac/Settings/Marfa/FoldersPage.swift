import SwiftUI

/// The Folders page: the synced folders, each opening a page of its own with its settings, the copies that keep it and what
/// each last reported. A folder is changed and stopped here, and made where it is kept in step, such as with the command line.
struct FoldersPage: View {
    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: FoldersModel
    @Environment(\.settingsNavigation) private var navigation

    init(host: any MarfaSettingsHost, subpage: SettingsSubpage?) {
        self.host = host
        self.subpage = subpage
        _model = State(initialValue: FoldersModel(context: OwnerContext(host: host), folderCalls: host.folderCalls))
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
            .onAppear { host.ownerDrafts.register(model) }
            .settingsSheet(presenting: model.isRenaming, dismiss: { model.cancelRename() }) { RenameFolderSheet(model: model) }
            .alert(
                model.question?.title ?? "", isPresented: Binding { model.question != nil } set: { if !$0 { model.cancelQuestion() } },
                presenting: model.question
            ) { asked in
                Button("Cancel", role: .cancel) {}
                Button(asked.button, role: .destructive) { Task { await model.confirm(asked) } }
            } message: { asked in
                Text(verbatim: asked.message)
            }
            .onChange(of: model.stopped) { if $1 != nil { navigation?.back() } }
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
                    line: Text("It was stopped, here or somewhere else."), action: ("Back", { navigation?.back() }))
            }
        } else {
            list
        }
    }

    private var list: some View {
        SettingsPageColumn {
            SettingsSection(
                name: Text("Folders"),
                footer: Text("A folder is made where it is kept in step, such as with the command line.")
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
                        verbatim: folder.title, line: line(folder, report: report),
                        lead: .tile("folder.fill", .blue), value: condition?.title, dot: condition.map(Self.dot)
                    ) { navigation?.push(Self.subpage(for: folder)) }
                }
            }
            if let cut = model.cutLine { SettingsNote(verbatim: cut) }
        }
    }

    /// What the folder holds, then how many copies keep it, as far as each is read.
    private func line(_ folder: OwnerFolder, report: FolderReport?) -> String? {
        let holds = model.settings[folder.id].map { FoldersModel.holds($0, plural: { host.plural($0) }) }
        let copies = report.map { FoldersModel.copies($0.copies.count) }
        let parts = [holds, copies].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static func dot(_ condition: FoldersModel.Condition) -> Color {
        switch condition.tone {
        case .ok: SettingsTokens.ok
        case .warning: SettingsTokens.warning
        case .quiet: SettingsTokens.tertiaryText
        }
    }
}

extension MarfaSettingsHost {
    /// A type's plural as the copy reads it, or its id where it has none.
    func plural(_ type: String) -> String { typePlural(of: type) ?? type }
}

/// One folder's page: what needs attention, what it holds, the patterns and limits it follows, the copies that keep it and
/// Stop Syncing.
private struct FolderDetail: View {
    @Bindable var model: FoldersModel
    let folder: OwnerFolder
    let host: any MarfaSettingsHost
    @Environment(\.settingsTextScale) private var scale

    var body: some View {
        SettingsPageColumn {
            if let report = model.reports[folder.id] {
                SettingsHead(
                    symbol: "folder.fill", tone: .blue, title: Text(verbatim: folder.title),
                    line: Text(verbatim: FoldersModel.copies(report.copies.count))
                ) {
                    if model.settings[folder.id] != nil { SettingsButton("Rename…") { model.beginRename() } }
                }
                attention(report)
                settings
                copies(report)
                if model.settings[folder.id] != nil { stopSyncing }
            } else if let failure = model.reportFailures[folder.id] {
                SettingsHead(symbol: "folder.fill", tone: .blue, title: Text(verbatim: folder.title))
                OwnerProblem(title: "Couldn’t Read This Folder", failure: failure, page: .folders, host: host, retry: { Task { await model.loadFolder(folder.id) } })
            } else {
                OwnerLoading()
            }
        }
        .task(id: folder.id) {
            model.open(folder.id)
            await model.loadFolder(folder.id)
        }
    }

    @ViewBuilder private func attention(_ report: FolderReport) -> some View {
        let held = report.copies.filter(FoldersModel.needsAttention)
        if !held.isEmpty {
            SettingsSection("Needs Attention") {
                ForEach(held) { copy in
                    if copy.pausedRemovals > 0 {
                        SettingsProblemRow(
                            title: Text(verbatim: FoldersModel.removalsTitle(copy.pausedRemovals, signIn: copy.signIn)),
                            line: Text(verbatim: FoldersModel.removalsLine(limit: model.settings[folder.id]?.removalLimit)), actions: [])
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

    @ViewBuilder private var settings: some View {
        if let read = model.settings[folder.id] {
            SettingsSection(
                name: Text("Folder"),
                footer: Text("Change what it holds with the command line: \(Text.settingsCode("marfa folders update")).")
            ) {
                SettingsRow("Holds") { SettingsValue(verbatim: FoldersModel.types(read, plural: { host.plural($0) })) }
                SettingsRow("From") { SettingsValue(verbatim: FoldersModel.tier(read)) }
                SettingsRow("New Files Become") {
                    if let type = read.newFileType {
                        SettingsValue(verbatim: host.plural(type))
                    } else {
                        SettingsValue("Chosen by Each File")
                    }
                }
            }
            patterns(
                .ignore, name: "Ignore", line: "Files and folders Marfa leaves alone.", read: read, held: read.ignore,
                draft: $model.ignoreDraft)
            patterns(
                .include, name: "Include", line: "Choose which paths can sync. Ignore rules still apply. Hidden paths need an explicit pattern.",
                read: read, held: read.include, draft: $model.includeDraft)
            SettingsSection("Safety", line: "Pauses also depend on the share of the folder. Removals have a separate ceiling.") {
                limit(.removalLimit, title: "Pause Removals Over", text: $model.removalDraft)
                limit(.additionLimit, title: "Pause Additions Over", text: $model.additionDraft)
            }
        } else if let failure = model.settingsFailures[folder.id] {
            SettingsSection("Folder") {
                OwnerProblemRow(
                    title: "Couldn’t Read This Folder’s Settings", failure: failure, page: .folders, host: host,
                    retry: { Task { await model.loadFolder(folder.id) } })
            }
        }
    }

    private func patterns(
        _ setting: FoldersModel.Setting, name: LocalizedStringKey, line: LocalizedStringKey, read: FolderSettingsReading, held: [String],
        draft: Binding<String?>
    ) -> some View {
        SettingsSection(name, line: line) {
            ForEach(Array(held.enumerated()), id: \.offset) { index, pattern in
                SettingsRow(title: Text(verbatim: pattern).font(SettingsTokens.font(.mono, scale: scale))) {
                    SettingsButton("Remove") { Task { await model.removePattern(at: index, from: setting, in: read) } }
                        .disabled(model.sending.contains(setting))
                }
            }
            if draft.wrappedValue != nil {
                SettingsRow("Name or Pattern", error: model.errors[setting]) {
                    SettingsField(
                        title: "Name or Pattern",
                        text: Binding { draft.wrappedValue ?? "" } set: { if draft.wrappedValue != nil { draft.wrappedValue = $0 } },
                        prompt: "*.tmp",
                        isError: model.errors[setting] != nil, isMonospaced: true,
                        onSubmit: { Task { await model.addPattern(to: setting) } },
                        onEndEditing: { Task { await model.addPattern(to: setting, explicitly: false) } })
                    .onExitCommand { model.endAdding(setting) }
                }
            } else {
                if let error = model.errors[setting] { SettingsRow("Not Changed", error: error) }
                SettingsAddRow("Add a Name or Pattern") { model.beginAdding(to: setting) }
            }
        }
    }

    private func limit(_ setting: FoldersModel.Setting, title: LocalizedStringKey, text: Binding<String>) -> some View {
        SettingsRow(title, error: model.errors[setting]) {
            SettingsNumberField(
                title: title, text: text, unit: "files", isError: model.errors[setting] != nil,
                onSubmit: { Task { await model.commitLimit(setting) } },
                onEndEditing: { Task { await model.commitLimit(setting, explicitly: false) } })
        }
    }

    private func copies(_ report: FolderReport) -> some View {
        SettingsSection(name: Text("Copies"), line: Text("Named by the sign-in that keeps each one.")) {
            if report.copies.isEmpty {
                SettingsEmptyCard(
                    symbol: "externaldrive", title: Text("No Copies"),
                    line: Text("No sign-in has reported keeping this folder yet."))
            }
            ForEach(report.copies) { copy in
                let condition = FoldersModel.condition(of: copy)
                SettingsRow(verbatim: copy.signIn, line: FoldersModel.reported(ageSeconds: copy.ageSeconds)) {
                    SettingsValue(verbatim: condition.title, dot: FoldersPage.dot(condition))
                }
            }
        }
    }

    private var stopSyncing: some View {
        SettingsSection("Stop Syncing") {
            SettingsRow(
                verbatim: String(localized: "Stop Syncing \(folder.title)"),
                line: String(localized: "Every copy stops. The files stay where each copy keeps them."), error: model.errors[.stopSyncing]
            ) {
                SettingsButton("Stop Syncing…", role: .destructive) { model.askToStop() }
                    .disabled(model.sending.contains(.stopSyncing))
            }
        }
    }
}

private struct RenameFolderSheet: View {
    @Bindable var model: FoldersModel

    var body: some View {
        SettingsSheet(title: Text("Rename Folder")) {
            SettingsSheetField(label: "Name", error: model.errors[.title]) {
                SettingsField(
                    title: "Name", text: $model.renameDraft, isError: model.errors[.title] != nil, width: nil,
                    onSubmit: { Task { await model.rename() } })
            }
        } buttons: {
            SettingsButton("Cancel") { model.cancelRename() }
            SettingsButton("Rename", role: .confirm) { Task { await model.rename() } }.disabled(!model.canRename)
        }
    }
}
