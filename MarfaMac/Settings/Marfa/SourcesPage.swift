import Marfa
import SwiftUI

/// The Sources page: every source that holds items, with the name and mark the server gives it, and the rules that reach every
/// app and key. A name or mark is kept on the server for every app.
struct SourcesPage: View {
    static let limitSources = SettingsSubpage(id: "limit-sources", title: String(localized: "Limit Sources"))

    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: SourcesModel
    @State private var limit: SourceLimitModel
    @Environment(\.settingsPush) private var push

    init(host: any MarfaSettingsHost, subpage: SettingsSubpage?) {
        self.host = host
        self.subpage = subpage
        let access = SourceAccess(
            rows: { [host] in host.sources }, refresh: { [host] in await host.refreshSources() },
            change: { [host] code, change in await host.changeSource(code, change) },
            marks: { [host] query, set in host.marks(matching: query, in: set) })
        _model = State(initialValue: SourcesModel(access: access, markSets: host.markSets))
        _limit = State(initialValue: SourceLimitModel(context: OwnerContext(host: host), sources: { [host] in host.sources }))
    }

    var body: some View {
        content
            .task(id: host.serverAddress) {
                async let sources: Void = model.load()
                if host.grants.contains(.configManage) { await limit.load() }
                await sources
            }
            .onAppear {
                host.ownerDrafts.register(model)
                host.ownerDrafts.register(limit)
            }
            .settingsSheet(presenting: model.sheet != nil, dismiss: { model.close() }) { SourceSheet(model: model, host: host) }
            .accessibilityIdentifier("SourcesPage")
    }

    @ViewBuilder private var content: some View {
        if subpage?.id == Self.limitSources.id {
            LimitSourcesPage(model: limit, host: host)
        } else {
            list
        }
    }

    private var list: some View {
        SettingsPageColumn {
            if let failure = model.listFailure { OwnerProblem(title: "Not Changed", failure: failure, page: .sources, host: host) }
            SettingsSection("Sources") {
                if model.rows.isEmpty {
                    SettingsEmptyCard(
                        symbol: "tray.and.arrow.down", title: Text(model.hasLoaded ? "No Sources Yet" : "Reading Sources…"),
                        line: model.hasLoaded ? Text("A source appears here once an app or key has written an item.") : nil)
                }
                ForEach(model.rows) { row in sourceRow(row) }
            }
            if host.grants.contains(.configManage) { rules }
        }
    }

    private func sourceRow(_ row: MarfaSourceRow) -> some View {
        SettingsRow(
            title: Text(verbatim: row.name), line: Text(verbatim: Self.naming(row)),
            lead: .well(host.markGlyph(row.mark ?? ""))
        ) {
            HStack(spacing: SettingsTokens.Metric.buttonGap) {
                if let count = row.count { SettingsValue(verbatim: String(localized: "\(count.formatted()) items")) }
                SettingsMoreMenu {
                    Button("Rename…") { model.beginRename(row.code) }
                    Button("Change Mark…") { model.beginMark(row.code) }
                    Button("Use Default Name") { Task { await model.useDefaultName(row.code) } }.disabled(!row.hasChosenName)
                    Button("Remove Mark") { Task { await model.removeMark(row.code) } }.disabled(row.mark == nil)
                }
                .disabled(!host.canChangeSources)
            }
        }
    }

    private var rules: some View {
        SettingsSection("Rules for Every App and Key", line: "A key can set its own instead.") {
            SettingsLinkRow(
                verbatim: String(localized: "Limit Sources"), line: String(localized: "Only items from the sources you name are read."),
                value: limit.isOn ? String(localized: "On") : String(localized: "Not Set")
            ) { push(Self.limitSources) }
        }
    }

    /// How a source got its name, in a line.
    static func naming(_ row: MarfaSourceRow) -> String {
        if row.hasChosenName { return String(localized: "Named by you.") }
        if row.name == row.code { return String(localized: "Not named yet.") }
        return String(localized: "Named by its app or key.")
    }
}

/// The sheet that renames a source or chooses its mark.
private struct SourceSheet: View {
    let model: SourcesModel
    let host: any MarfaSettingsHost

    var body: some View {
        switch model.sheet {
        case .name?: nameSheet
        case .mark?: markSheet
        case nil: EmptyView()
        }
    }

    private var nameSheet: some View {
        @Bindable var model = model
        return SettingsSheet(
            title: Text("Rename Source"), line: Text("The name shows in every app that uses \(host.serverName).")
        ) {
            SettingsSheetField(label: "Name", error: model.failure) {
                SettingsField(title: "Name", text: $model.name, isError: model.failure != nil, width: nil, onSubmit: { Task { await model.rename() } })
            }
        } buttons: {
            SettingsButton("Use Default Name") { Task { await model.useDefaultName() } }.disabled(!model.canUseDefaultName)
            Spacer(minLength: 0)
            SettingsButton("Cancel") { model.close() }.disabled(model.isWorking)
            SettingsButton("Rename") { Task { await model.rename() } }.disabled(!model.canRename)
        }
    }

    private var markSheet: some View {
        @Bindable var model = model
        return SettingsSheet(
            title: Text("Choose a Mark"), line: Text("The mark shows in every app that uses \(host.serverName)."), isWide: true
        ) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFieldGap) {
                if model.markSets.count > 1 {
                    SettingsPopUp(title: "Icon Set", selection: $model.markSet) {
                        ForEach(model.markSets) { Text(verbatim: $0.title).tag($0) }
                    }
                }
                SettingsField(title: "Search Icons", text: $model.search, width: nil)
                SettingsSection(name: nil) {
                    let choices = model.markChoices
                    if choices.isEmpty {
                        SettingsRow("No Marks Match", look: .off)
                    }
                    ForEach(choices, id: \.self) { mark in
                        Button { Task { await model.choose(mark: mark) } } label: {
                            SettingsRow(
                                title: Text(verbatim: host.markTitle(mark)),
                                lead: .custom(AnyView(host.markGlyph(mark).frame(width: SettingsTokens.Metric.tile, height: SettingsTokens.Metric.tile)))
                            ) {
                                if mark == model.openRow?.mark { Image(systemName: "checkmark").accessibilityLabel("Chosen") }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isWorking)
                    }
                }
                if let failure = model.failure {
                    Text(verbatim: failure).settingsFont(.line).foregroundStyle(SettingsTokens.errorRed)
                }
            }
        } buttons: {
            SettingsButton("Remove Mark") { Task { await model.removeMark() } }.disabled(!model.canRemoveMark)
            Spacer(minLength: 0)
            SettingsButton("Cancel") { model.close() }.disabled(model.isWorking)
        }
    }
}

/// The page Limit Sources opens (S65): the types and sources to check, then the button bar, then Turn Off.
private struct LimitSourcesPage: View {
    let model: SourceLimitModel
    let host: any MarfaSettingsHost

    var body: some View {
        @Bindable var model = model
        if let failure = model.failure, model.limit == nil {
            OwnerFailureState(page: .sources, failure: failure, host: host) { Task { await model.load() } }
        } else if model.limit == nil {
            OwnerLoading()
        } else {
            SettingsPageColumn {
                Text("For these types, every app and key reads only items from the checked sources: lists, search, exports and webhooks. The app too.")
                    .settingsFont(.sectionLine).foregroundStyle(SettingsTokens.secondaryText)
                    .padding(.horizontal, SettingsTokens.Metric.inset)
                SettingsSection("Types", line: "Types with no limit read every source.") {
                    ForEach(model.typeChoices) { choice in checkRow(choice, in: $model.types, id: "LimitType") }
                }
                SettingsSection("Sources", line: "A new source is left out until you check it.") {
                    if model.sourceChoices.isEmpty { SettingsRow("No Sources", look: .off) }
                    ForEach(model.sourceChoices) { choice in checkRow(choice, in: $model.checkedSources, id: "LimitSource") }
                }
                if let line = model.line {
                    Text(verbatim: line).settingsFont(.line).foregroundStyle(SettingsTokens.errorRed)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, SettingsTokens.Metric.inset)
                }
                SettingsBar {
                    if model.isSaving { ProgressView().controlSize(.small) }
                    SettingsButton("Revert") { model.revert() }.disabled(!model.hasEdits || model.isSaving)
                    SettingsButton("Save") { Task { await model.save() } }.disabled(!model.canSave).accessibilityIdentifier("LimitSourcesSave")
                }
                if model.isOn {
                    SettingsSection("Turn Off") {
                        SettingsRow("Turn Off Limit Sources", line: "Every source is read again.") {
                            SettingsButton("Turn Off", role: .destructive) { Task { await model.turnOff() } }.disabled(model.isSaving)
                        }
                    }
                }
            }
            .accessibilityIdentifier("LimitSourcesPage")
        }
    }

    private func checkRow(_ choice: SourceLimitModel.Choice, in set: Binding<Set<String>>, id: String) -> some View {
        SettingsRow(
            verbatim: choice.title,
            lead: .custom(AnyView(
                Toggle(
                    choice.title,
                    isOn: Binding { set.wrappedValue.contains(choice.code) } set: { on in
                        if on { set.wrappedValue.insert(choice.code) } else { set.wrappedValue.remove(choice.code) }
                    }
                )
                .labelsHidden()
                .toggleStyle(.checkbox)))
        ) {}
        .accessibilityIdentifier(id + "-" + choice.code)
    }
}
