import AppKit
import Marfa
import SwiftUI
import UniformTypeIdentifiers

struct AccountPage: View {
    let host: any MarfaSettingsHost
    @State private var model: AccountModel
    @State private var choosesPicture = false
    @State private var jobCount: Int?
    @State private var monitoringCount: Int?

    init(host: any MarfaSettingsHost) {
        self.host = host
        _model = State(initialValue: AccountModel(context: OwnerContext(host: host)))
    }

    var body: some View {
        Group {
            if model.failure == .unreachable {
                SettingsStandingState {
                    AccountHeader(host: host)
                } state: {
                    OwnerFailureState(page: .account, failure: .unreachable, host: host) { Task { await model.load() } }
                }
            } else {
                account
            }
        }
        .task(id: host.grants) {
            async let profile: Void = model.load()
            if host.grants.contains(.instanceRead) {
                jobCount = try? await host.ownerCalls.housekeepingJobs().count
            } else {
                jobCount = nil
            }
            if host.grants.contains(.configManage) {
                let snapshot = try? await host.instanceCalls.storedSettings()
                monitoringCount = snapshot?.enabledMonitoringCount
            } else {
                monitoringCount = nil
            }
            await profile
        }
        .onAppear { host.ownerDrafts.register(model) }
        .settingsSheet(presenting: model.sheet != nil, dismiss: { model.closePasswordSheet() }) { AccountSheet(model: model) }
        .fileImporter(isPresented: $choosesPicture, allowedContentTypes: [.image]) { chosen in
            switch chosen {
            case .success(let file): Task { await model.setPicture(from: file) }
            case .failure: model.pictureNotChosen()
            }
        }
    }

    private var account: some View {
        SettingsPageColumn {
            AccountHeader(host: host)
            problems
            if !model.canManageSignIns {
                SettingsSection("Permissions") {
                    SettingsProblemRow(
                        title: Text("This App Can’t Manage Sign-Ins"), line: Text("Your password, passkeys and browsers need this permission."),
                        symbol: "lock", actions: [SettingsProblemAction("Allow More") { Task { await model.allowSignIns() } }]
                    ).disabled(host.isAllowingMore)
                }
            }
            if let profile = model.profile, model.failure == nil {
                profileRows(profile)
            } else if let failure = model.failure {
                OwnerProblem(title: "Couldn’t Read the Profile", failure: failure, page: .account, host: host) { Task { await model.load() } }
            } else {
                OwnerLoading()
            }
            security
            AccountMarfaSection(host: host)
            SettingsSection("Server") {
                link(.network, value: host.instanceSettings.loaded?.signInAddress.map(AddressesModel.display))
                link(.fileStorage, value: storageSize)
            }
            SettingsSection("Advanced") {
                link(.monitoring, value: monitoringCount.map { String(localized: "\($0) of 3 on") })
                link(.limits)
                link(
                    .housekeeping,
                    value: host.grants.contains(.instanceRead) ? jobCount.map { $0 == 1 ? String(localized: "1 job") : String(localized: "\($0) jobs") } : nil)
            }
        }
    }

    private var storageSize: String? {
        guard host.grants.contains(.instanceRead), host.overview.metricsFailure == nil, let metrics = host.overview.metrics,
            let database = metrics.databaseBytes
        else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(database) + Int64(metrics.fileBytes), countStyle: .file)
    }

    @ViewBuilder private var problems: some View {
        let overview = host.overview
        if host.grants.contains(.instanceRead) {
            if let failure = overview.failure {
                OwnerProblem(title: "Couldn’t Check for Problems", failure: failure, page: .account, host: host) { Task { await overview.load() } }
            } else if !overview.concerns.isEmpty {
                SettingsSection("Problems") {
                    ForEach(overview.concerns) { concern in
                        let page = concern.destination
                        SettingsProblemRow(
                            title: Text(verbatim: concern.shownTitle), line: concern.shownLine.map { Text(verbatim: $0) },
                            actions: [
                                SettingsProblemAction(verbatim: page == .keys ? String(localized: "Show Keys") : String(localized: "Show \(page.title)")) {
                                    host.show(page)
                                }
                            ])
                    }
                }
            }
        }
    }

    private func profileRows(_ profile: OwnerProfile) -> some View {
        SettingsSection("Profile") {
            SettingsRow("Picture", error: model.pictureError) {
                if profile.pictureIsReadable {
                    ProfilePictureMark(picture: model.picture, name: profile.name ?? profile.username)
                }
                if profile.pictureIsReadable && model.changeable.contains(.avatar) {
                    SettingsButton("Change…") { choosesPicture = true }
                        .disabled(model.isSendingPicture)
                        .accessibilityIdentifier("AccountChangePicture")
                } else {
                    profileLock
                }
            }
            SettingsRow("Name", error: model.nameError) {
                if profile.name != nil && model.changeable.contains(.name) {
                    SettingsField(
                        title: "Name", text: $model.nameDraft, isError: model.nameError != nil,
                        onSubmit: { Task { await model.saveName() } }, onEndEditing: { Task { await model.saveName() } }
                    )
                    .disabled(model.isSavingName).accessibilityIdentifier("AccountName")
                } else {
                    if let name = profile.name { SettingsValue(verbatim: name) }
                    profileLock
                }
            }
            profileField(.username, readable: profile.username != nil, value: profile.username)
            profileField(.email, readable: profile.emailIsReadable, value: profile.email)
        }
    }

    private var profileLock: some View {
        Button {
            Task { await model.allowProfileChanges() }
        } label: {
            Label("Not Allowed", systemImage: "lock").labelStyle(.iconOnly)
        }.buttonStyle(.plain).disabled(host.isAllowingMore)
    }

    private func profileField(_ field: ProfileContactField, readable: Bool, value: String?) -> some View {
        SettingsRow(verbatim: field.title, error: model.contactErrors[field]) {
            if readable && model.changeable.contains(field.scope) {
                SettingsField(
                    title: LocalizedStringKey(field.title),
                    text: Binding {
                        model.contactDrafts[field] ?? value ?? ""
                    } set: {
                        model.contactDrafts[field] = $0
                    },
                    isError: model.contactErrors[field] != nil, onSubmit: { Task { await model.saveContact(field) } },
                    onEndEditing: { Task { await model.saveContact(field) } }
                )
                .disabled(model.savingContacts.contains(field))
            } else {
                if readable { SettingsValue(verbatim: value ?? String(localized: "Not Set")) }
                profileLock
            }
        }
    }

    private var security: some View {
        SettingsSection(name: Text("Security"), footer: model.note.map { Text(verbatim: $0) }) {
            if model.canManageSignIns {
                SettingsRow("Password", line: "Changing it signs out every browser.") {
                    SettingsButton("Change…") { Task { await model.beginChangePassword() } }.accessibilityIdentifier("AccountChangePassword")
                }
            } else {
                SettingsLinkRow(verbatim: String(localized: "Password"), lock: String(localized: "Not allowed")) {
                    Task { await model.beginChangePassword() }
                }.accessibilityIdentifier("AccountChangePassword")
            }
            let known = model.hasLoaded && model.failure == nil && model.listsFailure == nil
            link(.passkeys, value: known ? model.passkeys.count.formatted() : nil)
            link(.browsers, value: known ? model.browsers.count.formatted() : nil)
        }
    }

    private func link(_ page: MarfaSettingsPage, value: String? = nil) -> some View {
        let locked = page.missingPermission(in: host.grants) != nil
        return SettingsLinkRow(
            verbatim: page.title, lead: .tile(page.symbol, page.tone),
            value: locked ? nil : value, valueGlyph: page == .network ? .link : nil,
            lock: locked ? String(localized: "Not allowed") : nil
        ) { host.show(page) }
            .accessibilityIdentifier("SettingsLink-\(page.rawValue)")
    }
}

/// A configured Marfa can still be signed out when the copy or server is unavailable.
struct AccountHeader: View {
    let host: any MarfaSettingsHost

    var body: some View {
        if let address = host.serverAddress {
            SettingsPageHeader(name: host.serverName, address: AddressesModel.display(address)) {
                Button("Sign Out", action: host.requestSignOut)
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.regular)
                    .accessibilityIdentifier("AccountSignOut")
            }
        }
    }
}

/// The owner's picture in a circle, or the first letters of their name where there is none.
private struct ProfilePictureMark: View {
    let picture: Data?
    let name: String?

    private var initials: String {
        String((name ?? "").split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    var body: some View {
        Group {
            if let picture, let image = NSImage(data: picture) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Circle().fill(SettingsTokens.Tone.purple.color).overlay {
                    if initials.isEmpty {
                        SettingsTileGlyph(symbol: "person.fill", tileSize: SettingsTokens.Metric.tile)
                    } else {
                        Text(verbatim: initials).settingsFont(.small)
                    }
                }
                .foregroundStyle(SettingsTokens.tileForeground)
            }
        }
        .frame(width: SettingsTokens.Metric.tile, height: SettingsTokens.Metric.tile)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// The Account page's sheets, which the window shows in its middle: Change Password and Rename Passkey.
struct AccountSheet: View {
    @Bindable var model: AccountModel

    var body: some View {
        switch model.sheet {
        case .password?: PasswordSheet(model: model)
        case .renamePasskey?: RenamePasskeySheet(model: model)
        case nil: EmptyView()
        }
    }
}

private struct PasswordSheet: View {
    @Bindable var model: AccountModel

    var body: some View {
        if model.passwordChanged {
            SettingsSheet(
                title: Text("Password Changed"), line: Text("Every browser sign-in has ended. Apps and keys keep working.")
            ) {
                EmptyView()
            } buttons: {
                SettingsButton("Done", role: .confirm) { model.closePasswordSheet() }
            }
        } else {
            SettingsSheet(
                title: Text("Change Password"), line: Text("Every browser signs out. Apps and keys keep working.")
            ) {
                VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFieldGap) {
                    SettingsSheetField(label: "Current Password", error: model.currentPasswordError) {
                        SettingsField(
                            title: "Current Password", text: $model.currentPassword, isError: model.currentPasswordError != nil,
                            isSecure: true, width: nil)
                    }
                    SettingsSheetField(label: "New Password", error: model.newPasswordError ?? model.passwordLine) {
                        SettingsField(
                            title: "New Password", text: $model.newPassword, isError: model.newPasswordError != nil, isSecure: true,
                            width: nil, onSubmit: { Task { await model.changePassword() } })
                    }
                    SettingsSheetStatus(text: Text("At least 8 characters."), isMet: model.isNewPasswordLongEnough)
                }
            } buttons: {
                SettingsButton("Cancel") { model.closePasswordSheet() }
                SettingsButton("Change Password", role: .confirm) { Task { await model.changePassword() } }
                    .disabled(!model.canChangePassword)
            }
        }
    }
}

private struct RenamePasskeySheet: View {
    @Bindable var model: AccountModel

    var body: some View {
        SettingsSheet(title: Text("Rename Passkey")) {
            SettingsSheetField(label: "Name", error: model.renameError) {
                SettingsField(
                    title: "Name", text: $model.renameDraft, isError: model.renameError != nil, width: nil,
                    onSubmit: { Task { await model.rename() } })
            }
        } buttons: {
            SettingsButton("Cancel") { model.closeRename() }
            SettingsButton("Rename", role: .confirm) { Task { await model.rename() } }.disabled(!model.canRename)
        }
    }
}
