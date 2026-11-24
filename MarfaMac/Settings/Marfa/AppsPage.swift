import AppKit
import Marfa
import SwiftUI

/// The Apps page: the apps the owner approved, each opening a page of its own with what it may reach, which can only be
/// narrowed, the keys it made, the data it keeps and Disconnect. Narrowing, removing data and disconnecting ask first.
struct AppsPage: View {
    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: AppsModel
    /// The page view's, shared with the gate's states.
    let links: OpenLinksModel
    @Environment(\.settingsNavigation) private var navigation

    init(host: any MarfaSettingsHost, subpage: SettingsSubpage?, links: OpenLinksModel) {
        self.host = host
        self.subpage = subpage
        self.links = links
        _model = State(initialValue: AppsModel(context: OwnerContext(host: host), ownVendor: host.ownAppVendor))
    }

    static func subpage(for app: AppAccess) -> SettingsSubpage {
        SettingsSubpage(id: "app:" + app.id, title: AppsModel.name(of: app))
    }

    private var openApp: AppAccess? {
        guard let id = subpage?.id, id.hasPrefix("app:") else { return nil }
        return model.app(OwnerPermissions.owner(of: String(id.dropFirst(4))).base)
    }

    private var isShowingPermissions: Bool { subpage.map { OwnerPermissions.owner(of: $0.id).isList } ?? false }

    var body: some View {
        content
            .task(id: host.serverAddress) { await model.load() }
            .onChange(of: model.question) { _, asked in
                guard let asked else { return }
                // SwiftUI's alert has no checkbox, which Disconnect's "Also remove its data" is.
                SettingsAlert.confirm(
                    title: asked.title, message: asked.message, confirm: asked.confirm, checkbox: asked.checkbox, window: NSApp.keyWindow
                ) { confirmed, checked in
                    guard confirmed else { return model.cancelQuestion() }
                    Task { await model.confirm(asked, alsoRemovingData: checked) }
                }
            }
            .onChange(of: model.disconnected) { if $1 != nil { navigation?.back() } }
            .accessibilityIdentifier("AppsPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            standing { OwnerFailureState(page: .apps, failure: failure, host: host) { Task { await model.load() } } }
        } else if !model.hasLoaded {
            standing { OwnerLoading() }
        } else if subpage != nil {
            if let app = openApp {
                if isShowingPermissions {
                    AppPermissions(model: model, app: app, host: host)
                } else {
                    AppDetail(model: model, app: app, host: host)
                }
            } else {
                SettingsPageState(
                    symbol: "macwindow", title: Text("This App Isn’t Connected"),
                    line: Text("It was disconnected, here or somewhere else."), action: ("Back", { navigation?.back() }))
            }
        } else {
            list
        }
    }

    /// A state of the list keeps the Mac's own setting above it, which needs no Marfa. An app's page has none.
    @ViewBuilder private func standing<State: View>(@ViewBuilder _ state: () -> State) -> some View {
        if subpage == nil {
            SettingsStandingState { OpenLinksSection(model: links) } state: { state() }
        } else {
            state()
        }
    }

    private var list: some View {
        SettingsPageColumn {
            OpenLinksSection(model: links)
            SettingsSection("Connected") {
                if model.apps.isEmpty {
                    SettingsEmptyCard(symbol: "macwindow", title: Text("No Apps"), line: Text("No apps are connected."))
                }
                ForEach(model.apps) { app in
                    SettingsLinkRow(
                        verbatim: AppsModel.name(of: app),
                        line: AccessScopes.summary(AccessScopes.parse(app.scopes), names: model.typeNames),
                        lead: .well(symbol: Self.symbol(app.kind)), value: OwnerWording.used(app.lastUsed)
                    ) { navigation?.push(Self.subpage(for: app)) }
                }
            }
        }
    }

    static func symbol(_ kind: AppAccess.Kind) -> String {
        switch kind {
        case .app: "macwindow"
        case .web: "safari"
        case .commandLine: "terminal"
        }
    }
}

/// An app's owner permissions, the page the counted row opens.
private struct AppPermissions: View {
    let model: AppsModel
    let app: AppAccess
    let host: any MarfaSettingsHost

    var body: some View {
        OwnerPermissionsList(
            held: AccessScopes.parse(app.scopes).permissions, line: "The owner’s permissions. An app can only lose them.",
            problem: model.rowErrors[app.id], page: .apps, host: host
        ) { model.askToRemove(permission: $0, from: app) }
    }
}

/// One app's page.
private struct AppDetail: View {
    let model: AppsModel
    let app: AppAccess
    let host: any MarfaSettingsHost
    @Environment(\.settingsNavigation) private var navigation

    private var name: String { AppsModel.name(of: app) }
    private var parsed: AccessScopes.Parsed { AccessScopes.parse(app.scopes) }

    private var kindLine: String {
        let approved = app.granted.map { String(localized: "Approved \(OwnerWording.day($0)).") }
        let used = OwnerWording.used(app.lastUsed) + "."
        let kind: String =
            switch app.kind {
            case .app: String(localized: "An app.")
            case .commandLine: String(localized: "The command line.")
            case .web: String(localized: "A web page at \(app.origins.map(AddressesModel.display).formatted(.list(type: .and))).")
            }
        return [kind, approved, used].compactMap { $0 }.joined(separator: " ")
    }

    var body: some View {
        content
            // Here, not on the data section, which draws nothing until the first read ends.
            .task(id: app.id) { await model.readData(of: app) }
    }

    private var content: some View {
        SettingsPageColumn {
            SettingsHead(
                symbol: AppsPage.symbol(app.kind), tone: .purple, title: Text(verbatim: name), line: Text(verbatim: kindLine))
            if let failure = model.rowErrors[app.id] { OwnerProblem(title: "Not Changed", failure: failure, page: .apps, host: host) }
            SettingsSection(
                name: Text("Access"), line: Text("What \(name) may read and change."),
                footer: Text("You can only narrow it. \(name) asks you for more.")
            ) {
                if parsed.entries.isEmpty {
                    SettingsRow("Reaches No Items", look: .off)
                }
                ForEach(parsed.entries) { entry in
                    SettingsRow(verbatim: AccessScopes.title(of: entry.pattern, names: model.typeNames), lead: .custom(host.typeMark(for: entry.pattern))) {
                        SettingsPopUp(title: "Access", selection: Binding { entry.level } set: { model.askToNarrow(app, pattern: entry.pattern, to: $0) }) {
                            ForEach(AccessLevel.allCases.filter { $0 <= entry.level }, id: \.self) { Text(verbatim: $0.title).tag($0) }
                        }
                    }
                }
                OwnerPermissionsRow(held: parsed.permissions.count, line: String(localized: "The owner’s permissions. Most apps need none.")) {
                    navigation?.push(OwnerPermissions.subpage(of: AppsPage.subpage(for: app)))
                }
            }
            let keys = host.grants.contains(.keysManage) ? model.keysMade[app.clientID] ?? [] : []
            if !keys.isEmpty || model.keysFailure != nil {
                SettingsSection(name: Text("Keys It Made"), line: Text("They keep working when \(name) is disconnected.")) {
                    if let failure = model.keysFailure {
                        OwnerProblemRow(
                            title: "Couldn’t Read the Keys This App Made", failure: failure, page: .apps, host: host,
                            retry: { Task { await model.load() } })
                    }
                    ForEach(keys.sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }) { key in
                        SettingsRow(verbatim: key.label, line: OwnerWording.used(key.lastUsed) + ".", lead: .tile("key.fill", .amber))
                    }
                }
            }
            AppDataSection(model: model, app: app, host: host)
            SettingsSection("Disconnect") {
                SettingsRow(
                    verbatim: String(localized: "Disconnect \(name)"),
                    line: String(localized: "Its webhooks are deleted, its keys keep working, and it asks about its data.")
                ) {
                    SettingsButton("Disconnect…", role: .destructive) { model.askToDisconnect(app) }
                }
            }
        }
    }
}

/// What one app keeps under its own `app.<vendor>` namespaces, counted by state, with Remove…. Marfa answers counts, never a
/// size. The app's own settings are shown and never removed here.
private struct AppDataSection: View {
    let model: AppsModel
    let app: AppAccess
    let host: any MarfaSettingsHost

    private var name: String { AppsModel.name(of: app) }

    var body: some View {
        Group {
            switch model.data[app.id] {
            case nil, .reading?:
                EmptyView()
            case .failed(let failure)?:
                SettingsSection(name: Text("Data \(name) Keeps")) {
                    OwnerProblemRow(title: "Couldn’t Read Its Data", failure: failure, page: .apps, host: host) {
                        Task { await model.readData(of: app) }
                    }
                    removalNote
                }
            case .kept(let kept)?:
                SettingsSection(name: Text("Data \(name) Keeps")) {
                    if kept.isEmpty {
                        SettingsRow(verbatim: String(localized: "\(name) Keeps No Data"), look: .off)
                    }
                    ForEach(kept, id: \.vendor) { held in row(held, among: kept.count) }
                    removalNote
                }
            }
        }
    }

    /// What a removal that deleted items and then stopped says, drawn whether or not the data could be read again.
    @ViewBuilder private var removalNote: some View {
        if let note = model.removalNote(for: app) {
            SettingsProblemRow(title: Text(verbatim: note.title), line: Text(verbatim: note.line), actions: [])
        }
    }

    private func row(_ held: AppData, among count: Int) -> some View {
        let title = count == 1 ? String(localized: "\(name)’s Own Data") : held.vendor
        return SettingsRow(
            verbatim: title, line: AppDataWording.line(held, appName: name, keptByApp: model.isOwn(held.vendor)), lines: nil
        ) {
            if !model.isOwn(held.vendor), !held.types.isEmpty {
                SettingsButton("Remove…", role: .destructive) { model.askToRemoveData(app, vendor: held.vendor) }
                    .disabled(model.removing.contains(app.id))
            }
        }
    }
}
