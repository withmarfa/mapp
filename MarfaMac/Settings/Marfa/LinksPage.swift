import Marfa
import SwiftUI

/// Links between items, a page the Types page opens (its Links Between Items section), as the boards draw it: the owner's
/// link types with New Link Type…, those plugins brought and those Marfa ships, read only. One of the owner's opens a page of
/// its own with Delete…. It stands behind the Types page's gate.
struct LinksPage: View {
    static let subpage = SettingsSubpage(id: "links", title: String(localized: "Links"))
    private static let linkPrefix = "link:"

    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: LinksModel
    @Environment(\.settingsNavigation) private var navigation

    init(host: any MarfaSettingsHost, subpage: SettingsSubpage?) {
        self.host = host
        self.subpage = subpage
        _model = State(initialValue: LinksModel(context: OwnerContext(host: host)))
    }

    /// Whether `subpage` is this page or one of its link types' pages.
    static func shows(_ subpage: SettingsSubpage?) -> Bool {
        guard let id = subpage?.id else { return false }
        return id == Self.subpage.id || id.hasPrefix(linkPrefix)
    }

    private var openID: String? {
        guard let id = subpage?.id, id.hasPrefix(Self.linkPrefix) else { return nil }
        return String(id.dropFirst(Self.linkPrefix.count))
    }

    private func subpage(for type: OwnerLinkType) -> SettingsSubpage {
        SettingsSubpage(id: Self.linkPrefix + type.id, title: type.label)
    }

    var body: some View {
        content
            .task(id: host.serverAddress) { await model.load() }
            .onAppear { host.ownerDrafts.register(model) }
            .onChange(of: model.made) {
                guard let id = model.made, let type = model.linkType(id) else { return }
                model.acknowledgeMade()
                navigation?.push(subpage(for: type))
            }
            .onChange(of: model.deleted) {
                guard model.deleted != nil else { return }
                model.acknowledgeDeleted()
                navigation?.back()
            }
            .alert(
                model.question?.title ?? "", isPresented: Binding { model.question != nil } set: { if !$0 { model.dismissQuestion() } },
                presenting: model.question
            ) { asked in
                Button("Cancel", role: .cancel) { model.cancelDelete(asked) }
                Button("Delete Link Type", role: .destructive) { Task { await model.confirmDelete(asked) } }
            } message: { asked in
                Text(verbatim: asked.message)
            }
            .settingsSheet(presenting: model.isMaking, dismiss: { model.cancelNew() }) { NewLinkTypeSheet(model: model, host: host) }
            .accessibilityIdentifier("LinksPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .types, failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else if let id = openID {
            if let type = model.linkType(id) {
                LinkTypeDetail(model: model, type: type)
            } else {
                SettingsPageState(
                    symbol: "link", title: Text("This Link Type Is Gone"), line: Text("It was deleted, here or somewhere else."),
                    action: ("Back", { navigation?.back() }))
            }
        } else {
            list
        }
    }

    private var list: some View {
        SettingsPageColumn {
            SettingsSection("Yours") {
                if model.yours.isEmpty {
                    SettingsEmptyCard(symbol: "link", title: Text("No Link Types of Your Own"), line: Text("Make one to link items in a way of your own."))
                }
                ForEach(model.yours) { type in
                    SettingsLinkRow(verbatim: type.label, line: model.line(of: type), lead: .symbol("link")) { navigation?.push(subpage(for: type)) }
                }
                SettingsAddRow("New Link Type…") { model.beginNew() }
            }
            if !model.fromPlugins.isEmpty {
                SettingsSection("From Plugins", line: "Their plugins keep them.") {
                    ForEach(model.fromPlugins) { type in
                        SettingsRow(title: Text(verbatim: type.label), line: Text(verbatim: model.line(of: type)), lead: .symbol("link"))
                    }
                }
            }
            SettingsSection("Built In") {
                ForEach(model.builtIn) { type in
                    SettingsRow(title: Text(verbatim: type.label), lead: .symbol("link"))
                }
            }
        }
    }
}

/// One of the owner's link types: what it joins, and Delete….
struct LinkTypeDetail: View {
    let model: LinksModel
    let type: OwnerLinkType

    var body: some View {
        SettingsPageColumn {
            SettingsSection(name: nil) {
                SettingsRow("Name") { SettingsValue(verbatim: type.label) }
                if type.reverseLabel != type.label {
                    SettingsRow("Name at the Other End") { SettingsValue(verbatim: type.reverseLabel) }
                }
                SettingsRow("From") { SettingsValue(verbatim: end(type.fromTypes)) }
                SettingsRow("To") { SettingsValue(verbatim: end(type.toTypes)) }
                SettingsRow("How Many") { SettingsValue(verbatim: type.cardinality.title) }
                if let description = type.description, !description.isEmpty {
                    SettingsRow(title: Text("Description"), line: Text(verbatim: description), lines: nil)
                }
            }
            let failure = model.deleteLine(for: type.id)
            if model.isYours(type) || failure != nil {
                SettingsSection("Delete") {
                    SettingsRow(
                        title: Text("Delete \(type.label)"),
                        line: failure == nil ? Text("Marfa deletes a link type only while no item uses it.") : nil, error: failure, lines: nil
                    ) {
                        SettingsButton("Delete Link Type…", role: .destructive) { model.askToDelete(type.id) }
                            .disabled(model.isDeleting || !model.isYours(type))
                    }
                }
            }
        }
    }

    /// An end's item types by name, as the pop-ups in New Link Type… name them.
    private func end(_ constraints: [String]) -> String {
        if constraints.isEmpty || constraints.contains("*") { return String(localized: "Any Type") }
        return constraints.map { model.typeNames[$0] ?? $0 }.formatted(.list(type: .or))
    }
}

/// New Link Type…: its name, what each end takes and how many.
struct NewLinkTypeSheet: View {
    let model: LinksModel
    let host: any MarfaSettingsHost

    var body: some View {
        @Bindable var model = model
        let refusal = model.makeNeedsPermission || model.makeFailedUnsent ? nil : model.makeFailureLine
        return SettingsSheet(title: Text("New Link Type"), line: Text("A way one item can point to another, which every app can use.")) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFieldGap) {
                // What was sent stays as typed until the server answers.
                Group {
                    SettingsSheetField(label: "Name", error: refusal) {
                        SettingsField(
                            title: "Name", text: $model.name, prompt: String(localized: "Supplied By"), isError: refusal != nil, width: nil,
                            onSubmit: { Task { await model.make() } })
                    }
                    SettingsSheetField(label: "Name at the Other End") {
                        SettingsField(title: "Name at the Other End", text: $model.otherEndName, prompt: String(localized: "Optional"), width: nil)
                    }
                    SettingsSheetField(label: "From") { typePopUp("From", selection: $model.fromType) }
                    SettingsSheetField(label: "To") { typePopUp("To", selection: $model.toType) }
                    SettingsSheetField(label: "How Many") {
                        SettingsPopUp(title: "How Many", selection: $model.cardinality) {
                            ForEach(LinkCardinality.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                        }
                    }
                }
                .disabled(model.isWorking)
                if model.makeNeedsPermission, let line = model.makeFailureLine {
                    SettingsSection(name: nil) {
                        SettingsProblemRow(
                            title: Text("Not Made"), line: Text(verbatim: line), symbol: "lock", tone: nil,
                            actions: [
                                SettingsProblemAction(host.isAllowingMore ? "Waiting…" : "Allow More…") { Task { await model.allowMore() } }
                            ])
                            .disabled(host.isAllowingMore)
                    }
                } else if model.makeFailedUnsent, let line = model.makeFailureLine {
                    SettingsSection(name: nil) {
                        SettingsProblemRow(
                            title: Text("Not Made"), line: Text(verbatim: line),
                            actions: [SettingsProblemAction("Try Again") { Task { await model.make() } }])
                            .disabled(model.isWorking)
                    }
                }
            }
        } buttons: {
            SettingsButton("Cancel") { model.cancelNew() }.disabled(model.isWorking)
            SettingsButton("Create Link Type", role: .confirm) { Task { await model.make() } }.disabled(!model.canMake)
        }
    }

    private func typePopUp(_ title: LocalizedStringKey, selection: Binding<String?>) -> some View {
        SettingsPopUp(title: title, selection: selection) {
            Text("Any Type").tag(String?.none)
            ForEach(model.typeChoices, id: \.id) { Text(verbatim: $0.name).tag(Optional($0.id)) }
        }
    }
}

/// The Types page's Links Between Items section: one row that names the first link types and opens the Links page.
struct LinksSection: View {
    @State private var model: LinksModel
    let host: any MarfaSettingsHost
    @Environment(\.settingsNavigation) private var navigation

    init(host: any MarfaSettingsHost) {
        self.host = host
        _model = State(initialValue: LinksModel(context: OwnerContext(host: host)))
    }

    var body: some View {
        SettingsSection("Links Between Items") {
            SettingsLinkRow(
                verbatim: String(localized: "Links"), line: model.summary, lead: .symbol("link"),
                value: model.hasLoaded && model.failure == nil ? model.linkTypes.count.formatted() : nil
            ) { navigation?.push(LinksPage.subpage) }
        }
        .task(id: host.serverAddress) { await model.load() }
    }
}
