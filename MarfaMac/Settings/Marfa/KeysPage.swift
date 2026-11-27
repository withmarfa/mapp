import Marfa
import SwiftUI

/// Apps with standing access and the keys the current sign-in can manage.
struct KeysPage: View {
    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: KeysModel
    @State private var apps: AppsModel
    @Environment(\.settingsNavigation) private var navigation

    init(host: any MarfaSettingsHost, subpage: SettingsSubpage?) {
        self.host = host
        self.subpage = subpage
        _model = State(initialValue: KeysModel(context: OwnerContext(host: host)))
        _apps = State(initialValue: AppsModel(context: OwnerContext(host: host), ownVendor: host.ownAppVendor))
    }

    static func subpage(for key: KeyInfo) -> SettingsSubpage {
        SettingsSubpage(id: "key:" + key.id, title: key.label)
    }

    private var openKeyID: String? {
        guard let id = subpage?.id, id.hasPrefix("key:") else { return nil }
        return OwnerPermissions.owner(of: String(id.dropFirst(4))).base
    }

    private var isShowingPermissions: Bool { subpage.map { OwnerPermissions.owner(of: $0.id).isList } ?? false }

    var body: some View {
        content
            .task(id: host.grants.intersection([.keysManage, .keysMint])) {
                if model.canReadKeys { await model.load() }
            }
            .onAppear { host.ownerDrafts.register(model) }
            .settingsSheet(presenting: model.sheet != nil, dismiss: { model.dismissSheet() }) { KeySheet(model: model) }
            .alert(
                model.question?.title ?? "", isPresented: Binding { model.question != nil } set: { if !$0 { model.cancelQuestion() } },
                presenting: model.question
            ) { asked in
                Button("Cancel", role: .cancel) {}
                Button(asked.confirm, role: .destructive) { Task { await model.confirm(asked) } }
            } message: { asked in
                Text(verbatim: asked.message)
            }
            .onChange(of: model.revoked) { if $1 == openKeyID, $1 != nil { navigation?.back() } }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("KeysPage")
    }

    @ViewBuilder private var content: some View {
        if let id = openKeyID {
            if !model.canReadKeys {
                SettingsPageState(
                    symbol: "lock", title: Text("Needs a Permission"), line: Text(verbatim: MarfaSettingsPage.keys.permissionLine),
                    action: ("Allow More", { host.askForMore(naming: InstancePermission.keysManage.rawValue) }))
            } else if model.failure != nil || !model.hasLoaded {
                loadState
            } else {
                if let key = model.key(id) {
                    if isShowingPermissions {
                        KeyPermissions(model: model, key: key, host: host)
                    } else {
                        KeyDetail(model: model, key: key, host: host)
                    }
                } else {
                    SettingsPageState(
                        symbol: "key", title: Text("This Key Is Gone"), line: Text("It was revoked, or it expired, somewhere else."),
                        action: ("Back", { navigation?.back() }))
                }
            }
        } else {
            list
        }
    }

    @ViewBuilder private var loadState: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .keys, failure: failure, host: host) { Task { await model.load() } }
        } else {
            OwnerLoading()
        }
    }

    private var list: some View {
        SettingsPageColumn {
            SignedInAppsSection(model: apps, host: host)
            SettingsSection("Your Keys", footer: "Keys made by connected apps are on those apps’ pages.") {
                if model.canMake {
                    SettingsButton("New Key…") { model.beginNewKey() }
                }
            } content: {
                if !model.canExtend {
                    OwnerProblemRow(
                        title: "Manage All Keys", failure: .notPermitted(InstancePermission.keysManage.rawValue),
                        line: MarfaSettingsPage.keys.permissionLine, page: .keys, host: host)
                }
                if model.canReadKeys {
                    if let failure = model.failure {
                        OwnerProblemRow(title: "Couldn’t Read Keys", failure: failure, page: .keys, host: host) {
                            Task { await model.load() }
                        }
                    } else if !model.hasLoaded {
                        OwnerLoading()
                    } else if model.ownersKeys.isEmpty {
                        SettingsEmptyCard(symbol: "key", title: Text("No Keys"), line: Text("You haven’t made any keys this sign-in can see."))
                    } else {
                        ForEach(model.ownersKeys) { row($0) }
                    }
                }
                if !model.canMake {
                    SettingsAddRow(
                        off: "New Key…", line: "The app isn’t allowed to make keys.",
                        remedy: (host.isAllowingMore ? "Waiting…" : "Allow More…", {
                            Task { _ = await host.allowMore([.keysMint]) }
                        }))
                }
            }
            if model.canReadKeys, model.hasLoaded, model.failure == nil, !otherAppKeys.isEmpty {
                SettingsSection("Made by Apps", line: "They keep working when the app is disconnected.") {
                    ForEach(otherAppKeys) { row($0) }
                }
            }
        }
    }

    private var otherAppKeys: [KeyInfo] {
        guard apps.canReadApps, apps.hasLoaded, apps.failure == nil else { return model.appKeys }
        let connected = Set(apps.apps.map(\.clientID))
        return model.appKeys.filter { !connected.contains($0.appClientID ?? "") }
    }

    @ViewBuilder
    private func row(_ key: KeyInfo) -> some View {
        SettingsRow(
            verbatim: key.label, line: Self.line(key, names: model.typeNames, isCurrent: model.isCurrent(key)), lead: .symbol("key")
        ) {
            HStack(spacing: SettingsTokens.Metric.buttonGap) {
                SettingsValue(verbatim: OwnerWording.used(key.lastUsed)).fixedSize()
                SettingsMoreMenu {
                    Button("Open Key Settings") { navigation?.push(Self.subpage(for: key)) }
                    Button("Revoke", role: .destructive) { model.askToRevoke(key) }
                }
                .accessibilityLabel(Text("Actions for \(key.label)"))
            }
        }
        .help(Text(verbatim: key.label))
        if let failure = model.rowErrors[key.id] {
            let line = failure == .unreachable
                ? String(localized: "The app can’t reach the server to confirm whether this key was revoked.")
                : OwnerWording.line(failure, on: .keys)
            OwnerProblemRow(title: "Couldn’t Revoke Key", failure: failure, line: line, page: .keys, host: host)
        }
    }

    /// What the key reaches, then when it ends.
    static func line(_ key: KeyInfo, names: [String: String], isCurrent: Bool = false) -> String {
        let identity = isCurrent ? String(localized: "Used to sign in on this Mac.") + " " : ""
        let reach = AppsPage.accessLine(KeyAccess.parsed(key), names: names)
        return identity + reach + " " + expiryLine(key)
    }

    static func expiryLine(_ key: KeyInfo, now: Date = .now) -> String {
        guard let expiry = key.expires else { return String(localized: "Never expires.") }
        let day = OwnerWording.day(expiry)
        return expiry <= now ? String(localized: "Expired \(day).") : String(localized: "Expires \(day).")
    }
}
/// A key's types as the entries an app's access is read as.
nonisolated enum KeyAccess {
    static func parsed(_ key: KeyInfo) -> AccessScopes.Parsed {
        AccessScopes.Parsed(
            entries: key.types.sorted { $0.key < $1.key }.map { AccessScopes.Entry(pattern: $0.key, level: $0.value) },
            permissions: key.permissions.sorted())
    }
}

/// One key's page.
private struct KeyDetail: View {
    let model: KeysModel
    let key: KeyInfo
    let host: any MarfaSettingsHost
    @Environment(\.settingsNavigation) private var navigation

    private var parsed: AccessScopes.Parsed { KeyAccess.parsed(key) }

    private var line: String {
        let made = key.created.map { String(localized: "Made \(OwnerWording.day($0)).") }
        let identity = model.isCurrent(key) ? String(localized: "Used to sign in on this Mac.") : nil
        return [identity, made, OwnerWording.used(key.lastUsed) + "."].compactMap { $0 }.joined(separator: " ")
    }

    var body: some View {
        SettingsPageColumn {
            SettingsHead(symbol: "key.fill", tone: .amber, title: Text(verbatim: key.label), line: Text(verbatim: line)) {
                SettingsButton("Rename…") { model.beginRename(key) }
            }
            if let failure = model.rowErrors[key.id] {
                let line = failure == .unreachable ? String(localized: "The app can’t reach the server to confirm the result.") : nil
                SettingsSection(name: nil) {
                    OwnerProblemRow(title: "Couldn’t Change Key", failure: failure, line: line, page: .keys, host: host)
                }
            }
            SettingsSection("Key") {
                expires
                SettingsRow("New Items Go To", line: "The feed, or straight into the library.") {
                    SettingsPopUp(title: "New Items Go To", selection: Binding { key.tier } set: { tier in Task { await model.setTier(tier, of: key) } }) {
                        ForEach(KeyTier.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                    }
                }
                SettingsRow("Source", line: "Stamped on what it writes.") { SettingsLockedValue(text: key.source) }
            }
            SettingsSection(name: Text("Access"), line: Text("What it may read and change. It can only be narrowed.")) {
                if parsed.entries.isEmpty {
                    SettingsRow("Reaches No Items", look: .off)
                }
                ForEach(parsed.entries) { entry in
                    SettingsRow(verbatim: AccessScopes.title(of: entry.pattern, names: model.typeNames), lead: .custom(host.typeMark(for: entry.pattern))) {
                        SettingsPopUp(title: "Access", selection: Binding { entry.level } set: { level in
                            model.askToNarrow(key, pattern: entry.pattern, to: level)
                        }) {
                            ForEach(AccessLevel.allCases.filter { $0 <= entry.level }, id: \.self) { Text(verbatim: $0.title).tag($0) }
                        }
                    }
                }
                ownerPermissions
            }
            SettingsSection("Revoke") {
                SettingsRow(verbatim: String(localized: "Revoke \(key.label)"), line: String(localized: "Anything using it stops at once.")) {
                    SettingsButton("Revoke", role: .destructive) { model.askToRevoke(key) }
                }
            }
        }
    }

    /// The expiry with Extend…, which only a sign-in holding Manage Keys may use. Without it the row says so, with Allow More….
    @ViewBuilder private var expires: some View {
        let ends = key.expires.map { OwnerWording.day($0) } ?? String(localized: "Never")
        if !model.canExtend {
            SettingsRow("Expires") { SettingsValue(verbatim: ends) }
            OwnerProblemRow(
                title: "Can’t Extend This Key", failure: .notPermitted(InstancePermission.keysManage.rawValue), line: KeysModel.notAllowedToExtend,
                page: .keys, host: host)
        } else if let failure = model.identityFailure {
            SettingsRow("Expires") { SettingsValue(verbatim: ends) }
            OwnerProblemRow(
                title: "Can’t Extend This Key Yet", failure: failure,
                line: String(localized: "The app couldn’t read when its own sign-in ends, which limits how long a key can be given."), page: .keys,
                host: host, retry: { Task { await model.load() } })
        } else if model.extensions(of: key).isEmpty {
            SettingsRow("Expires", line: key.expires == nil ? "It never ends." : "The app’s own sign-in ends sooner, so it can’t give this key longer.") {
                SettingsValue(verbatim: ends)
            }
        } else {
            SettingsRow(title: Text("Expires"), line: Text("\(ends). Extending keeps the same key, so nothing using it changes.")) {
                SettingsButton("Extend…") { model.beginExtend(key) }
            }
        }
    }

    private var ownerPermissions: some View {
        OwnerPermissionsRow(held: parsed.permissions.count, line: String(localized: "The owner’s permissions. Most keys need none.")) {
            navigation?.push(OwnerPermissions.subpage(of: KeysPage.subpage(for: key)))
        }
    }
}

/// A key's owner permissions, the page the counted row opens.
private struct KeyPermissions: View {
    let model: KeysModel
    let key: KeyInfo
    let host: any MarfaSettingsHost

    var body: some View {
        OwnerPermissionsList(
            held: KeyAccess.parsed(key).permissions, line: "The owner’s permissions. A key can only lose them.",
            problem: model.rowErrors[key.id], page: .keys, host: host
        ) { model.askToRemove(permission: $0, from: key) }
    }
}
