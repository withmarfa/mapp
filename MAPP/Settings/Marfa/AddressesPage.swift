import SwiftUI

/// The Addresses page: where people sign in, the other addresses this Marfa answers on and the websites allowed to call
/// it. Each address is checked by the server before it is added, removed or moved.
struct AddressesPage: View {
    let host: any MarfaSettingsHost
    @State private var model: AddressesModel

    init(host: any MarfaSettingsHost) {
        self.host = host
        _model = State(initialValue: AddressesModel(context: OwnerContext(host: host)))
    }

    var body: some View {
        content
            .task(id: host.serverAddress) { await model.load() }
            .onAppear { host.ownerDrafts.register(model) }
            .settingsSheet(presenting: model.sheet != nil, dismiss: { model.close() }) { AddressSheet(model: model, serverName: host.serverName) }
            .alert(
                model.question?.title ?? "", isPresented: Binding { model.question != nil } set: { if !$0 { model.cancelQuestion() } },
                presenting: model.question
            ) { asked in
                Button("Cancel", role: .cancel) {}
                Button(asked.confirm, role: .destructive) { Task { await model.confirm(asked) } }
            } message: { asked in
                Text(verbatim: asked.message)
            }
            .accessibilityIdentifier("AddressesPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure, model.settings == nil {
            OwnerFailureState(page: .addresses, failure: failure, host: host) { Task { await model.load() } }
        } else if let settings = model.settings {
            SettingsPageColumn {
                SettingsHead(
                    name: Text("Sign-In Address"), symbol: "globe", tone: .teal, title: Text(verbatim: AddressesModel.display(settings.signIn)),
                    line: Text("Where you sign in, and where apps connect.")
                ) {
                    SettingsButton("Change…") { model.begin(.changeSignIn) }
                }
                if let failure = model.rowErrors[settings.signIn] { OwnerProblem(title: "Not Changed", failure: failure, page: .addresses, host: host) }
                SettingsSection("Other Addresses", line: "\(host.serverName) answers on these too.") {
                    ForEach(model.otherAddresses, id: \.self) { address in
                        SettingsRow(
                            verbatim: AddressesModel.display(address), line: AddressesModel.kind(of: address),
                            error: model.rowErrors[address].map { OwnerWording.line($0, on: .addresses) }
                        ) {
                            SettingsMoreMenu { Button("Remove…", role: .destructive) { Task { await model.askToRemove(address: address) } } }
                        }
                    }
                    SettingsAddRow("Add an Address…") { model.begin(.addAddress) }
                }
                SettingsSection("Websites", line: "Pages on these sites may call \(host.serverName).") {
                    ForEach(settings.websites, id: \.self) { website in
                        SettingsRow(verbatim: AddressesModel.display(website), error: model.rowErrors[website].map { OwnerWording.line($0, on: .addresses) }) {
                            SettingsMoreMenu { Button("Remove…", role: .destructive) { model.askToRemove(website: website) } }
                        }
                    }
                    SettingsAddRow("Add a Website…") { model.begin(.addWebsite) }
                }
            }
        } else {
            OwnerLoading()
        }
    }
}

/// The Addresses page's sheets, which the window shows in its middle: adding an address or a website, and moving the
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
            VStack(alignment: .leading, spacing: 12) {
                SettingsSheetField(label: model.sheet == .changeSignIn ? "New Address" : "Address", error: model.inputError) {
                    SettingsField(
                        title: "Address", text: $model.input, prompt: "https://", isError: model.inputError != nil, width: nil,
                        onSubmit: { Task { await model.confirm() } })
                }
                if model.sheet == .changeSignIn, let plan = model.currentPlan, !plan.consequences.isEmpty {
                    SettingsSection("What Happens") {
                        ForEach(plan.consequences, id: \.code) { consequence in
                            SettingsRow(verbatim: Self.title(of: consequence), line: consequence.sentence, lead: .symbol(Self.symbol(consequence.code)), lines: nil)
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
            Spacer(minLength: 0)
            SettingsButton("Cancel") { model.close() }
            SettingsButton(confirmTitle) { Task { await model.confirm() } }
                .disabled(model.sheet == .addWebsite ? !(model.inputError == nil && AddressesModel.origin(from: model.input) != nil) : !model.canConfirm)
                .keyboardShortcut(.defaultAction)
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

    static func title(of consequence: AddressPlan.Consequence) -> String {
        switch consequence.code {
        case "browser_sessions_end": String(localized: "Every browser signs out")
        case "passkeys_unusable": String(localized: "Passkeys stop working")
        case "apps_sign_in_again": String(localized: "Every app signs out")
        case "address_removed": String(localized: "An address is removed")
        default: consequence.sentence
        }
    }

    static func symbol(_ code: String) -> String {
        switch code {
        case "browser_sessions_end", "apps_sign_in_again": "rectangle.portrait.and.arrow.right"
        case "passkeys_unusable": "person.badge.key"
        default: "link"
        }
    }
}
