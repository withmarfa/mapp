import Marfa
import SwiftUI

private func expiryTitle(inDays days: Int) -> String {
    switch days {
    case 1: String(localized: "Tomorrow")
    case 365: String(localized: "In 1 Year")
    default: String(localized: "In \(days) Days")
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

    @State private var isEditingAccess: Bool
    @State private var showsSourceOptions = false

    init(model: KeysModel) {
        self.model = model
        _isEditingAccess = State(initialValue: !model.draft.exceptions.isEmpty || !model.draft.permissions.isEmpty || model.isChoosingPermissions)
    }

    private static let expiries: [KeysModel.Expiry] = [.days(7), .days(30), .days(90), .days(365), .never]

    private func title(_ expiry: KeysModel.Expiry) -> String {
        switch expiry {
        case .never: String(localized: "Never")
        case .days(let days): expiryTitle(inDays: days)
        }
    }

    private var exceptionPatterns: [String] { model.draft.exceptions.keys.sorted() }

    private var addable: [(id: String, name: String)] {
        model.typeNames.filter { model.draft.exceptions[$0.key] == nil }.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    private var unavailablePermissions: Set<String> {
        model.draft.permissions.subtracting(model.givablePermissions)
    }

    private var permissionSummary: String {
        let operations = model.draft.permissions.sorted().map { permission in
            switch InstancePermission(rawValue: permission) {
            case .itemsPurge: String(localized: "permanently delete trashed items")
            case .instanceMaintain: String(localized: "update and maintain the server")
            default: OwnerWording.title(of: permission).localizedLowercase
            }
        }
        guard !operations.isEmpty else { return String(localized: "None") }
        let list = operations.formatted(.list(type: .and))
        let sentence = String(list.prefix(1)).localizedUppercase + list.dropFirst()
        return String(localized: "\(sentence).")
    }

    var body: some View {
        Group {
            if model.isChoosingPermissions {
                permissionsPage
            } else {
                fieldsPage
            }
        }
        .onChange(of: model.sourceError, initial: true) {
            if model.sourceError != nil { showsSourceOptions = true }
        }
    }

    private var fieldsPage: some View {
        SettingsSheet(title: Text("New Key"), isWide: true) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFormGap) {
                SettingsSheetField(label: "Name", error: model.draftError) {
                    SettingsField(title: "Name", text: Binding { model.draft.name } set: { name in
                        if model.draft.source == KeysModel.source(from: model.draft.name) { model.draft.source = KeysModel.source(from: name) }
                        model.draft.name = name
                        if model.draft.source.isEmpty, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showsSourceOptions = true
                        }
                    }, isError: model.draftError != nil, width: nil)
                }
                if showsSourceOptions { sourceOptions }
                accessSection
                SettingsSection(name: nil) {
                    SettingsRow("Expires") {
                        SettingsPopUp(title: "Expires", selection: $model.draft.expires) {
                            ForEach(Self.expiries, id: \.self) { Text(verbatim: title($0)).tag($0) }
                        }
                    }
                }
                if isEditingAccess || !model.draft.permissions.isEmpty { permissionSection }
            }
            .environment(\.settingsCompactControls, true)
            .environment(\.settingsUsesSheetControls, false)
        } leading: {
            SettingsButton(showsSourceOptions ? "Hide Options" : "Source and Destination", small: true) {
                showsSourceOptions.toggle()
            }
            .disabled(model.sourceError != nil)
            .help("Set the source and where new items go.")
        } buttons: {
            SettingsButton("Cancel") { model.closeSheet() }
            SettingsButton("Create Key", role: .confirm) {
                Task {
                    guard unavailablePermissions.isEmpty else { return }
                    await model.make()
                }
            }
            .disabled(!model.canMakeDraft || !unavailablePermissions.isEmpty)
        }
    }

    private var accessSection: some View {
        SettingsSection("Access") {
            SettingsButton(isEditingAccess ? "Finish Customizing" : "Customize Access", small: true) {
                isEditingAccess.toggle()
            }
            .help("Choose type exceptions and owner permissions.")
        } content: {
            SettingsRow("Every type", lead: .symbol("tray.full")) {
                SettingsPopUp(title: "Every type", selection: $model.draft.everyType) { accessLevels }
            }
            ForEach(exceptionPatterns, id: \.self) { pattern in
                let name = AccessScopes.title(of: pattern, names: model.typeNames)
                if let level = model.draft.exceptions[pattern] {
                    SettingsRow(verbatim: name, lead: .symbol("tray")) {
                        if isEditingAccess {
                            HStack(spacing: SettingsTokens.Metric.buttonGap) {
                                SettingsPopUp(verbatim: name, selection: Binding { model.draft.exceptions[pattern] ?? level } set: {
                                    model.draft.exceptions[pattern] = $0
                                }) {
                                    accessLevels
                                }
                                SettingsMoreMenu { Button("Remove", role: .destructive) { model.draft.exceptions[pattern] = nil } }
                                    .accessibilityLabel(Text("More actions for \(name)"))
                            }
                        } else {
                            SettingsValue(verbatim: level.title)
                        }
                    }
                }
            }
            if isEditingAccess, !addable.isEmpty {
                SettingsAddMenu("Add an Exception…") {
                    ForEach(addable, id: \.id) { type in
                        Button(type.name) { model.draft.exceptions[type.id] = .read }
                    }
                }
            }
        }
    }

    private var accessLevels: some View {
        ForEach(AccessLevel.allCases.reversed(), id: \.self) { level in
            Text(verbatim: level.title).tag(level)
        }
    }

    private var permissionSection: some View {
        SettingsSection("Permissions") {
            if model.givablePermissions.isEmpty && model.draft.permissions.isEmpty {
                SettingsRow("Owner’s permissions", line: "This sign-in can’t grant owner permissions.", lead: .symbol("lock"), look: .off)
            } else {
                SettingsRow(title: Text("Owner’s permissions"), line: Text(verbatim: permissionSummary), lines: nil) {
                    if isEditingAccess, !model.givablePermissions.isEmpty {
                        SettingsButton("Choose…", small: true) { model.isChoosingPermissions = true }
                    }
                }
            }
            if !unavailablePermissions.isEmpty {
                let names = unavailablePermissions.sorted().map { OwnerWording.title(of: $0) }.formatted(.list(type: .and))
                SettingsRow(title: Text("Permissions no longer available"), line: Text(verbatim: names), lines: nil) {
                    SettingsButton("Remove") { model.draft.permissions.subtract(unavailablePermissions) }
                }
            }
        }
    }

    private var sourceOptions: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFormGap) {
            SettingsSheetField(label: "Source", error: model.sourceError) {
                SettingsField(title: "Source", text: $model.draft.source, isError: model.sourceError != nil, isMonospaced: true, width: nil)
            }
            SettingsSection(name: nil, footer: Text("The source is stamped on what the key writes and can’t change later.")) {
                SettingsRow("New items go to") {
                    SettingsPopUp(title: "New items go to", selection: $model.draft.tier) {
                        ForEach(KeyTier.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                    }
                }
            }
        }
    }

    /// The owner's permissions, a page of the sheet: one switch each, and Back to the fields with what was chosen kept.
    private var permissionsPage: some View {
        SettingsSheet(
            title: Text("Permissions"), line: Text("The owner’s permissions. Most keys need none."), isWide: true
        ) {
            SettingsSection(name: nil) {
                ForEach(model.givablePermissions, id: \.self) { permission in
                    SettingsRow(verbatim: OwnerWording.title(of: permission), size: .compact) {
                        SettingsToggle(title: "Allowed", isOn: Binding { model.draft.permissions.contains(permission) } set: { on in
                            if on {
                                guard model.givablePermissions.contains(permission) else { return }
                                model.draft.permissions.insert(permission)
                            } else {
                                model.draft.permissions.remove(permission)
                            }
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
                SettingsSheetField(verbatim: created.label) {
                    SettingsReadOnlyValue(text: created.secret, isSelectable: false)
                        .accessibilityHidden(true)
                }
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
        case .days(let days): expiryTitle(inDays: days)
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
