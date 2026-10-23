import AppKit
import SwiftUI

/// The connection sections of the Library page: the server the app reads from, and the key. How the connection
/// stands is told by the summary at the top of the page. The sections go in the page's grouped form.
struct MarfaSettingsView: View {
    @Bindable var model: MarfaSettingsModel

    private var host: MarfaHost { model.host }

    var body: some View {
        Group {
            if let connection = host.configuredConnection {
                connected(to: connection)
            } else {
                disconnected
            }
        }
    }

    // MARK: Not connected

    private var disconnected: some View {
        Group {
            Section {
                TextField("Address", text: $model.address, prompt: Text("https://marfa.example.com"))
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("MarfaAddress")
                SecureField("Key", text: $model.key, prompt: Text("Paste your key"))
                    .accessibilityIdentifier("MarfaKey")
                HStack {
                    Button("Connect") { Task { await model.connect() } }
                        .disabled(!model.canConnect)
                        .accessibilityIdentifier("MarfaConnect")
                    if model.isWorking { ProgressView().controlSize(.small) }
                }
            } header: {
                Text("Marfa Server")
            } footer: {
                Text("Connect to a Marfa server to read and edit its items here. MAPP keeps the key in your Keychain and doesn’t show it again. Your notes folder is used again if you disconnect.")
            }
            notice
        }
    }

    // MARK: Connected

    private func connected(to connection: MarfaConnection) -> some View {
        Group {
            Section {
                LabeledContent("Address") {
                    Text(connection.address.absoluteString)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .accessibilityIdentifier("MarfaConnectedAddress")
                if let waiting = host.waitingChanges, waiting > 0 {
                    LabeledContent("Waiting to Send") { Text(Words.changes(waiting)).foregroundStyle(.secondary) }
                }
            } header: {
                Text("Marfa Server")
            }
            keySection
            notice
            otherServer
        }
    }

    private var isKeyRefused: Bool { host.state == .keyRefused }

    private var keySection: some View {
        Section {
            SecureField("New Key", text: $model.newKey, prompt: Text("Paste a new key"))
                .accessibilityIdentifier("MarfaNewKey")
            Button(isKeyRefused ? "Use New Key" : "Replace Key") { Task { await model.replaceKey() } }
                .disabled(!model.canReplaceKey)
                .accessibilityIdentifier("MarfaReplaceKey")
        } header: {
            Text(isKeyRefused ? "Key refused" : "Key")
        } footer: {
            if isKeyRefused {
                Text("The server doesn’t accept your key. Changes you make are kept on this Mac and sent once a key works.")
            } else {
                Text("MAPP keeps the key in your Keychain and doesn’t show it again.")
            }
        }
    }

    private var otherServer: some View {
        Section {
            DisclosureGroup("Use a Different Server") {
                TextField("Address", text: $model.otherAddress, prompt: Text("https://marfa.example.com"))
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("MarfaOtherAddress")
                SecureField("Key", text: $model.otherKey, prompt: Text("Paste its key"))
                    .accessibilityIdentifier("MarfaOtherKey")
                Button("Switch Server") { Task { await model.switchServer() } }
                    .disabled(!model.canSwitch)
                    .accessibilityIdentifier("MarfaSwitch")
            }
        } footer: {
            Text("Each server has its own copy on this Mac.")
        }
    }

    @ViewBuilder private var notice: some View {
        if let notice = model.notice {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label(notice.title, systemImage: "exclamationmark.triangle")
                        .interfaceFont(.headline)
                        .foregroundStyle(Color.orange)
                    Text(notice.message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("MarfaNotice")
            }
        }
    }
}

/// Asked when a copy is left while changes wait in it: keep it, so connecting to the same server again sends
/// them, or discard it with them. The text of what would be lost is shown, since it is the only copy.
struct DepartureSheet: View {
    let model: MarfaSettingsModel
    let departure: MarfaSettingsModel.Departure

    private var isDisconnecting: Bool { departure.kind == .disconnect }

    /// Whether the copy is one a different version of the app made. This version can't send what it holds, so
    /// keeping the copy does not send it on connecting again.
    private var isOtherVersion: Bool {
        if case .otherVersion = model.host.state { true } else { false }
    }

    private var otherVersionUnsent: UInt64? {
        if case .otherVersion(let unsent) = model.host.state { unsent } else { nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Changes Haven’t Been Sent")
                .interfaceFont(.title2.bold())
            if departure.isAskedAgain {
                Text("More changes arrived while you were deciding. Look at them before you choose.")
                    .foregroundStyle(.orange)
            }
            if let unsent = departure.unsent {
                Text(Words.notSent(unsent.count))
                changes(unsent)
            } else if let held = otherVersionUnsent {
                Text(Words.notSent(Int(clamping: held)))
            } else {
                Text("MAPP can’t tell what’s waiting in the copy on this Mac.")
            }
            Group {
                if isOtherVersion {
                    Text("Keep the copy and the changes stay on this Mac. Install the previous build of MAPP from TestFlight and connect it to the same server, and it sends them. Discard the copy and they’re lost.")
                } else {
                    Text("Keep the copy and the changes stay on this Mac. Connect to the same server again and they’re sent. Discard the copy and they’re lost.")
                }
            }
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel", role: .cancel) { model.cancelDeparture() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("DepartureCancel")
                Spacer()
                Button(isDisconnecting ? "Discard Changes and Disconnect" : "Discard Changes and Switch", role: .destructive) {
                    Task { await model.answer(.discardCopy) }
                }
                .accessibilityIdentifier("DepartureDiscard")
                Button(isDisconnecting ? "Keep Copy and Disconnect" : "Keep Copy and Switch") {
                    Task { await model.answer(.keepCopy) }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("DepartureKeep")
            }
            .disabled(model.isWorking)
        }
        .padding(20)
        .frame(width: 580)
        .accessibilityIdentifier("DepartureSheet")
    }

    @ViewBuilder private func changes(_ unsent: UnsentWrites) -> some View {
        if !unsent.texts.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(unsent.texts) { text in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(text.content.plainText)
                                .textSelection(.enabled)
                                .lineLimit(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Copy Text") { copy(text.content.plainText) }
                                .controlSize(.small)
                        }
                        .padding(8)
                        .background(.quaternary, in: .rect(cornerRadius: 6))
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        if unsent.count > unsent.texts.count {
            Text(Words.moreNotShown(unsent.count - unsent.texts.count))
                .foregroundStyle(.secondary)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
