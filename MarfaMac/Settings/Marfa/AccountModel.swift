import Foundation
import Marfa
import Observation

/// The Account page: the owner's profile as the server holds it, the password, the passkeys and the browsers signed in.
/// The sign-ins need `sign_ins.manage`, which every sign-in asks for; where the owner did not approve it, Change Password
/// asks again for everything the sign-in lacks. A refused write keeps what was typed.
@Observable @MainActor final class AccountModel: OwnerDraftHolding {
    enum Sheet: Equatable {
        case password
        case renamePasskey(String)
    }

    /// A removal waiting on the owner's answer.
    struct Question: Identifiable, Equatable {
        enum Action: Equatable {
            case removePasskey(String)
            case endBrowser(String)
        }

        let id = UUID()
        let action: Action
        let title: String
        let message: String
        let confirm: String
    }

    static let passwordLength = 8...128

    private let context: OwnerContext

    private(set) var profile: OwnerProfile?
    private(set) var passkeys: [OwnerPasskey] = []
    private(set) var browsers: [BrowserSignIn] = []
    /// Why the page can't be shown at all.
    private let loader = OwnerLoader()
    var failure: OwnerFailure? { loader.failure }
    /// Why the passkeys and browsers couldn't be read, where the profile could.
    private let signInsRead = OwnerLoader.ReadStatus()
    var listsFailure: OwnerFailure? { signInsRead.failure }
    var hasLoaded: Bool { loader.hasLoaded }
    /// One line under a passkey or a browser whose change was refused, by its id.
    private(set) var rowErrors: [String: OwnerFailure] = [:]
    /// One line under the page's rows, such as why Add Passkey… did not open.
    private(set) var note: String?
    var sheet: Sheet?
    var question: Question?

    var currentPassword = ""
    var newPassword = ""
    private(set) var currentPasswordError: String?
    private(set) var newPasswordError: String?
    private(set) var passwordLine: String?
    private(set) var isChangingPassword = false
    private(set) var passwordChanged = false
    var renameDraft = ""
    private(set) var renameError: String?

    init(context: OwnerContext) {
        self.context = context
    }

    var canManageSignIns: Bool { context.grants().contains(.signInsManage) }

    // MARK: Reading

    func load() async {
        await loader.load(in: context, primary: { () throws(OwnerFailure) in
            profile = try await context.calls.profile()
        }, secondary: [
            .required(signInsRead) { [self] () throws(OwnerFailure) in
                guard canManageSignIns else {
                    passkeys = []
                    browsers = []
                    return
                }
                passkeys = try await context.calls.passkeys()
                browsers = try await context.calls.browserSignIns()
            },
        ])
    }

    // MARK: Password

    /// Requests access for the sign-in controls and shows their missing permission after an insufficient approval.
    @discardableResult func allowSignIns() async -> Bool {
        note = nil
        let outcome = await context.allowMore([.signInsManage])
        if outcome != .allowed, outcome != .cancelled { note = OwnerWording.permissionLine(InstancePermission.signInsManage.rawValue) }
        return outcome == .allowed
    }

    /// Opens the password sheet once the sign-in holds `sign_ins.manage`.
    func beginChangePassword() async {
        note = nil
        if !canManageSignIns {
            guard await allowSignIns() else { return }
            await load()
        }
        clearPasswordInput()
        sheet = .password
    }

    var isNewPasswordLongEnough: Bool { Self.passwordLength.contains(newPassword.count) }

    var canChangePassword: Bool { !currentPassword.isEmpty && isNewPasswordLongEnough && !isChangingPassword }

    func changePassword() async {
        guard canChangePassword else { return }
        isChangingPassword = true
        defer { isChangingPassword = false }
        currentPasswordError = nil
        newPasswordError = nil
        passwordLine = nil
        do {
            switch try await context.calls.changePassword(from: currentPassword, to: newPassword) {
            case .changed:
                clearPasswordInput()
                passwordChanged = true
                browsers = []
                await load()
            case .currentWrong:
                currentPasswordError = String(localized: "That isn’t your current password.")
            case .newRefused(let reason):
                newPasswordError = reason
            case .tooManyAttempts(let seconds):
                let wait = seconds.map { Duration.seconds($0).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 1)) }
                currentPasswordError = wait.map { String(localized: "Too many tries. Try again in \($0).") } ?? String(localized: "Too many tries. Try again later.")
            }
        } catch {
            passwordLine = OwnerWording.line(error)
            await context.learn(from: error)
        }
    }

    /// Closes the sheet. What was typed is a password, so it is never kept.
    func closePasswordSheet() {
        guard !isChangingPassword else { return }
        clearPasswordInput()
        passwordChanged = false
        sheet = nil
    }

    private func clearPasswordInput() {
        currentPassword = ""
        newPassword = ""
        currentPasswordError = nil
        newPasswordError = nil
        passwordLine = nil
    }

    // MARK: Passkeys

    /// The address of the server's own page where the owner adds a passkey, or nil with the page's note saying why not.
    func passkeyAddress() async -> URL? {
        note = nil
        do {
            return try await context.calls.passkeyAddAddress()
        } catch {
            note = OwnerWording.line(error)
            await context.learn(from: error)
            return nil
        }
    }

    func beginRename(_ passkey: OwnerPasskey) {
        renameDraft = passkey.name ?? ""
        renameError = nil
        sheet = .renamePasskey(passkey.id)
    }

    var canRename: Bool { !renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func rename() async {
        guard case .renamePasskey(let id)? = sheet, canRename else { return }
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await context.calls.renamePasskey(id, to: name)
            if let index = passkeys.firstIndex(where: { $0.id == id }) { passkeys[index].name = name }
            sheet = nil
        } catch {
            renameError = OwnerWording.line(error)
            await context.learn(from: error)
            if error == .notFound { await load() }
        }
    }

    func closeRename() {
        sheet = nil
        renameError = nil
    }

    func askToRemove(_ passkey: OwnerPasskey) {
        let name = passkey.name ?? String(localized: "Passkey")
        question = Question(
            action: .removePasskey(passkey.id), title: String(localized: "Remove “\(name)”?"),
            message: String(localized: "It can’t sign in again. Browsers already signed in keep working."), confirm: String(localized: "Remove"))
    }

    func askToEnd(_ browser: BrowserSignIn) {
        question = Question(
            action: .endBrowser(browser.id), title: String(localized: "Sign out “\(browser.name)”?"),
            message: String(localized: "It must sign in again with your password or a passkey. Apps and keys keep working."),
            confirm: String(localized: "Sign Out"))
    }

    func cancelQuestion() { question = nil }

    func confirm(_ asked: Question) async {
        question = nil
        switch asked.action {
        case .removePasskey(let id):
            guard let passkey = passkeys.first(where: { $0.id == id }) else { return }
            await remove(passkey)
        case .endBrowser(let id):
            guard let browser = browsers.first(where: { $0.id == id }) else { return }
            await end(browser)
        }
    }

    private func remove(_ passkey: OwnerPasskey) async {
        rowErrors[passkey.id] = nil
        do {
            try await context.calls.removePasskey(passkey.id)
            passkeys.removeAll { $0.id == passkey.id }
        } catch {
            if error == .notFound {
                passkeys.removeAll { $0.id == passkey.id }
            } else {
                rowErrors[passkey.id] = error
            }
            await context.learn(from: error)
        }
    }

    // MARK: Browsers

    private func end(_ browser: BrowserSignIn) async {
        rowErrors[browser.id] = nil
        do {
            try await context.calls.endSignIn(browser.id)
            browsers.removeAll { $0.id == browser.id }
        } catch {
            if error == .notFound {
                browsers.removeAll { $0.id == browser.id }
            } else {
                rowErrors[browser.id] = error
            }
            await context.learn(from: error)
        }
    }

    // MARK: Closing

    /// The name typed for a passkey, which the app gives back when Settings closes. A password is dropped and never
    /// handed over.
    func takeDrafts() -> [OwnerDraft] {
        switch sheet {
        case .password?:
            closePasswordSheet()
            return []
        case .renamePasskey(let id)?:
            let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let held = passkeys.first { $0.id == id }?.name ?? ""
            closeRename()
            guard !name.isEmpty, name != held else { return [] }
            return [.typed(title: String(localized: "Passkey Not Renamed"), text: name)]
        case nil:
            return []
        }
    }
}
