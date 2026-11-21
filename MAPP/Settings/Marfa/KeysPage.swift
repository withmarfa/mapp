import AppKit
import Marfa
import SwiftUI

/// The Keys page: the owner's keys and the keys apps made, each opening a page of its own, and New Key…. A key's page
/// holds its expiry, its source, what it may reach (which can only be narrowed) and Revoke.
struct KeysPage: View {
    let host: any MarfaSettingsHost
    let subpage: SettingsSubpage?
    @State private var model: KeysModel
    @Environment(\.settingsPush) private var push
    @Environment(\.settingsBack) private var back

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
        return String(id.dropFirst(4))
    }

    var body: some View {
        content
            .task(id: host.serverAddress) { await model.load() }
            .settingsSheet(presenting: model.sheet != nil, dismiss: { model.closeSheet() }) { KeySheet(model: model) }
            .alert(
                model.question?.title ?? "", isPresented: Binding { model.question != nil } set: { if !$0 { model.cancelQuestion() } },
                presenting: model.question
            ) { asked in
                Button("Cancel", role: .cancel) {}
                Button(asked.confirm, role: .destructive) { Task { await model.confirm(asked) } }
            } message: { asked in
                Text(verbatim: asked.message)
            }
            .onChange(of: model.revoked) { if $1 != nil { back() } }
            .accessibilityIdentifier("KeysPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else if let id = openKeyID {
            if let key = model.key(id) {
                KeyDetail(model: model, key: key)
            } else {
                SettingsPageState(
                    symbol: "key", title: Text("This Key Is Gone"), line: Text("It was revoked, or it expired, somewhere else."),
                    action: ("Back", back))
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
                off: "New Key…", line: "MAPP isn’t allowed to make keys.",
                remedy: (host.isAllowingMore ? "Waiting…" : "Allow More…", {
                    let host = host
                    Task { _ = await host.allowMore([.keysMint]) }
                }))
        }
    }

    private func row(_ key: KeyInfo) -> some View {
        SettingsLinkRow(
            verbatim: key.label, line: Self.line(key, names: model.typeNames), lead: .tile("key.fill", .yellow),
            value: OwnerWording.used(key.lastUsed)
        ) { push(Self.subpage(for: key)) }
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

    private static let steps = [1, 7, 30, 90, 365]

    private var parsed: AccessScopes.Parsed { KeyAccess.parsed(key) }

    private var line: String {
        let made = key.created.map { String(localized: "Made \(OwnerWording.day($0)).") }
        return [made, OwnerWording.used(key.lastUsed) + "."].compactMap { $0 }.joined(separator: " ")
    }

    /// The days from now at which the key could be made to end, that fall before it ends now.
    private var earlier: [Int] {
        Self.steps.filter { days in
            guard let ends = key.expires else { return true }
            return (Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .distantFuture) < ends
        }
    }

    var body: some View {
        SettingsPageColumn {
            SettingsHead(symbol: "key.fill", tone: .yellow, title: Text(verbatim: key.label), line: Text(verbatim: line)) {
                SettingsButton("Rename…") { model.beginRename(key) }
            }
            if let line = model.rowErrors[key.id] { OwnerProblem(title: "Not Changed", line: line) }
            SettingsSection("Key") {
                SettingsRow("Expires", line: "A key can only be made to end sooner.") {
                    SettingsPopUp(title: "Expires", selection: Binding { 0 } set: { days in
                        if days > 0, let date = Calendar.current.date(byAdding: .day, value: days, to: .now) { model.askToExpire(key, on: date) }
                    }) {
                        Text(verbatim: key.expires.map { OwnerWording.day($0) } ?? String(localized: "Never")).tag(0)
                        if !earlier.isEmpty { Divider() }
                        ForEach(earlier, id: \.self) { Text(Self.title(days: $0)).tag($0) }
                    }
                }
                SettingsRow("New Items Go To", line: "The feed, or straight into the library.") {
                    SettingsPopUp(title: "New Items Go To", selection: Binding { key.tier } set: { tier in Task { await model.setTier(tier, of: key) } }) {
                        ForEach(KeyTier.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                    }
                }
                SettingsRow("Source", line: "Stamped on what it writes. It can’t change.") { SettingsValue(verbatim: key.source) }
            }
            SettingsSection(name: Text("Access"), line: Text("What it may read and change. It can only be narrowed.")) {
                if parsed.entries.isEmpty {
                    SettingsRow("Reaches No Items", look: .off)
                }
                ForEach(parsed.entries) { entry in
                    SettingsRow(verbatim: AccessScopes.title(of: entry.pattern, names: model.typeNames), lead: .symbol("tray.full")) {
                        SettingsPopUp(title: "Access", selection: Binding { entry.level } set: { level in
                            Task { await model.narrow(key, pattern: entry.pattern, to: level) }
                        }) {
                            ForEach(AccessLevel.allCases.filter { $0 <= entry.level }, id: \.self) { Text(verbatim: $0.title).tag($0) }
                        }
                    }
                }
                ForEach(parsed.permissions, id: \.self) { permission in
                    SettingsRow(verbatim: OwnerWording.title(of: permission), lead: .symbol("gearshape")) {
                        SettingsPopUp(title: "Permission", selection: Binding { true } set: { allowed in
                            if !allowed { Task { await model.remove(permission: permission, from: key) } }
                        }) {
                            Text("Allowed").tag(true)
                            Text("Not Allowed").tag(false)
                        }
                    }
                }
            }
            SettingsSection("Revoke") {
                SettingsRow(verbatim: String(localized: "Revoke \(key.label)"), line: String(localized: "Anything using it stops at once.")) {
                    SettingsButton("Revoke…", role: .destructive) { model.askToRevoke(key) }
                }
            }
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

/// The Keys page's sheets, which the window shows in its middle: New Key, the key shown once and Rename.
struct KeySheet: View {
    @Bindable var model: KeysModel

    var body: some View {
        switch model.sheet {
        case .new?: NewKeySheet(model: model)
        case .shown?: ShownKeySheet(model: model)
        case .rename?: RenameKeySheet(model: model)
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

    var body: some View {
        SettingsSheet(
            title: Text("New Key"), line: Text("A key can only be narrowed later, so choose what it needs now."), isWide: true
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSheetField(label: "Name", error: model.draftError) {
                        SettingsField(title: "Name", text: Binding { model.draft.name } set: { name in
                            if model.draft.source == KeysModel.source(from: model.draft.name) { model.draft.source = KeysModel.source(from: name) }
                            model.draft.name = name
                        }, isError: model.draftError != nil, width: nil)
                    }
                    SettingsSheetField(label: "Source, Stamped on What It Writes") {
                        SettingsField(title: "Source", text: $model.draft.source, isMonospaced: true, width: nil)
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
                                HStack(spacing: 8) {
                                    SettingsPopUp(title: "Access", selection: Binding { model.draft.exceptions[pattern] ?? .read } set: { model.draft.exceptions[pattern] = $0 }) {
                                        ForEach(AccessLevel.allCases.reversed(), id: \.self) { Text(verbatim: $0.title).tag($0) }
                                    }
                                    SettingsMoreMenu { Button("Remove", role: .destructive) { model.draft.exceptions[pattern] = nil } }
                                }
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
                    if !model.givablePermissions.isEmpty {
                        SettingsSection(name: Text("Look After This Marfa"), line: Text("The owner’s permissions. Most keys need none.")) {
                            ForEach(model.givablePermissions, id: \.self) { permission in
                                SettingsRow(verbatim: OwnerWording.title(of: permission), size: .compact) {
                                    SettingsToggle(title: "Allowed", isOn: Binding { model.draft.permissions.contains(permission) } set: { on in
                                        if on { model.draft.permissions.insert(permission) } else { model.draft.permissions.remove(permission) }
                                    })
                                }
                            }
                        }
                    }
                    Text("The source can’t change later.").settingsFont(.footer).foregroundStyle(SettingsTokens.secondaryText)
                }
            }
            .frame(maxHeight: 460)
        } buttons: {
            Spacer(minLength: 0)
            SettingsButton("Cancel") { model.closeSheet() }
            SettingsButton("Create Key") { Task { await model.make() } }.disabled(!model.canMakeDraft).keyboardShortcut(.defaultAction)
        }
    }
}

private struct ShownKeySheet: View {
    let model: KeysModel
    @State private var copied = false

    /// How long a copied key stays on the clipboard before it is taken off, if nothing else was copied since.
    private static let clipboardLife: Duration = .seconds(60)

    /// Puts the key on the clipboard marked concealed and transient, so clipboard managers do not keep it, and takes it off
    /// again after a minute unless something else has been copied since.
    private static func copy(_ secret: String) {
        let pasteboard = NSPasteboard.general
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        pasteboard.declareTypes([.string, concealed, transient], owner: nil)
        pasteboard.setString(secret, forType: .string)
        pasteboard.setData(Data(), forType: concealed)
        pasteboard.setData(Data(), forType: transient)
        let count = pasteboard.changeCount
        Task {
            try? await Task.sleep(for: clipboardLife)
            if pasteboard.changeCount == count { pasteboard.clearContents() }
        }
    }

    var body: some View {
        SettingsSheet(title: Text("Copy the Key Now"), line: Text("It is shown only once. Keep it where the script can read it.")) {
            if let created = model.created {
                SettingsSheetField(label: LocalizedStringKey(created.label)) {
                    Text(verbatim: created.secret)
                        .settingsFont(.mono)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: SettingsTokens.Metric.controlHeight, alignment: .leading)
                        .background(SettingsTokens.field, in: .rect(cornerRadius: SettingsTokens.Metric.controlRadius))
                        .overlay { RoundedRectangle(cornerRadius: SettingsTokens.Metric.controlRadius).strokeBorder(SettingsTokens.hairline) }
                }
            }
        } buttons: {
            Spacer(minLength: 0)
            SettingsButton(copied ? "Copied" : "Copy") {
                guard let secret = model.created?.secret else { return }
                Self.copy(secret)
                copied = true
            }
            SettingsButton("Done") { model.closeSheet() }.keyboardShortcut(.defaultAction)
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
            Spacer(minLength: 0)
            SettingsButton("Cancel") { model.closeSheet() }
            SettingsButton("Rename") { Task { await model.rename() } }.disabled(!model.canRename).keyboardShortcut(.defaultAction)
        }
    }
}
