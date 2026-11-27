import SwiftUI

/// The Network page's sheets, which the window shows in its middle: adding an address or a website, and moving the
/// sign-in address, which says what changes first.
struct AddressSheet: View {
    @Bindable var model: AddressesModel
    let serverName: String
    /// A refused check can return only an error, without a plan that identifies the input.
    @State private var checkedInput: String?

    private var title: Text {
        switch model.sheet {
        case .addAddress?: Text("Add an Address")
        case .addWebsite?: Text("Add a Website")
        case .changeSignIn?, nil: Text("Change Sign-In Address")
        }
    }

    private var line: Text? {
        switch model.sheet {
        case .addAddress?: Text("\(serverName) answers on it too.")
        case .addWebsite?: Text("Pages on it may call \(serverName).")
        case .changeSignIn?, nil:
            if let address = model.signInAddress, !address.isEmpty { Text("Now \(AddressesModel.display(address)).") } else { nil }
        }
    }

    private var confirmTitle: LocalizedStringKey {
        switch model.sheet {
        case .addAddress?: "Add Address"
        case .addWebsite?: "Add Website"
        case .changeSignIn?, nil: "Change Address"
        }
    }

    var body: some View {
        let changingSignIn = model.sheet == .changeSignIn
        let label: LocalizedStringKey = changingSignIn ? "New address" : "Address"
        let error = changingSignIn && model.currentPlan == nil && checkedInput != model.input ? nil : model.inputError
        SettingsSheet(title: title, line: line, isWide: changingSignIn) {
            VStack(alignment: .leading, spacing: changingSignIn ? SettingsTokens.Metric.sheetGap : SettingsTokens.Metric.sheetFieldGap) {
                SettingsSheetField(label: label, error: error) {
                    SettingsField(
                        title: label, text: $model.input, prompt: "https://", isError: error != nil, width: nil,
                        onSubmit: { Task { await model.confirm() } })
                    .disabled(changingSignIn && model.isWriting)
                }
                if changingSignIn, let plan = model.currentPlan, plan.requiresConfirmation || !plan.consequences.isEmpty {
                    SettingsSection("What Happens") {
                        ForEach(Self.happenings(plan.consequences)) { happening in
                            SettingsRow(verbatim: happening.title, line: happening.line, lead: .symbol(happening.symbol), lines: nil)
                        }
                    }
                }
                if changingSignIn, model.currentPlan != nil, let notice = model.approvalNotice {
                    SettingsSheetStatus(text: Text(verbatim: notice), isMet: false)
                } else if let status {
                    SettingsSheetStatus(text: Text(verbatim: status))
                } else if changingSignIn, error == nil, let plan = model.currentPlan,
                    plan.requiresConfirmation, plan.reach == .notChecked
                {
                    SettingsSheetStatus(text: Text("Sign in again to check the new address."), isMet: false)
                }
            }
            .task(id: model.input) { [input = model.input] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, input == model.input else { return }
                if changingSignIn { checkedInput = input }
                await model.check()
            }
        } buttons: {
            SettingsButton("Cancel") { model.close() }
            SettingsButton(confirmTitle, role: .confirm) { Task { await model.confirm() } }
                .disabled(model.sheet == .addWebsite ? !(model.inputError == nil && AddressesModel.origin(from: model.input) != nil) : !model.canConfirm)
        }
    }

    /// What the server's check found, where it found the address fine.
    private var status: String? {
        guard model.inputError == nil, AddressesModel.origin(from: model.input) != nil else { return nil }
        switch model.sheet {
        case .changeSignIn?: return model.currentPlan?.reach == .answers ? String(localized: "The new address works.") : nil
        case .addAddress?: return model.currentPlan == nil ? nil : String(localized: "The server accepts this address.")
        case .addWebsite?: return String(localized: "This is a website address.")
        case nil: return nil
        }
    }

    /// One row of What Happens.
    struct Happening: Identifiable {
        let id: String
        let title: String
        let line: String?
        let symbol: String
    }

    /// What moving the sign-in address does, in the app's words: browsers and apps signing out as one row, passkeys, any
    /// consequence the app has no words for in the server's, and keys, which keep working whatever the server counts.
    static func happenings(_ consequences: [AddressPlan.Consequence]) -> [Happening] {
        let codes = Set(consequences.map(\.code))
        var rows: [Happening] = []
        let signOut: String? =
            switch (codes.contains("browser_sessions_end"), codes.contains("apps_sign_in_again")) {
            case (true, true): String(localized: "Browsers and apps sign out")
            case (true, false): String(localized: "Browsers sign out")
            case (false, true): String(localized: "Apps sign out")
            case (false, false): nil
            }
        if let signOut {
            rows.append(Happening(
                id: "sign_out", title: signOut, line: String(localized: "Each signs in again at the new address."),
                symbol: "rectangle.portrait.and.arrow.right"))
        }
        if codes.contains("passkeys_unusable") {
            rows.append(Happening(
                id: "passkeys_unusable", title: String(localized: "Passkeys for other domains stop working"),
                line: String(localized: "Add a new one at the new address."), symbol: "person.badge.key"))
        }
        let worded: Set<String> = ["browser_sessions_end", "apps_sign_in_again", "passkeys_unusable"]
        for consequence in consequences where !worded.contains(consequence.code) {
            rows.append(Happening(id: "\(consequence.code):\(consequence.sentence)", title: consequence.sentence, line: nil, symbol: "link"))
        }
        rows.append(Happening(
            id: "keys", title: String(localized: "Keys keep working"), line: String(localized: "If the old address stops working, update your scripts."),
            symbol: "key"))
        return rows
    }
}
