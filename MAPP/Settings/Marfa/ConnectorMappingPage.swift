import Marfa
import SwiftUI

/// How one kind of a connector lands: whether it comes in, which type it is written as, at which tier, where each field of that
/// type gets its value, how status words map and what happens to the items already brought. A change is saved as it is made.
struct ConnectorMappingPage: View {
    let model: ConnectorMappingModel
    let kind: ConnectorKind
    /// Whether the connector is running where a preview can be answered, and if not, why in words.
    let previewBlock: String?
    let host: any MarfaSettingsHost
    @Environment(\.settingsBack) private var back

    private var name: String { kind.name }
    private var summary: PluginConnectorSummary { model.plugin }
    private var entry: ConnectorMappingModel.Kind? { model.kinds[name] }

    var body: some View {
        Group {
            if let failure = model.failure {
                OwnerFailureState(page: .connectors, failure: failure, host: host) { Task { await model.load() } }
            } else if !model.hasLoaded {
                OwnerLoading()
            } else if let entry {
                content(entry)
            } else {
                SettingsPageState(
                    symbol: "arrow.triangle.2.circlepath", title: Text("This Kind Is Gone"),
                    line: Text("The connector no longer brings it."), action: ("Back", back))
            }
        }
        .task { await model.load() }
        .onAppear { host.ownerDrafts.register(model) }
        .task(id: model.hasLoaded ? model.previewRuns[name] ?? 0 : -1) {
            guard previewBlock == nil, model.hasLoaded, model.kinds[name] != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            await model.preview(name)
        }
        .alert(
            String(localized: "Apply to \(plural)?"), isPresented: Binding { model.question == name } set: { if !$0 { model.cancelQuestion() } }
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Apply") { Task { await model.apply(name) } }
        } message: {
            Text("\(summary.title) moves ^[\(model.counts[name] ?? 0) existing item](inflect: true) to \(model.typeName(entry?.draft.targetType ?? "")) and fills them as this mapping says, at its next run.")
        }
        .accessibilityIdentifier("ConnectorMappingPage")
    }

    private var title: String { ConnectorWording.kindTitle(name) }

    /// The kind's items by name: its own type's plural where the server gives one.
    private var plural: String { model.ownType(of: name)?.plural ?? title }

    private func content(_ entry: ConnectorMappingModel.Kind) -> some View {
        SettingsPageColumn {
            SettingsHead(
                lead: SettingsWell(size: SettingsTokens.Metric.headTile) { host.markGlyph(summary.mark) },
                title: Text("\(title) From \(summary.title)"), line: Text("How each one lands in \(host.serverName)."))
            if model.isStale { stale }
            if let failure = model.saveFailure {
                OwnerProblem(title: "Not Saved", failure: failure, page: .connectors, host: host)
            }
            if entry.draft.enabled { previewSection }
            brings(entry)
            if entry.draft.enabled {
                fields(entry)
                statusWords
                existing(entry)
            }
        }
    }

    private var stale: some View {
        SettingsSection(name: nil) {
            SettingsProblemRow(
                title: Text("Changed Somewhere Else"), line: Text("Your changes are kept here and not saved. Reload carries them onto what is there now."),
                actions: [SettingsProblemAction("Reload", isPrimary: true) { Task { await model.reload() } }])
        }
    }

    // MARK: Preview

    @ViewBuilder private var previewSection: some View {
        let target = model.typeName(entry?.draft.targetType ?? "")
        SettingsSection(name: Text("Preview"), line: Text("A recent \(title.lowercased()) as it would land as \(target).")) {
            if let block = previewBlock {
                SettingsRow(verbatim: String(localized: "No Preview Yet"), line: block)
            } else {
                switch model.previewState(name) {
                case .none, .asking:
                    SettingsRow(verbatim: String(localized: "Asking \(summary.title)…"), line: nil) { ProgressView().controlSize(.small) }
                case .waiting:
                    SettingsRow(
                        verbatim: String(localized: "Waiting for \(summary.title)"),
                        line: String(localized: "It answers at its next run.")
                    ) { ProgressView().controlSize(.small) }
                case .ready(let item): previewRows(item)
                case .failed(let reason):
                    SettingsRow(
                        verbatim: String(localized: "\(summary.title) Couldn’t Show One"),
                        line: reason ?? String(localized: "It gave no reason."), error: nil
                    ) {
                        SettingsButton("Try Again") { Task { await model.preview(name) } }
                    }
                case .expired:
                    SettingsRow(
                        verbatim: String(localized: "No Answer"),
                        line: String(localized: "The preview expired before \(summary.title) answered.")
                    ) {
                        SettingsButton("Try Again") { Task { await model.preview(name) } }
                    }
                case .unavailable(let line):
                    SettingsRow(verbatim: String(localized: "No Preview Yet"), line: line) {
                        SettingsButton("Try Again") { Task { await model.preview(name) } }
                    }
                }
            }
        }
    }

    @ViewBuilder private func previewRows(_ item: MappingPreviewItem) -> some View {
        let target = model.type(item.type)
        let shown = (target?.fields ?? []).compactMap { field in item.properties[field.name].map { (field, $0) } }
            .sorted { MappingWording.fieldTitle($0.0).localizedStandardCompare(MappingWording.fieldTitle($1.0)) == .orderedAscending }
        SettingsRow(verbatim: item.title ?? String(localized: "Untitled"), line: String(localized: "As \(model.typeName(item.type))."))
        ForEach(shown, id: \.0.name) { field, value in
            SettingsRow(verbatim: MappingWording.fieldTitle(field), size: .compact) { SettingsValue(verbatim: value) }
        }
    }

    // MARK: What it brings

    @ViewBuilder private func brings(_ entry: ConnectorMappingModel.Kind) -> some View {
        SettingsSection(
            name: Text("What It Brings"),
            footer: Text("A change applies to new items. Existing ones change only when you ask.")
        ) {
            SettingsRow(verbatim: String(localized: "Bring In \(plural)")) {
                SettingsToggle(verbatim: String(localized: "Bring In \(plural)"), isOn: Binding { entry.draft.enabled } set: { on in
                    Task { await model.setEnabled(on, for: name) }
                })
            }
            if entry.draft.enabled {
                SettingsRow("As", error: model.targetError(name), lines: nil) {
                    SettingsPopUp(
                        title: "As", selection: Binding { entry.draft.targetType } set: { id in Task { await model.setTarget(id, for: name) } },
                        isError: model.targetError(name) != nil
                    ) {
                        ForEach(model.targetChoices(for: name)) { Text(verbatim: model.typeName($0.id)).tag($0.id) }
                    }
                }
                SettingsRow("To", line: entry.draft.tier == .feed ? "You can move them on from the feed." : nil) {
                    SettingsPopUp(title: "To", selection: Binding { entry.draft.tier } set: { tier in Task { await model.setTier(tier, for: name) } }) {
                        ForEach(KeyTier.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                    }
                }
            }
            ForEach(Array(model.looseFaults(name).enumerated()), id: \.offset) { _, fault in
                SettingsRow(verbatim: MappingWording.faultTitle(fault.path), error: fault.message, lines: nil)
            }
        }
        if model.isRefused(name) {
            Text(verbatim: MappingWording.kept(host.serverName))
                .settingsFont(.footer).foregroundStyle(SettingsTokens.errorRed)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, SettingsTokens.Metric.inset)
        }
    }

    // MARK: Fields

    @ViewBuilder private func fields(_ entry: ConnectorMappingModel.Kind) -> some View {
        let all = model.targetFields(of: name)
        if !all.isEmpty {
            SettingsSection(
                name: Text("Fields"), line: Text("A field filled by a template can’t be written back to \(summary.title).")
            ) {
                ForEach(all) { field in fieldRows(field) }
            }
        }
    }

    @ViewBuilder private func fieldRows(_ field: MappingTypeField) -> some View {
        let title = MappingWording.fieldTitle(field)
        let choice = model.choice(of: field.name, in: name)
        let error = model.error(for: field, in: name)
        SettingsRow(
            verbatim: title, line: choice == .template ? String(localized: "Filled by a template. Not written back.") : nil, error: error, lines: nil
        ) {
            SettingsPopUp(
                verbatim: title, selection: Binding { choice } set: { picked in Task { await model.setChoice(picked, for: field, in: name) } },
                isError: error != nil
            ) {
                if field.required, choice == .none {
                    Text("Choose…").tag(MappingChoice.none)
                } else {
                    Text("Not Filled").tag(MappingChoice.none)
                }
                ForEach(model.sources(for: field, in: name)) { source in
                    Text(verbatim: MappingWording.fieldTitle(source)).tag(MappingChoice.field(source.name))
                }
                Divider()
                Text("Fixed Value").tag(MappingChoice.fixed)
                if field.kind == .string { Text("Template").tag(MappingChoice.template) }
            }
        }
        switch choice {
        case .template:
            SettingsRow(verbatim: String(localized: "\(title) Template"), line: String(localized: "Jinja text, filled from the item as it comes in.")) {
                SettingsField(
                    verbatim: title, text: textBinding(field), isMonospaced: true, width: nil,
                    onSubmit: { Task { await model.commit(name) } }, onEndEditing: { Task { await model.commit(name) } })
            }
        case .fixed:
            SettingsRow(verbatim: String(localized: "\(title) Value")) { fixedEditor(field) }
        default: EmptyView()
        }
    }

    private func textBinding(_ field: MappingTypeField) -> Binding<String> {
        Binding { model.text(of: field.name, in: name) } set: { model.type($0, into: field, in: name) }
    }

    @ViewBuilder private func fixedEditor(_ field: MappingTypeField) -> some View {
        switch field.kind {
        case .boolean:
            SettingsToggle(verbatim: field.name, isOn: Binding { model.flag(of: field.name, in: name) } set: { on in
                Task { await model.setFixed(.flag(on), for: field, in: name) }
            })
        case .choice, .status:
            let words = field.kind == .status ? field.statusWords.map(\.value) : field.choices
            SettingsPopUp(
                verbatim: field.name, selection: Binding { model.text(of: field.name, in: name) } set: { word in
                    Task { await model.setFixed(.text(word), for: field, in: name) }
                }
            ) {
                if model.text(of: field.name, in: name).isEmpty { Text("Choose…").tag("") }
                ForEach(words, id: \.self) { Text(verbatim: MappingWording.word($0)).tag($0) }
            }
        default:
            SettingsField(
                verbatim: field.name, text: textBinding(field),
                onSubmit: { Task { await model.commit(name) } }, onEndEditing: { Task { await model.commit(name) } })
        }
    }

    // MARK: Status words

    @ViewBuilder private var statusWords: some View {
        if let pair = model.statusPair(of: name) {
            SettingsSection(
                name: Text("Status Words"),
                line: Text("A word goes to the word in its group, unless you choose another.")
            ) {
                ForEach(pair.own.statusWords, id: \.value) { word in
                    let error = model.overrideError(of: word.value, in: name)
                    SettingsRow(
                        verbatim: MappingWording.word(word.value), line: String(localized: "In \(MappingWording.group(word.group))."), error: error,
                        lines: nil
                    ) {
                        SettingsPopUp(
                            verbatim: word.value, selection: Binding<String?> { model.override(of: word.value, in: name) } set: { target in
                                Task { await model.setOverride(target, for: word.value, in: name) }
                            },
                            isError: error != nil
                        ) {
                            Text("By Group").tag(String?.none)
                            Divider()
                            ForEach(pair.target.statusWords, id: \.value) { Text(verbatim: MappingWording.word($0.value)).tag(String?.some($0.value)) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Existing items

    /// A missing permission uses the page's own line, so Allow More… fits it. Anything else says the request was made.
    private func readBackLine(_ failure: OwnerFailure) -> String? {
        if case .notPermitted = failure { return nil }
        return String(localized: "The request was made. MAPP couldn’t read it back to show it here.")
    }

    @ViewBuilder private func existing(_ entry: ConnectorMappingModel.Kind) -> some View {
        SettingsSection(name: Text("Existing \(plural)")) {
            if let failure = model.rewriteFailure {
                SettingsProblemRow(
                    title: Text("Not Asked"), line: Text(verbatim: OwnerWording.line(failure, on: .connectors)),
                    actions: [])
            }
            if let failure = model.readBackFailure {
                OwnerProblemRow(
                    title: "Couldn’t Show the Request", failure: failure, line: readBackLine(failure), page: .connectors, host: host
                ) { Task { await model.readBack() } }
            }
            ForEach(model.pending(name)) { rewrite in
                SettingsRow(
                    verbatim: MappingWording.pendingTitle(rewrite, plural: plural), line: MappingWording.pendingLine(rewrite, connector: summary.title)
                ) { ProgressView().controlSize(.small) }
            }
            if let failure = model.countFailures[name] {
                OwnerProblemRow(title: "Couldn’t Count", failure: failure, page: .connectors, host: host) { Task { await model.count(name) } }
            }
            let count = model.counts[name]
            SettingsRow(
                verbatim: count.map { String(localized: "\($0) \(plural) Brought Before") }
                    ?? (model.countFailures[name] == nil ? String(localized: "Counting…") : String(localized: "Not Counted")),
                line: (count ?? 1) == 0
                    ? String(localized: "None are left to change.")
                    : String(localized: "They keep the old mapping until you apply this one.")
            ) {
                SettingsButton("Apply to Them…") { model.askToApply(name) }.disabled(!model.canApply(name))
            }
        }
    }
}
