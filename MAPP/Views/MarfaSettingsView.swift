import AppKit
import SwiftUI

/// The connection sections of the Library page: the sign-in and the other server while connected, and the address to
/// sign in to otherwise. How the connection stands is told by the server section above. The sections go in the
/// page's grouped form.
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
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("MarfaAddress")
                signInButtons(
                    title: "Sign In", canStart: model.canConnect,
                    browser: .connect(usingCode: false), code: .connect(usingCode: true),
                    identifier: "MarfaConnect")
            } header: {
                Text("Server")
            } footer: {
                Text("Connect to a Marfa server to read and edit its items here. MAPP opens the server’s own page to sign in and never sees your password.")
            }
            codeSection
            notice
        }
    }

    // MARK: Connected

    private func connected(to connection: MarfaConnection) -> some View {
        Group {
            // The server section above names the server and what waits, so only the sign-in and the other server are here.
            signInSection
            codeSection
            notice
            otherServer
        }
    }

    private var isSignedOut: Bool { host.state == .keyRefused }

    private var signInSection: some View {
        Section {
            signInButtons(
                title: "Sign In Again", canStart: !model.isWorking,
                browser: .signInAgain(usingCode: false), code: .signInAgain(usingCode: true),
                identifier: "MarfaSignInAgain")
            if isSignedOut {
                // The other way out: a sign-in the server will not renew needs the library disconnected to start over.
                Button("Disconnect…") { model.requestDisconnect() }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("MarfaRefusedDisconnect")
            }
        } header: {
            Text(isSignedOut ? "Signed out" : "Your Sign-In")
        } footer: {
            if isSignedOut {
                Text("The server has ended MAPP’s sign-in. Sign in again, or disconnect to start again. Changes not yet sent stay on this Mac until you are signed in or choose what to do with them.")
            } else {
                Text("MAPP keeps its sign-in in your Keychain and renews it itself. Sign in again only to change the account or permissions.")
            }
        }
    }

    private var otherServer: some View {
        Section {
            DisclosureGroup("Use a different server") {
                TextField("Address", text: $model.otherAddress, prompt: Text("https://marfa.example.com"))
                    .autocorrectionDisabled()
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("MarfaOtherAddress")
                signInButtons(
                    title: "Sign In and Switch", canStart: model.canSwitch,
                    browser: .switchServer(usingCode: false), code: .switchServer(usingCode: true),
                    identifier: "MarfaSwitch")
            }
        } footer: {
            Text("Each server has its own copy on this Mac.")
        }
    }

    /// The two ways to sign in, side by side, and Cancel while one waits on the person.
    private func signInButtons(
        title: LocalizedStringKey, canStart: Bool,
        browser: MarfaSettingsModel.SignInStep, code: MarfaSettingsModel.SignInStep, identifier: String
    ) -> some View {
        HStack {
            Button(title) { model.start(browser) }
                .disabled(!canStart)
                .accessibilityIdentifier(identifier)
            Button("Use a Code Instead…") { model.start(code) }
                .disabled(!canStart)
                .accessibilityIdentifier(identifier + "Code")
            if model.isWorking {
                ProgressView().controlSize(.small)
                if model.canCancelSignIn {
                    Button("Cancel", role: .cancel) { model.cancelSignIn() }
                        .accessibilityIdentifier("MarfaSignInCancel")
                }
            }
        }
    }

    /// The code to approve on another device, while a sign-in with a code waits for it.
    @ViewBuilder private var codeSection: some View {
        if let code = model.code {
            Section {
                Text(code.code)
                    .font(.system(.title, design: .monospaced).bold())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("MarfaSignInCode")
                HStack {
                    Button("Open Page") { NSWorkspace.shared.open(code.completeAddress ?? code.address) }
                    Button("Copy Code") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code.code, forType: .string)
                    }
                }
            } header: {
                Text("Approve MAPP With This Code")
            } footer: {
                Text("Open \(code.address.absoluteString) on any device, sign in and type the code. It stops working at \(code.expiresAt.formatted(date: .omitted, time: .shortened)).")
            }
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

    /// Whether the person has been shown how many changes they would lose. The package removes a copy only
    /// against that number, so a copy whose changes can't be counted is kept, never discarded.
    private var canDiscard: Bool { departure.unsent != nil || otherVersionUnsent != nil }

    /// Where the copy is, for the person to remove when MAPP can't.
    private var copyFolder: String {
        model.host.configuredConnection.map { model.host.location.directory(for: $0).path } ?? ""
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
                Text(Words.cannotDiscard(folder: copyFolder))
            }
            Group {
                if !canDiscard {
                    Text("Keep the copy and the changes stay on this Mac.")
                } else if isOtherVersion {
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
                if canDiscard {
                    Button(isDisconnecting ? "Discard Changes and Disconnect" : "Discard Changes and Switch", role: .destructive) {
                        Task { await model.answer(.discardCopy) }
                    }
                    .accessibilityIdentifier("DepartureDiscard")
                }
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
