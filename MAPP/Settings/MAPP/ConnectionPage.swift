import AppKit
import SwiftUI

/// The Connection page: the server in use and how it stands, each change that needs the person, the sign-in and the
/// other server, the downloaded files, and Disconnect. With no server set it is the address to sign in to. What each
/// step does is `MarfaSettingsModel`'s, unchanged; this draws it from the parts.
struct ConnectionPage: View {
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library
    @State private var isChoosingOther = false

    private var host: MarfaHost { libraries.host }
    private var model: MarfaSettingsModel { libraries.marfaSettings }

    var body: some View {
        SettingsPageColumn {
            if let connection = host.configuredConnection {
                connected(to: connection)
            } else {
                disconnected
            }
            codeSection
            noticeSection
            if let connection = host.configuredConnection {
                if isSignedOut == false { otherServer }
                if let library, let files = library.downloadedFiles {
                    ConnectionDownloads(files: files).id(ObjectIdentifier(library))
                }
                if Reporting.carriesDestination { ErrorReportRows() }
                disconnect(from: connection)
            }
        }
        .accessibilityIdentifier("ConnectionPage")
        .confirmationDialog("Disconnect from this server?", isPresented: Bindable(model).isConfirmingDisconnect) {
            Button("Disconnect", role: .destructive) { Task { await model.disconnect() } }
        } message: {
            Text("MAPP removes its copy of your library from this Mac and ends its sign-in, also on the server. Your items on the server don’t change.")
        }
    }

    private var isSignedOut: Bool { host.state == .keyRefused }

    // MARK: Not connected

    private var disconnected: some View {
        SettingsSection("Connect to a Marfa", line: "MAPP shows one Marfa at a time.", footer: "MAPP opens the server’s own page to sign in and never sees your password.") {
            SettingsRow("Address", line: "A Marfa server’s address.") {
                SettingsField(
                    title: "Address", text: Bindable(model).address, prompt: "https://marfa.example.com", onSubmit: { model.start(.connect(usingCode: false)) }
                )
                .disabled(model.isWorking)
                .accessibilityIdentifier("MarfaAddress")
            }
            SettingsRow("Sign In", line: "On the server’s own page, in your browser.") {
                signInButtons(
                    title: "Sign In", canStart: model.canConnect, browser: .connect(usingCode: false), code: .connect(usingCode: true),
                    identifier: "MarfaConnect")
            }
        }
    }

    // MARK: Connected

    @ViewBuilder private func connected(to connection: MarfaConnection) -> some View {
        // Read again as the clock passes, so "2 minutes ago" turns to "3" on time.
        SyncStatusReading(host: host) { status in
            let words = standing(status)
            let name = LibraryDescription.name(libraries)
            let host = SettingsWording.hostName(of: connection.address)
            VStack(alignment: .leading, spacing: 10) {
                SettingsHead(
                    symbol: "server.rack", tone: .blue, title: Text(verbatim: name),
                    line: Text(verbatim: [name == host ? nil : host, words.line].compactMap { $0 }.joined(separator: ". "))
                ) {
                    if isSignedOut {
                        signInButtons(
                            title: "Sign In Again", canStart: !model.isWorking, browser: .signInAgain(usingCode: false),
                            code: .signInAgain(usingCode: true), identifier: "MarfaSignInAgain")
                    } else {
                        SettingsValue(verbatim: words.title, dot: words.color)
                    }
                }
                .accessibilityIdentifier("LibrarySummary")
                if let detail = words.detail {
                    SettingsNote(verbatim: detail)
                }
            }
        }
        SettingsSection("Library") {
            if let library {
                SettingsRow("Items") { SettingsValue(verbatim: library.count(in: .allItems).formatted()) }
            }
            SettingsRow("Unsent Changes", line: isSignedOut ? "Sent once you sign in again." : nil) {
                SettingsValue(verbatim: host.waitingChanges.map { $0 > 0 ? Words.changes($0) : String(localized: "None") } ?? String(localized: "Unknown"))
            }
            if let fill = library?.syncReport.fill, fill.state != .complete {
                SettingsRow(fill.state == .updating ? "Updating Library…" : "Downloading Library…") {
                    SettingsValue(verbatim: FillWording.line(fill)).monospacedDigit().accessibilityIdentifier("LibraryFillProgress")
                }
            }
        }
        if library != nil, !host.report.problems.isEmpty {
            SettingsSection("Problems", footer: "Until you decide, these changes stay on this Mac.") {
                ForEach(host.report.problems) { problem in
                    ConnectionProblem(problem: problem, isOnline: host.state == .online)
                }
            }
        }
        if !isSignedOut { signInSection }
    }

    private var signInSection: some View {
        SettingsSection(
            "Your Sign-In",
            footer: "MAPP keeps its sign-in in your Keychain and renews it itself. Sign in again only to change the account or permissions."
        ) {
            SettingsRow("Sign In Again") {
                signInButtons(
                    title: "Sign In Again", canStart: !model.isWorking, browser: .signInAgain(usingCode: false),
                    code: .signInAgain(usingCode: true), identifier: "MarfaSignInAgain")
            }
        }
    }

    private var otherServer: some View {
        SettingsSection("Other Marfas", footer: "Each server has its own copy on this Mac.") {
            SettingsRow("Use Another Marfa", line: "MAPP shows one Marfa at a time.") {
                SettingsButton(isChoosingOther ? "Hide" : "Choose…") { isChoosingOther.toggle() }
            }
            if isChoosingOther {
                SettingsRow("Address") {
                    SettingsField(title: "Address", text: Bindable(model).otherAddress, prompt: "https://marfa.example.com")
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("MarfaOtherAddress")
                }
                SettingsRow("Sign In and Switch") {
                    signInButtons(
                        title: "Sign In and Switch", canStart: model.canSwitch, browser: .switchServer(usingCode: false),
                        code: .switchServer(usingCode: true), identifier: "MarfaSwitch")
                }
            }
        }
    }

    private func disconnect(from connection: MarfaConnection) -> some View {
        SettingsSection("Disconnect") {
            SettingsRow(
                verbatim: String(localized: "Disconnect from \(LibraryDescription.name(libraries))"),
                line: String(localized: "Removes this Mac’s copy and signs MAPP out.")
            ) {
                HStack(spacing: 8) {
                    if model.isWorking { ProgressView().controlSize(.small) }
                    SettingsButton("Disconnect…", role: .destructive) { model.requestDisconnect() }
                        .disabled(model.isWorking)
                        .accessibilityIdentifier(isSignedOut ? "MarfaRefusedDisconnect" : "MarfaDisconnect")
                }
            }
        }
    }

    // MARK: Shared

    /// The two ways to sign in side by side, and Cancel while one waits on the person.
    private func signInButtons(
        title: LocalizedStringKey, canStart: Bool, browser: MarfaSettingsModel.SignInStep, code: MarfaSettingsModel.SignInStep,
        identifier: String
    ) -> some View {
        HStack(spacing: 8) {
            if model.isWorking {
                ProgressView().controlSize(.small)
                if model.canCancelSignIn {
                    SettingsButton("Cancel") { model.cancelSignIn() }.accessibilityIdentifier("MarfaSignInCancel")
                }
            }
            SettingsButton("Use a Code Instead…") { model.start(code) }
                .disabled(!canStart)
                .accessibilityIdentifier(identifier + "Code")
            SettingsButton(title) { model.start(browser) }
                .disabled(!canStart)
                .accessibilityIdentifier(identifier)
        }
    }

    /// The code to approve on another device, while a sign-in with a code waits for it.
    @ViewBuilder private var codeSection: some View {
        if let code = model.code {
            SettingsSection(
                name: Text("Approve MAPP with This Code"),
                footer: Text("Open \(code.address.absoluteString) on any device, sign in and type the code. It stops working at \(code.expiresAt.formatted(date: .omitted, time: .shortened)).")
            ) {
                SettingsRow(verbatim: code.code) {
                    HStack(spacing: 8) {
                        SettingsButton("Open Page") { NSWorkspace.shared.open(code.completeAddress ?? code.address) }
                        SettingsButton("Copy Code") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code.code, forType: .string)
                        }
                    }
                }
                .textSelection(.enabled)
                .accessibilityIdentifier("MarfaSignInCode")
            }
        }
    }

    @ViewBuilder private var noticeSection: some View {
        if let notice = model.notice {
            SettingsCard {
                SettingsRow(
                    verbatim: notice.title, line: notice.message, lead: .tint("exclamationmark.triangle", .orange), lines: nil
                )
                .accessibilityIdentifier("MarfaNotice")
            }
        }
    }

    // MARK: Standing

    /// How the server stands: a word, a dot, and what to do about it.
    /// The status word goes once, at the head's trailing edge; the line says only what else is true of it.
    private func standing(_ status: SyncStatus) -> (title: String, line: String?, detail: String?, color: Color) {
        let connection = ConnectionStatus(host.state)
        if let note = status.primary {
            return (connection.title, note.line, connection.detail ?? note.detail, note.dotColor)
        }
        switch host.state {
        case .online: return (connection.title, upToDate(), nil, SettingsTokens.ok)
        default:
            return (connection.title, nil, connection.detail, connection.isProblem ? SettingsTokens.Tone.red.color : SettingsTokens.secondaryText)
        }
    }

    private func upToDate() -> String { ConnectionHeadWording.upToDate(since: host.lastSynced, now: .now) }
}

/// The words of the Connection head's line.
enum ConnectionHeadWording {
    /// "Up to date 2 minutes ago", or "Up to date" before the first sync has finished.
    static func upToDate(since synced: Date?, now: Date, locale: Locale = .current) -> String {
        guard let synced else { return String(localized: "Up to date") }
        guard let age = SyncFootLine.age(of: synced, now: now, locale: locale) else { return String(localized: "Up to date just now") }
        return String(localized: "Up to date \(age)")
    }
}

/// One change that needs the person, drawn as a problem row with its actions, then the text they wrote where it can be
/// copied. What each action does is `library.resolve`'s, unchanged.
private struct ConnectionProblem: View {
    @CurrentLibrary private var library
    @Environment(\.openWindow) private var openWindow
    let problem: SyncProblemEntry
    let isOnline: Bool
    @State private var failed: String?
    @State private var confirming: ProblemWording.Confirmation?
    @State private var isWorking = false

    private var wording: ProblemWording { ProblemWording(problem) { library.item($0)?.title } }

    var body: some View {
        SettingsProblemRow(title: Text(verbatim: wording.headline), line: Text(verbatim: wording.explanation), actions: actions)
            .disabled(isWorking)
            .accessibilityIdentifier("SyncProblem")
            .confirmationDialog(
                confirming?.title ?? "",
                isPresented: Binding { confirming != nil } set: { if !$0 { confirming = nil } },
                presenting: confirming
            ) { confirmation in
                Button(confirmation.button, role: .destructive) {
                    if confirmation.copiesText { copyText() }
                    resolve(confirmation.action)
                }
            } message: { confirmation in
                Text(confirmation.message)
            }
        ForEach(wording.details, id: \.self) { detail in
            SettingsRow(verbatim: detail, size: .compact, lines: nil)
        }
        if wording.canCopyText {
            SettingsRow(title: Text(verbatim: problem.copyText).font(SettingsTokens.font(.mono)), size: .compact)
                .textSelection(.enabled)
        }
        if let failed {
            SettingsRow(title: Text(verbatim: failed).foregroundStyle(SettingsTokens.errorRed), size: .compact)
        }
    }

    private var actions: [SettingsProblemAction] {
        var actions = wording.actions.map { action in
            SettingsProblemAction(verbatim: action.title, isDestructive: action.isDestructive, isPrimary: !action.isDestructive) { act(action) }
        }
        if let original = wording.original { actions.append(SettingsProblemAction("Open Original") { openWindow(value: original) }) }
        if let copy = wording.copy { actions.append(SettingsProblemAction("Open Copy") { openWindow(value: copy) }) }
        if wording.canCopyText { actions.append(SettingsProblemAction("Copy Text", perform: copyText)) }
        return actions
    }

    private func act(_ action: ProblemWording.Action) {
        if action.needsServer && !isOnline {
            failed = String(localized: "This needs the server. Try again when you’re back online.")
            return
        }
        if let confirmation = wording.confirmation(for: action.action) {
            confirming = confirmation
        } else {
            resolve(action.action)
        }
    }

    private func resolve(_ action: SyncAction) {
        isWorking = true
        failed = nil
        Task {
            defer { isWorking = false }
            do {
                let done = try await library.resolve(problem.id, by: action)
                if !done { failed = String(localized: "That can’t be done right now.") }
            } catch {
                failed = (error as? SourceFailure)?.message ?? String(localized: "That didn’t work. Try again in a moment.")
            }
        }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(problem.copyText, forType: .string)
    }
}

/// The switch for reporting errors and timings to WithMarfa, shown only in a build that carries a destination for them
/// (`Reporting.carriesDestination`). It is on until turned off, and turning it off stops reporting at once.
private struct ErrorReportRows: View {
    @AppStorage(Reporting.switchKey) private var sends = true

    var body: some View {
        SettingsSection(
            "Privacy",
            footer: "Sends errors and timings to WithMarfa to help fix problems. Never includes your items, their text, your server’s address or anything you type."
        ) {
            SettingsRow("Send Error Reports") {
                SettingsToggle(title: "Send Error Reports", isOn: $sends).accessibilityIdentifier("SendErrorReports")
            }
        }
        .onChange(of: sends) { _, isOn in Reporting.shared.switchChanged(to: isOn) }
    }
}
