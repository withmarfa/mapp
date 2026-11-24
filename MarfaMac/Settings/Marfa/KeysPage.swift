import AppKit
import Marfa
import SwiftUI

/// The Keys page: the owner's keys and the keys apps made, each opening a page of its own, and New Key…. A key's page
/// holds its expiry (with Extend…), its source, what it may reach (which can only be narrowed) and Revoke.
struct KeysPage: View {
    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: KeysModel
    @Environment(\.settingsNavigation) private var navigation

    init(host: any MarfaSettingsHost, subpage: SettingsSubpage?) {
        self.host = host
        self.subpage = subpage
        _model = State(initialValue: KeysModel(context: OwnerContext(host: host)))
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
            .task(id: host.serverAddress) { await model.load() }
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
            .onChange(of: model.revoked) { if $1 != nil { navigation?.back() } }
            .accessibilityIdentifier("KeysPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .keys, failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else if let id = openKeyID {
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
        } else {
            list
        }
    }

    private var list: some View {
        SettingsPageColumn {
            SettingsSection("Yours") {
                ForEach(model.ownersKeys) { row($0) }
                newKeyRow
            }
            if !model.appKeys.isEmpty {
                SettingsSection("Made by Apps", line: "They keep working when the app is disconnected.") {
                    ForEach(model.appKeys) { row($0) }
                }
            }
        }
    }

    @ViewBuilder private var newKeyRow: some View {
        if model.canMake {
            SettingsAddRow("New Key…") { model.beginNewKey() }
        } else {
            SettingsAddRow(
                off: "New Key…", line: "The app isn’t allowed to make keys.",
                remedy: (host.isAllowingMore ? "Waiting…" : "Allow More…", {
                    let host = host
                    Task { _ = await host.allowMore([.keysMint]) }
                }))
        }
    }

    private func row(_ key: KeyInfo) -> some View {
        SettingsLinkRow(
            verbatim: key.label, line: Self.line(key, names: model.typeNames), lead: .tile("key.fill", .amber),
            value: OwnerWording.used(key.lastUsed)
        ) { navigation?.push(Self.subpage(for: key)) }
    }

    /// What the key reaches, then when it ends.
    static func line(_ key: KeyInfo, names: [String: String]) -> String {
        let reach = AccessScopes.summary(KeyAccess.parsed(key), names: names)
        let ends = key.expires.map { String(localized: "Expires \(OwnerWording.day($0)).") } ?? String(localized: "Never expires.")
        return reach + " " + ends
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
        return [made, OwnerWording.used(key.lastUsed) + "."].compactMap { $0 }.joined(separator: " ")
    }

    var body: some View {
        SettingsPageColumn {
            SettingsHead(symbol: "key.fill", tone: .amber, title: Text(verbatim: key.label), line: Text(verbatim: line)) {
                SettingsButton("Rename…") { model.beginRename(key) }
            }
            if let failure = model.rowErrors[key.id] { OwnerProblem(title: "Not Changed", failure: failure, page: .keys, host: host) }
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
                    SettingsButton("Revoke…", role: .destructive) { model.askToRevoke(key) }
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

    static func title(days: Int) -> String {
        switch days {
        case 1: String(localized: "Tomorrow")
        case 365: String(localized: "In 1 Year")
        default: String(localized: "In \(days) Days")
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

/// The Keys page's sheets, which the window shows in its middle: New Key, the key shown once, Rename and Extend.
struct KeySheet: View {
    @Bindable var model: KeysModel

    var body: some View {
        switch model.sheet {
        case .new?: NewKeySheet(model: model)
        case .shown?: ShownKeySheet(model: model)
        case .rename?: RenameKeySheet(model: model)
        case .extend(let id)?: ExtendKeySheet(model: model, key: model.key(id))
        case nil: EmptyView()
        }
    }
}

private struct NewKeySheet: View {
    @Bindable var model: KeysModel

    private static let expiries: [KeysModel.Expiry] = [.days(7), .days(30), .days(90), .days(365), .never]

    private func title(_ expiry: KeysModel.Expiry) -> String {
        switch expiry {
        case .never: String(localized: "Never")
        case .days(let days): KeyDetail.title(days: days)
        }
    }

    private var exceptionPatterns: [String] { model.draft.exceptions.keys.sorted() }

    private var addable: [(id: String, name: String)] {
        model.typeNames.filter { model.draft.exceptions[$0.key] == nil }.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    private var permissionCount: String {
        OwnerWording.permissionCount(model.draft.permissions.count, of: model.givablePermissions.count)
    }

    var body: some View {
        if model.isChoosingPermissions {
            permissionsPage
        } else {
            fieldsPage
        }
    }

    private var fieldsPage: some View {
        SettingsSheet(
            title: Text("New Key"), line: Text("A key can only be narrowed later, so choose what it needs now."), isWide: true
        ) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFormGap) {
                SettingsSheetField(label: "Name", error: model.draftError) {
                    SettingsField(title: "Name", text: Binding { model.draft.name } set: { name in
                        if model.draft.source == KeysModel.source(from: model.draft.name) { model.draft.source = KeysModel.source(from: name) }
                        model.draft.name = name
                    }, isError: model.draftError != nil, width: nil)
                }
                SettingsSheetField(label: "Source, Stamped on What It Writes", error: model.sourceError) {
                    SettingsField(title: "Source", text: $model.draft.source, isError: model.sourceError != nil, isMonospaced: true, width: nil)
                }
                SettingsSection("Key") {
                    SettingsRow("Expires") {
                        SettingsPopUp(title: "Expires", selection: $model.draft.expires) {
                            ForEach(Self.expiries, id: \.self) { Text(verbatim: title($0)).tag($0) }
                        }
                    }
                    SettingsRow("New Items Go To") {
                        SettingsPopUp(title: "New Items Go To", selection: $model.draft.tier) {
                            ForEach(KeyTier.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                        }
                    }
                }
                SettingsSection("Access") {
                    SettingsRow("Every Type", lead: .symbol("tray.full")) {
                        SettingsPopUp(title: "Every Type", selection: $model.draft.everyType) {
                            ForEach(AccessLevel.allCases.reversed(), id: \.self) { Text(verbatim: $0.title).tag($0) }
                        }
                    }
                    ForEach(exceptionPatterns, id: \.self) { pattern in
                        SettingsRow(verbatim: AccessScopes.title(of: pattern, names: model.typeNames), lead: .symbol("tray")) {
                            HStack(spacing: SettingsTokens.Metric.buttonGap) {
                                SettingsPopUp(title: "Access", selection: Binding { model.draft.exceptions[pattern] ?? .read } set: { model.draft.exceptions[pattern] = $0 }) {
                                    ForEach(AccessLevel.allCases.reversed(), id: \.self) { Text(verbatim: $0.title).tag($0) }
                                }
                                SettingsMoreMenu { Button("Remove", role: .destructive) { model.draft.exceptions[pattern] = nil } }
                            }
                        }
                    }
                    if !model.givablePermissions.isEmpty {
                        SettingsRow(title: Text("Look After This Marfa"), line: Text(verbatim: permissionCount)) {
                            SettingsButton("Choose…") { model.isChoosingPermissions = true }
                        }
                    }
                    if !addable.isEmpty {
                        SettingsAddMenu("Add an Exception…") {
                            ForEach(addable, id: \.id) { type in
                                Button(type.name) { model.draft.exceptions[type.id] = .read }
                            }
                        }
                    }
                }
                Text("The source can’t change later.").settingsFont(.footer).foregroundStyle(SettingsTokens.secondaryText)
            }
        } buttons: {
            SettingsButton("Cancel") { model.closeSheet() }
            SettingsButton("Create Key", role: .confirm) { Task { await model.make() } }.disabled(!model.canMakeDraft)
        }
    }

    /// The owner's permissions, a page of the sheet: one switch each, and Back to the fields with what was chosen kept.
    private var permissionsPage: some View {
        SettingsSheet(
            title: Text("Look After This Marfa"), line: Text("The owner’s permissions. Most keys need none."), isWide: true
        ) {
            SettingsSection(name: nil) {
                ForEach(model.givablePermissions, id: \.self) { permission in
                    SettingsRow(verbatim: OwnerWording.title(of: permission), size: .compact) {
                        SettingsToggle(title: "Allowed", isOn: Binding { model.draft.permissions.contains(permission) } set: { on in
                            if on { model.draft.permissions.insert(permission) } else { model.draft.permissions.remove(permission) }
                        })
                    }
                }
            }
        } buttons: {
            SettingsButton("Back", role: .confirm) { model.isChoosingPermissions = false }
        }
    }
}

private struct ShownKeySheet: View {
    let model: KeysModel
    @State private var copied = false

    var body: some View {
        SettingsSheet(title: Text("Copy the Key Now"), line: Text("It is shown only once. Keep it where the script can read it.")) {
            if let created = model.created {
                SettingsSheetField(verbatim: created.label) { SettingsReadOnlyValue(text: created.secret) }
            }
        } buttons: {
            SettingsButton(copied ? "Copied" : "Copy") {
                guard let secret = model.created?.secret else { return }
                OwnerClipboard.copySecret(secret)
                copied = true
            }
            SettingsButton("Done", role: .confirm) { model.closeSheet() }
        }
    }
}

private struct RenameKeySheet: View {
    @Bindable var model: KeysModel

    var body: some View {
        SettingsSheet(title: Text("Rename Key")) {
            SettingsSheetField(label: "Name", error: model.renameError) {
                SettingsField(
                    title: "Name", text: $model.renameDraft, isError: model.renameError != nil, width: nil,
                    onSubmit: { Task { await model.rename() } })
            }
        } buttons: {
            SettingsButton("Cancel") { model.closeSheet() }
            SettingsButton("Rename", role: .confirm) { Task { await model.rename() } }.disabled(!model.canRename)
        }
    }
}

private struct ExtendKeySheet: View {
    @Bindable var model: KeysModel
    let key: KeyInfo?

    private func title(_ choice: KeysModel.Extension) -> String {
        switch choice {
        case .never: String(localized: "Never")
        case .days(let days): KeyDetail.title(days: days)
        }
    }

    var body: some View {
        SettingsSheet(
            title: Text("Extend Key"), line: Text("The key itself stays the same, so nothing using it needs to change.")
        ) {
            SettingsSection(name: nil) {
                SettingsRow(
                    title: Text("Expires"), line: key?.expires.map { Text("Now \(OwnerWording.day($0)).") }, error: model.extendError,
                    lines: nil
                ) {
                    SettingsPopUp(title: "Expires", selection: $model.extensionChoice, isError: model.extendError != nil) {
                        ForEach(key.map { model.extensions(of: $0) } ?? [], id: \.self) { Text(verbatim: title($0)).tag($0) }
                    }
                }
            }
        } buttons: {
            SettingsButton("Cancel") { model.closeSheet() }
            SettingsButton("Extend", role: .confirm) { Task { await model.extend() } }.disabled(model.isExtending)
        }
    }
}
