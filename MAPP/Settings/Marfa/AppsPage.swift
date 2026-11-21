import SwiftUI

/// The Apps page: the apps the owner approved, each opening a page of its own with what it may reach, which can only be
/// narrowed, the keys it made and Disconnect. Narrowing and disconnecting ask first.
struct AppsPage: View {
    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: AppsModel
    @Environment(\.settingsPush) private var push
    @Environment(\.settingsBack) private var back

    init(host: any MarfaSettingsHost, subpage: SettingsSubpage?) {
        self.host = host
        self.subpage = subpage
        _model = State(initialValue: AppsModel(context: OwnerContext(host: host)))
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
            .alert(
                model.question?.title ?? "", isPresented: Binding { model.question != nil } set: { if !$0 { model.cancelQuestion() } },
                presenting: model.question
            ) { asked in
                Button("Cancel", role: .cancel) {}
                Button(asked.confirm, role: .destructive) { Task { await model.confirm(asked) } }
            } message: { asked in
                Text(verbatim: asked.message)
            }
            .onChange(of: model.disconnected) { if $1 != nil { back() } }
            .accessibilityIdentifier("AppsPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .apps, failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
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
                    line: Text("It was disconnected, here or somewhere else."), action: ("Back", back))
            }
        } else {
            list
        }
    }

    private var list: some View {
        SettingsPageColumn {
            SettingsSection("Connected") {
                if model.apps.isEmpty {
                    SettingsEmptyCard(symbol: "macwindow", title: Text("No Apps"), line: Text("No apps are connected."))
                }
                ForEach(model.apps) { app in
                    SettingsLinkRow(
                        verbatim: AppsModel.name(of: app),
                        line: AccessScopes.summary(AccessScopes.parse(app.scopes), names: model.typeNames),
                        lead: .well(symbol: Self.symbol(app.kind)), value: OwnerWording.used(app.lastUsed)
                    ) { push(Self.subpage(for: app)) }
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
    @Environment(\.settingsPush) private var push

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
                    SettingsRow(verbatim: AccessScopes.title(of: entry.pattern, names: model.typeNames), lead: .symbol("tray.full")) {
                        SettingsPopUp(title: "Access", selection: Binding { entry.level } set: { model.askToNarrow(app, pattern: entry.pattern, to: $0) }) {
                            ForEach(AccessLevel.allCases.filter { $0 <= entry.level }, id: \.self) { Text(verbatim: $0.title).tag($0) }
                        }
                    }
                }
                OwnerPermissionsRow(held: parsed.permissions.count, line: String(localized: "The owner’s permissions. Most apps need none.")) {
                    push(OwnerPermissions.subpage(of: AppsPage.subpage(for: app)))
                }
            }
            if let keys = model.keysMade[app.clientID], !keys.isEmpty {
                SettingsSection(name: Text("Keys It Made"), line: Text("They keep working when \(name) is disconnected.")) {
                    ForEach(keys.sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }) { key in
                        SettingsRow(verbatim: key.label, line: OwnerWording.used(key.lastUsed) + ".", lead: .tile("key.fill", .amber))
                    }
                }
            }
            SettingsSection("Disconnect") {
                SettingsRow(
                    verbatim: String(localized: "Disconnect \(name)"),
                    line: String(localized: "Its webhooks are deleted, and its keys keep working.")
                ) {
                    SettingsButton("Disconnect…", role: .destructive) { model.askToDisconnect(app) }
                }
            }
        }
    }
}
