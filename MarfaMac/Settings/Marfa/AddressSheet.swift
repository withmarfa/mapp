import SwiftUI

/// The Network page's sheets, which the window shows in its middle: adding an address or a website, and moving the
/// sign-in address, which says what changes first.
struct AddressSheet: View {
    @Bindable var model: AddressesModel
    let serverName: String

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
        case .changeSignIn?, nil: model.signInAddress.map { Text("From \(AddressesModel.display($0)).") }
        }
    }

    private var confirmTitle: LocalizedStringKey {
        switch model.sheet {
        case .addAddress?: "Add Address"
        case .addWebsite?: "Add Website"
        case .changeSignIn?, nil: "Change Address…"
        }
    }

    var body: some View {
        SettingsSheet(title: title, line: line, isWide: model.sheet == .changeSignIn) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFieldGap) {
                SettingsSheetField(label: model.sheet == .changeSignIn ? "New Address" : "Address", error: model.inputError) {
                    SettingsField(
                        title: "Address", text: $model.input, prompt: "https://", isError: model.inputError != nil, width: nil,
                        onSubmit: { Task { await model.confirm() } })
                }
                if model.sheet == .changeSignIn, let plan = model.currentPlan {
                    SettingsSection("What Happens") {
                        ForEach(Self.happenings(plan.consequences)) { happening in
                            SettingsRow(verbatim: happening.title, line: happening.line, lead: .symbol(happening.symbol), lines: nil)
                        }
                    }
                }
                if let status = status { SettingsSheetStatus(text: Text(verbatim: status)) }
            }
            .task(id: model.input) {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
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
        case .changeSignIn?: return model.currentPlan?.reach == .answers ? String(localized: "\(serverName) answers there.") : nil
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
            case (true, true): String(localized: "Every browser and app signs out")
            case (true, false): String(localized: "Every browser signs out")
            case (false, true): String(localized: "Every app signs out")
            case (false, false): nil
            }
        if let signOut {
            rows.append(Happening(
                id: "sign_out", title: signOut, line: String(localized: "Each signs in again at the new address."),
                symbol: "rectangle.portrait.and.arrow.right"))
        }
        if codes.contains("passkeys_unusable") {
            rows.append(Happening(
                id: "passkeys_unusable", title: String(localized: "Passkeys stop working"),
                line: String(localized: "Add a passkey at the new address."), symbol: "person.badge.key"))
        }
        let worded: Set<String> = ["browser_sessions_end", "apps_sign_in_again", "passkeys_unusable"]
        for consequence in consequences where !worded.contains(consequence.code) {
            rows.append(Happening(id: consequence.code, title: consequence.sentence, line: nil, symbol: "link"))
        }
        rows.append(Happening(
            id: "keys", title: String(localized: "Keys keep working"), line: String(localized: "If the old address stops working, update your scripts."),
            symbol: "key"))
        return rows
    }
}
