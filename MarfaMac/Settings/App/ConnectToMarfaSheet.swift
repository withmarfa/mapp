import AppKit
import Marfa
import SwiftUI

struct ConnectToMarfaSheet: View {
    @Bindable var model: MarfaSettingsModel
    let dismiss: () -> Void
    @State private var check: AddressCheck?

    private struct AddressCheck {
        let address: String
        let status: Status
    }

    private enum Status: Equatable {
        case checking, found, notSetUp, unknown, unavailable, notFound

        var words: Text {
            switch self {
            case .checking: Text("Checking…")
            case .found: Text("Found")
            case .notSetUp: Text("This Marfa isn’t set up yet.")
            case .unknown: Text("Couldn’t tell whether this Marfa is set up.")
            case .unavailable: Text("Marfa isn’t answering.")
            case .notFound: Text("Not found")
            }
        }

        var symbol: String {
            switch self {
            case .found: "checkmark.circle.fill"
            case .notSetUp, .unavailable: "exclamationmark.circle.fill"
            case .unknown: "questionmark.circle.fill"
            case .notFound: "xmark.circle.fill"
            case .checking: ""
            }
        }

        var color: Color {
            switch self {
            case .found: SettingsTokens.ok
            case .notFound: SettingsTokens.errorRed
            case .checking, .notSetUp, .unknown, .unavailable: SettingsTokens.warning
            }
        }

        init(_ health: InstanceHealth) {
            switch health.claimed {
            case false?: self = .notSetUp
            case true?: self = health.status == .down ? .unavailable : .found
            case nil: self = .unknown
            }
        }
    }

    var body: some View {
        SettingsSheet(
            title: model.code == nil ? Text("Connect to a Marfa") : Text("Approve This App with This Code"),
            line: model.code == nil ? Text("Next, you sign in on its own page.") : nil
        ) {
            if let code = model.code {
                ConnectionCodeSection(code: code, showsTitle: false)
            } else {
                addressForm
            }
        } leading: {
            if model.code == nil, !model.isWorking {
                SettingsButton("Sign In with a Code…") { model.start(.connect(usingCode: true)) }
                    .accessibilityIdentifier("MarfaConnectCode")
            }
        } buttons: {
            if model.isWorking, model.code == nil { ProgressView().controlSize(.small) }
            SettingsButton("Cancel", action: dismiss)
                .keyboardShortcut(.cancelAction)
                .disabled(model.isWorking && !model.canCancelSignIn)
                .accessibilityIdentifier("MarfaConnectCancel")
            if model.code == nil {
                SettingsButton("Continue", role: .confirm, action: continueSignIn)
                    .disabled(!model.canConnect)
                    .accessibilityIdentifier("MarfaConnect")
            }
        }
        .accessibilityIdentifier("ConnectToMarfaSheet")
    }

    private var addressForm: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Metric.sheetFieldGap) {
            SettingsSheetField(label: "Address") {
                SettingsField(
                    title: "Address", text: $model.address, prompt: String(localized: "marfa.example"),
                    width: nil, trailingAccessory: AnyView(statusMark),
                    onSubmit: continueSignIn
                )
                .disabled(model.isWorking)
                .accessibilityIdentifier("MarfaAddress")
            }
            if let notice = model.notice {
                SettingsCard {
                    SettingsProblemRow(title: Text(verbatim: notice.title), line: Text(verbatim: notice.message), actions: [])
                        .accessibilityIdentifier("MarfaNotice")
                }
            }
        }
        .padding(.bottom, ChipLooks.defaults.focusRingWidth)
        .task(id: model.isWorking ? nil : model.address) { [address = model.isWorking ? nil : model.address] in
            if let address { await checkAddress(address) }
        }
    }

    private var statusMark: some View {
        Group {
            if let check, check.address == model.address {
                Group {
                    if check.status == .checking {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: check.status.symbol)
                            .font(.system(size: SettingsTokens.Metric.statusMark, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(SettingsTokens.tileForeground, check.status.color)
                    }
                }
                .help(check.status.words)
                .accessibilityLabel(check.status.words)
                .accessibilityIdentifier("MarfaAddressStatus")
            } else {
                Color.clear
            }
        }
        .frame(width: SettingsTokens.Metric.statusMark, height: SettingsTokens.Metric.statusMark)
    }

    private func checkAddress(_ address: String) async {
        guard let connection = try? MarfaConnection(address: address) else { return }
        do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
        guard !Task.isCancelled, model.address == address, !model.isWorking else { return }
        check = AddressCheck(address: address, status: .checking)
        let status: Status
        do {
            let server = try connection.server(key: "")
            status = Status(try await server.health(timeout: .seconds(5)))
        } catch {
            status = .notFound
        }
        guard !Task.isCancelled, model.address == address else { return }
        check = AddressCheck(address: address, status: status)
    }

    private func continueSignIn() {
        if model.canConnect { model.start(.connect(usingCode: false)) }
    }
}

struct ConnectionCodeSection: View {
    let code: CodeSignIn
    var showsTitle = true

    var body: some View {
        SettingsSection(
            name: showsTitle ? Text("Approve This App with This Code") : nil,
            footer: Text("Open \(code.address.absoluteString) on any device, sign in and type the code. It stops working at \(DateDisplay.timeOfDay(of: code.expiresAt, format: .stored())).")
        ) {
            SettingsRow(verbatim: code.code) {
                SettingsButton("Copy Code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.code, forType: .string)
                }
            }
            .textSelection(.enabled)
            .accessibilityIdentifier("MarfaSignInCode")
            SettingsRow(title: Text("Approve in a Browser"), line: Text(verbatim: code.address.absoluteString)) {
                SettingsButton("Open Page…") { NSWorkspace.shared.open(code.completeAddress ?? code.address) }
            }
        }
    }
}
