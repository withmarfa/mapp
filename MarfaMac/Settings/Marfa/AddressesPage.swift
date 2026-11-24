import SwiftUI

/// The Addresses page: where people sign in, the other addresses this Marfa answers on and the websites allowed to call
/// it. Each address is checked by the server before it is added, removed or moved.
struct AddressesPage: View {
    let host: any MarfaSettingsHost
    @State private var model: AddressesModel
    @State private var network: PrivateAddressesModel

    init(host: any MarfaSettingsHost) {
        self.init(host: host, network: PrivateAddressesModel(context: OwnerContext(host: host), calls: host.instanceCalls))
    }

    init(host: any MarfaSettingsHost, network: PrivateAddressesModel) {
        self.host = host
        _model = State(initialValue: AddressesModel(context: OwnerContext(host: host)))
        _network = State(initialValue: network)
    }

    var body: some View {
        content
            .task(id: host.serverAddress) {
                async let network: Void = network.load()
                await model.load()
                await network
            }
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
            .alert("Allow Private Addresses?", isPresented: $network.asksToAllow) {
                Button("Cancel", role: .cancel) {}
                Button("Allow") { Task { await network.allow() } }
            } message: {
                Text("\(host.serverName) will send webhooks, the heartbeat, error reports, telemetry and backups to addresses that aren’t public: the machine it runs on, and networks such as a home network or Tailscale.")
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
                networkSection
            }
        } else {
            OwnerLoading()
        }
    }

    @ViewBuilder private var networkSection: some View {
        if let notice = network.notice { OwnerNotice(title: "Changed Elsewhere", line: notice, close: { network.dismissNotice() }) }
        if network.isLoaded || network.failure != nil { networkRows }
    }

    private var networkRows: some View {
        SettingsSection("Network") {
            if network.isLoaded {
                SettingsRow("Private Addresses", line: "Lets webhooks and the heartbeat reach this network.", error: network.line) {
                    SettingsToggle(title: "Private Addresses", isOn: Binding { network.isOn } set: { on in Task { await network.set(on) } })
                        .disabled(network.isWriting)
                        .accessibilityIdentifier("PrivateAddresses")
                }
            } else if let failure = network.failure {
                OwnerProblemRow(title: "Couldn’t Read Private Addresses", failure: failure, page: .addresses, host: host) {
                    Task { await network.load() }
                }
            }
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
                line: String(localized: "A passkey works only where it was added. Add them again."), symbol: "person.badge.key"))
        }
        let worded: Set<String> = ["browser_sessions_end", "apps_sign_in_again", "passkeys_unusable"]
        for consequence in consequences where !worded.contains(consequence.code) {
            rows.append(Happening(id: consequence.code, title: consequence.sentence, line: nil, symbol: "link"))
        }
        rows.append(Happening(
            id: "keys", title: String(localized: "Keys keep working"), line: String(localized: "Scripts change the address they call."),
            symbol: "key"))
        return rows
    }
}
