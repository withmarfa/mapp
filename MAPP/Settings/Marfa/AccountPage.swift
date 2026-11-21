import SwiftUI

/// The Account page: the owner's username and email as the server holds them, Change Password…, the passkeys with Add a
/// Passkey…, and the browsers signed in, each with Sign Out.
struct AccountPage: View {
    let host: any MarfaSettingsHost
    @State private var model: AccountModel
    @Environment(\.openURL) private var openURL

    init(host: any MarfaSettingsHost) {
        self.host = host
        _model = State(initialValue: AccountModel(context: OwnerContext(host: host)))
    }

    var body: some View {
        content
            .task(id: host.serverAddress) { await model.load() }
            .onAppear { host.ownerDrafts.register(model) }
            .settingsSheet(presenting: model.sheet != nil, dismiss: dismissSheet) { AccountSheet(model: model) }
            .alert(
                model.question?.title ?? "", isPresented: Binding { model.question != nil } set: { if !$0 { model.cancelQuestion() } },
                presenting: model.question
            ) { asked in
                Button("Cancel", role: .cancel) {}
                Button(asked.confirm, role: .destructive) { Task { await model.confirm(asked) } }
            } message: { asked in
                Text(verbatim: asked.message)
            }
            .accessibilityIdentifier("AccountPage")
    }

    private static var unnamed: String { String(localized: "Passkey") }

    private func dismissSheet() {
        switch model.sheet {
        case .password?: model.closePasswordSheet()
        case .renamePasskey?: model.closeRename()
        case nil: break
        }
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            OwnerFailureState(page: .account, failure: failure, host: host) { Task { await model.load() } }
        } else if !model.hasLoaded {
            OwnerLoading()
        } else {
            SettingsPageColumn {
                if let profile = model.profile, !profile.isEmpty { profileSection(profile) }
                passwordSection
                if model.canManageSignIns {
                    if let failure = model.listsFailure {
                        OwnerProblem(title: "Couldn’t Read the Sign-Ins", failure: failure, page: .account, host: host, retry: { Task { await model.load() } })
                    } else {
                        passkeysSection
                        browsersSection
                    }
                } else {
                    SettingsSection("Passkeys and Browsers") {
                        SettingsProblemRow(
                            title: Text("Sign-Ins"), line: Text("MAPP isn’t allowed to list and end your sign-ins."), symbol: "lock", tone: .gray,
                            actions: [
                                SettingsProblemAction(host.isAllowingMore ? "Waiting…" : "Allow More…") {
                                    Task { await model.allowSignIns(); await model.load() }
                                }
                            ]
                        )
                        .disabled(host.isAllowingMore)
                    }
                }
            }
        }
    }

    private func profileSection(_ profile: OwnerProfile) -> some View {
        SettingsSection("Profile") {
            if let username = profile.username {
                SettingsRow("Username", line: "You sign in with it.") { SettingsValue(verbatim: username) }
            }
            if profile.emailIsReadable {
                SettingsRow("Email", line: "Optional. Not used to sign in.") {
                    if let email = profile.email { SettingsValue(verbatim: email) } else { SettingsValue("Not Set") }
                }
            }
        }
    }

    private var passwordSection: some View {
        SettingsSection(name: Text("Password"), footer: model.note.map { Text(verbatim: $0) }) {
            SettingsRow("Password", line: "Changing it signs out every browser.") {
                SettingsButton("Change…") { Task { await model.beginChangePassword() } }
                    .accessibilityIdentifier("AccountChangePassword")
            }
        }
    }

    private var passkeysSection: some View {
        SettingsSection("Passkeys") {
            ForEach(model.passkeys) { passkey in
                SettingsRow(
                    verbatim: passkey.name ?? Self.unnamed, line: Self.line(added: passkey.added, used: passkey.lastUsed),
                    error: model.rowErrors[passkey.id].map { OwnerWording.line($0, on: .account) }, lead: .symbol("touchid")
                ) {
                    SettingsMoreMenu {
                        Button("Rename…") { model.beginRename(passkey) }
                        Button("Remove…", role: .destructive) { model.askToRemove(passkey) }
                    }
                }
            }
            SettingsAddRow("Add a Passkey…") {
                Task { if let address = await model.passkeyAddress() { openURL(address) } }
            }
        }
    }

    private var browsersSection: some View {
        SettingsSection("Browsers", line: "Signed in with your password or a passkey.") {
            if model.browsers.isEmpty {
                SettingsEmptyCard(symbol: "safari", title: Text("No Browsers"), line: Text("No browsers are signed in."))
            }
            ForEach(model.browsers) { browser in
                SettingsRow(
                    verbatim: browser.name, line: Self.line(added: browser.added, used: browser.lastUsed, signedIn: true),
                    error: model.rowErrors[browser.id].map { OwnerWording.line($0, on: .account) }, lead: .symbol("safari")
                ) {
                    SettingsButton("Sign Out") { model.askToEnd(browser) }
                }
            }
        }
    }

    /// "Added 3 October. Used today."
    static func line(added: Date?, used: Date?, signedIn: Bool = false, now: Date = .now, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if let added {
            let day = OwnerWording.day(added, now: now, calendar: calendar)
            parts.append(signedIn ? String(localized: "Signed in \(day).") : String(localized: "Added \(day)."))
        }
        parts.append(OwnerWording.used(used, now: now, calendar: calendar) + ".")
        return parts.joined(separator: " ")
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
                Spacer(minLength: 0)
                SettingsButton("Done") { model.closePasswordSheet() }.keyboardShortcut(.defaultAction)
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
                Spacer(minLength: 0)
                SettingsButton("Cancel") { model.closePasswordSheet() }
                SettingsButton("Change Password") { Task { await model.changePassword() } }
                    .disabled(!model.canChangePassword)
                    .keyboardShortcut(.defaultAction)
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
            Spacer(minLength: 0)
            SettingsButton("Cancel") { model.closeRename() }
            SettingsButton("Rename") { Task { await model.rename() } }.disabled(!model.canRename).keyboardShortcut(.defaultAction)
        }
    }
}
