import Marfa
import SwiftUI

/// The Sources page: every source that holds items, with the name and mark the server gives it, and the rules that reach every
/// app and key. A name or mark is kept on the server for every app.
struct SourcesPage: View {
    static let limitSources = SettingsSubpage(id: "limit-sources", title: SourceRule.filter.title)
    static let whoMayWrite = SettingsSubpage(id: "who-may-write", title: SourceRule.allowlist.title)

    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: SourcesModel
    @State private var limit: SourceLimitModel
    @State private var allowlist: SourceLimitModel
    @State private var showsAll = false
    @Environment(\.settingsNavigation) private var navigation

    init(host: any MarfaSettingsHost, subpage: SettingsSubpage?) {
        self.host = host
        self.subpage = subpage
        let access = SourceAccess(
            rows: { [host] in host.sources }, refresh: { [host] in await host.refreshSources() },
            change: { [host] code, change in await host.changeSource(code, change) },
            marks: { [host] query, set in host.marks(matching: query, in: set) })
        _model = State(initialValue: SourcesModel(access: access, markSets: host.markSets))
        _limit = State(initialValue: SourceLimitModel(rule: .filter, context: OwnerContext(host: host)))
        _allowlist = State(initialValue: SourceLimitModel(rule: .allowlist, context: OwnerContext(host: host)))
    }

    var body: some View {
        content
            .onAppear {
                host.ownerDrafts.register(model)
                host.ownerDrafts.register(limit)
                host.ownerDrafts.register(allowlist)
            }
            .settingsSheet(presenting: model.sheet != nil, dismiss: { model.close() }) { SourceSheet(model: model, host: host) }
            .accessibilityIdentifier("SourcesPage")
    }

    @ViewBuilder private var content: some View {
        if subpage?.id == Self.limitSources.id {
            rulePage(limit)
        } else if subpage?.id == Self.whoMayWrite.id {
            rulePage(allowlist)
        } else {
            list
        }
    }

    /// A rule's page, which needs `config.manage` beside the Sources page's own permission: Forward can reach it after the
    /// permission was taken away.
    @ViewBuilder private func rulePage(_ model: SourceLimitModel) -> some View {
        if host.grants.contains(.configManage) {
            SourceRulePage(model: model, host: host)
        } else {
            SettingsPageState(
                symbol: "lock", title: Text("Needs a Permission"), line: Text(verbatim: model.rule.permissionLine),
                action: (host.isAllowingMore ? "Waiting…" : "Allow More", { host.askForMore(naming: InstancePermission.configManage.rawValue) }))
            .disabled(host.isAllowingMore)
        }
    }

    private var list: some View {
        SettingsPageColumn {
            if let failure = model.listFailure { OwnerProblem(title: "Not Changed", failure: failure, page: .sources, host: host) }
            let rows = model.rows
            let preview = SettingsTablePreview(total: rows.count, expanded: showsAll)
            SettingsSection(name: nil) {
                if rows.isEmpty {
                    SettingsEmptyCard(
                        symbol: "tray.and.arrow.down", title: Text(model.hasLoaded ? "No Sources Yet" : "Reading Sources…"),
                        line: model.hasLoaded ? Text("A source appears here once an app or key has written an item.") : nil)
                }
                ForEach(rows.prefix(preview.visibleCount)) { row in sourceRow(row) }
                if let count = preview.countLabel {
                    SettingsRow(verbatim: count) { SettingsShowAllButton { showsAll = true } }
                }
            }
            rules
        }
        .task { await model.load() }
        .task(id: host.grants.contains(.configManage)) {
            if host.grants.contains(.configManage) { await limit.load(choices: false) }
        }
    }

    private func sourceRow(_ row: MarfaSourceRow) -> some View {
        SettingsRow(
            title: Text(verbatim: row.name), line: row.hasChosenName ? Text("Custom name.") : nil,
            lead: .custom(AnyView(host.markGlyph(row.mark ?? "").accessibilityHidden(true)))
        ) {
            HStack(spacing: SettingsTokens.Metric.buttonGap) {
                if let count = row.count {
                    SettingsValue(verbatim: count == 1 ? String(localized: "1 item") : String(localized: "\(count.formatted()) items"))
                }
                SettingsMoreMenu {
                    Button("Rename…") { model.beginRename(row.code) }
                    Button("Change Mark…") { model.beginMark(row.code) }
                    Button("Use Default Name") { Task { await model.useDefaultName(row.code) } }.disabled(!row.hasChosenName)
                    Button("Remove Mark") { Task { await model.removeMark(row.code) } }.disabled(row.mark == nil)
                }
                .disabled(!host.canChangeSources || model.isWorking)
            }
        }
        .help(Text(verbatim: row.name))
    }

    private var rules: some View {
        let allowed = host.grants.contains(.configManage)
        let lock = allowed ? nil : String(localized: "Not allowed")
        return SettingsSection("Rules for Every App and Key", footer: "A key can set its own instead.") {
            if allowed, let failure = limit.failure {
                OwnerProblemRow(title: "Couldn’t Read the Rules", failure: failure, page: .sources, host: host) {
                    Task { await limit.load(choices: false) }
                }
            }
            SettingsLinkRow(
                verbatim: SourceRule.allowlist.title, lead: .tile("square.and.pencil", .blue),
                value: limit.status(of: .allowlist), lock: lock
            ) { navigation?.push(Self.whoMayWrite) }
            SettingsLinkRow(
                verbatim: SourceRule.filter.title, lead: .tile("eye", .indigo),
                value: limit.status(of: .filter), lock: lock
            ) { navigation?.push(Self.limitSources) }
        }
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
        } leading: {
            SettingsButton("Use Default Name") { Task { await model.useDefaultName() } }.disabled(!model.canUseDefaultName)
        } buttons: {
            SettingsButton("Cancel") { model.close() }.disabled(model.isWorking)
            SettingsButton("Rename", role: .confirm) { Task { await model.rename() } }.disabled(!model.canRename)
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
        } leading: {
            SettingsButton("Remove Mark") { Task { await model.removeMark() } }.disabled(!model.canRemoveMark)
        } buttons: {
            SettingsButton("Cancel") { model.close() }.disabled(model.isWorking)
        }
    }
}

private struct SourceRulePage: View {
    let model: SourceLimitModel
    let host: any MarfaSettingsHost
    @State private var asksToTurnOff = false

    var body: some View {
        // The rule and its choices are read however the page was reached, the list's read included.
        state.task { await model.load() }
    }

    @ViewBuilder private var state: some View {
        @Bindable var model = model
        let words = SourceRuleWords(rule: model.rule)
        if let failure = model.failure, model.limit == nil {
            OwnerFailureState(page: .sources, failure: failure, host: host) { Task { await model.load() } }
        } else if model.limit == nil {
            OwnerLoading()
        } else {
            SettingsPageColumn {
                if let failure = model.failure {
                    OwnerProblem(title: words.readFailure, failure: failure, page: .sources, host: host) {
                        Task { await model.load() }
                    }
                }
                Text(verbatim: words.intro)
                    .settingsFont(.sectionLine).foregroundStyle(SettingsTokens.secondaryText)
                    .padding(.horizontal, SettingsTokens.Metric.inset)
                SettingsSection(name: Text("Types"), line: Text(verbatim: words.typesLine)) {
                    if let failure = model.typesFailure {
                        OwnerProblemRow(title: "Couldn’t Read Available Types", failure: failure, page: .sources, host: host) {
                            Task { await model.load() }
                        }
                    }
                    ForEach(model.typeChoices) { choice in checkRow(choice, in: $model.types, id: words.id + "Type") }
                }
                SettingsSection(name: Text("Sources"), line: Text(verbatim: words.sourcesLine)) {
                    if let failure = model.sourcesFailure {
                        OwnerProblemRow(title: "Couldn’t Read Every Source", failure: failure, page: .sources, host: host) {
                            Task { await model.load() }
                        }
                    }
                    if let failure = model.appsFailure {
                        OwnerProblemRow(
                            title: "Can’t Check Apps That Write", failure: failure,
                            line: String(localized: "The app isn’t allowed to read your apps, so only keys are checked before you save."),
                            page: .sources, host: host
                        ) { Task { await model.load() } }
                    }
                    if model.sourceChoices.isEmpty { SettingsRow("No Sources", look: .off) }
                    ForEach(model.sourceChoices) { choice in checkRow(choice, in: $model.checkedSources, id: words.id + "Source") }
                }
                if let waiting = model.waitsFor, model.hasEdits {
                    Text(verbatim: waiting).settingsFont(.line).foregroundStyle(SettingsTokens.secondaryText)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, SettingsTokens.Metric.inset)
                }
                if let line = model.line {
                    Text(verbatim: line).settingsFont(.line).foregroundStyle(SettingsTokens.errorRed)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, SettingsTokens.Metric.inset)
                }
                if model.hasEdits || model.isSaving {
                    SettingsBar {
                        if model.isSaving { ProgressView().controlSize(.small) }
                        SettingsButton("Revert") { model.revert() }.disabled(!model.hasEdits || model.isSaving)
                        SettingsButton("Save") {
                            if model.saveTurnsOff { asksToTurnOff = true } else { Task { await model.save() } }
                        }
                        .disabled(!model.canSave).accessibilityIdentifier(words.id + "Save")
                    }
                }
                if model.isOn {
                    SettingsSection("Turn Off") {
                        SettingsRow(verbatim: words.turnOff, line: words.turnOffLine) {
                            SettingsButton("Turn Off…", role: .destructive) { asksToTurnOff = true }.disabled(model.isSaving)
                        }
                    }
                }
            }
            .alert(Text(verbatim: words.turnOffQuestion), isPresented: $asksToTurnOff) {
                Button("Cancel", role: .cancel) {}
                Button("Turn Off", role: .destructive) { Task { await model.turnOff() } }
            } message: {
                Text(verbatim: words.turnOffMessage)
            }
            .accessibilityIdentifier(words.id + "Page")
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

/// What a source rule's page says.
private struct SourceRuleWords {
    let rule: SourceRule

    var id: String { rule == .filter ? "LimitSources" : "WhoMayWrite" }

    var intro: String {
        switch rule {
        case .filter:
            String(localized: "Lists, search, exports, and webhooks include only items from the checked sources for these types and their subtypes. Individual items can still be opened directly. A key can use its own rule.")
        case .allowlist:
            String(localized: "Only the checked sources can add items of the checked types. Subtypes have their own rules. A key can use its own rule.")
        }
    }

    var typesLine: String {
        switch rule {
        case .filter: String(localized: "Checking a type also limits its subtypes.")
        case .allowlist: String(localized: "Types left unchecked take items from every source.")
        }
    }

    var sourcesLine: String {
        switch rule {
        case .filter: String(localized: "A new source is left out until you check it.")
        case .allowlist: String(localized: "A new source can’t add these types until you check it.")
        }
    }

    var readFailure: LocalizedStringKey { "Couldn’t Read \(rule.title)" }
    var turnOff: String { String(localized: "Turn Off \(rule.title)") }
    var turnOffQuestion: String { String(localized: "Turn Off \(rule.title)?") }

    var turnOffLine: String {
        switch rule {
        case .filter: String(localized: "Remove the instance’s source filter.")
        case .allowlist: String(localized: "Remove the instance’s rule for adding items.")
        }
    }

    var turnOffMessage: String {
        switch rule {
        case .filter: String(localized: "Apps and keys using this rule will see items from every source for the types you limited, including subtypes.")
        case .allowlist: String(localized: "Apps and keys using this rule will be able to add items of these types from any source.")
        }
    }
}
