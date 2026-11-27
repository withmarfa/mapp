import SwiftUI

/// Network shows where people sign in, the other addresses this Marfa answers on and the websites allowed to call
/// it. Each address is checked by the server before it is added, removed or moved.
struct NetworkPage: View {
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
                model.question?.title ?? "",
                isPresented: Binding {
                    model.question != nil
                } set: {
                    if !$0 { model.cancelQuestion() }
                },
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
                Text(
                    "\(host.serverName) can send webhooks, the heartbeat, error reports, telemetry, and object store requests to addresses that aren’t public, including its own computer and devices on private networks such as Tailscale."
                )
            }
            .accessibilityIdentifier("NetworkPage")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure, model.settings == nil || failure == .unreachable {
            OwnerFailureState(page: .network, failure: failure, host: host) { Task { await model.load() } }
        } else if let settings = model.settings {
            SettingsPageColumn {
                SettingsSection("Sign-In Address") {
                    SettingsRow(
                        title: Text(verbatim: AddressesModel.display(settings.signIn)), line: Text("Where you sign in, and where apps connect.")
                    ) {
                        SettingsButton("Change…") { model.begin(.changeSignIn) }
                    }
                }
                if let failure = model.rowErrors[settings.signIn] { OwnerProblem(title: "Not changed", failure: failure, page: .network, host: host) }
                SettingsSection("Other Addresses", footer: "This Marfa answers on these too.") {
                    SettingsButton("Add Address…") { model.begin(.addAddress) }
                } content: {
                    ForEach(model.otherAddresses, id: \.self) { address in
                        SettingsRow(
                            title: Text(verbatim: AddressesModel.display(address)), line: AddressesModel.kind(of: address).map { Text(verbatim: $0) },
                            error: model.rowErrors[address].map { OwnerWording.line($0, on: .network) }
                        ) {
                            SettingsMoreMenu { Button("Remove", role: .destructive) { Task { await model.askToRemove(address: address) } } }
                        }
                    }
                }
                SettingsSection("Websites", footer: "Pages on these sites may call this Marfa.") {
                    SettingsButton("Add Website…") { model.begin(.addWebsite) }
                } content: {
                    ForEach(settings.websites, id: \.self) { website in
                        SettingsRow(
                            title: Text(verbatim: AddressesModel.display(website)),
                            error: model.rowErrors[website].map { OwnerWording.line($0, on: .network) }
                        ) {
                            SettingsMoreMenu { Button("Remove", role: .destructive) { model.askToRemove(website: website) } }
                        }
                    }
                }
                networkSection
            }
        } else {
            OwnerLoading()
        }
    }

    @ViewBuilder private var networkSection: some View {
        if let notice = network.notice { OwnerNotice(title: "Changed elsewhere", line: notice, close: { network.dismissNotice() }) }
        if network.isLoaded || network.failure != nil { networkRows }
    }

    private var networkRows: some View {
        SettingsSection(name: nil) {
            if network.isLoaded {
                SettingsRow("Private addresses", line: "Lets webhooks and the heartbeat reach this network.", error: network.line, lines: nil) {
                    SettingsToggle(
                        title: "Private addresses",
                        isOn: Binding {
                            network.isOn
                        } set: { on in
                            Task { await network.set(on) }
                        }
                    )
                    .disabled(network.isWriting)
                    .accessibilityIdentifier("PrivateAddresses")
                }
            } else if let failure = network.failure {
                OwnerProblemRow(title: "Couldn’t read private addresses", failure: failure, page: .network, host: host) {
                    Task { await network.load() }
                }
            }
        }
    }
}
