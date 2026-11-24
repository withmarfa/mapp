import AppKit
import SwiftUI

/// The Connection page: the server in use and how it stands, the account (who is signed in, what the owner has allowed
/// the app, what waits to be sent), each change that needs the person, the other server, and Disconnect. With no server set
/// it is the address to sign in to. What each step does is `MarfaSettingsModel`'s, unchanged; this draws it from the parts.
struct ConnectionPage: View {
    let settingsHost: AppSettingsHost
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library
    @State private var isChoosingOther = false
    /// The owner's name and the server it was read from, kept while that server does not answer.
    @State private var accountName: String?
    @State private var accountNameServer: MarfaConnection?
    @State private var isConfirmingRemoval = false
    @State private var isRemoving = false
    @State private var settingsProblem: String?

    private var host: MarfaHost { libraries.host }
    private var model: MarfaSettingsModel { libraries.marfaSettings }

    var body: some View {
        SettingsPageColumn {
            if let connection = host.configuredConnection {
                connected(to: connection)
            } else {
                disconnected
            }
            if host.configuredConnection != nil { appSettings }
            codeSection
            noticeSection
            if let connection = host.configuredConnection {
                otherServer
                disconnect(from: connection)
            }
        }
        .accessibilityIdentifier("ConnectionPage")
        .onChange(of: model.isConfirmingDisconnect) { _, isAsking in
            guard isAsking else { return }
            model.isConfirmingDisconnect = false
            askToDisconnect()
        }
        .alert(Text(verbatim: appSettingsWords.removeTitle), isPresented: $isConfirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { removeSettings() }
        } message: {
            Text(appSettingsWords.removeMessage)
        }
        .alert(
            "Couldn’t Remove This App’s Settings",
            isPresented: Binding { model.settingsRemovalFailure != nil } set: { if !$0 { model.stayConnected() } }
        ) {
            Button("Stay Connected", role: .cancel) {}
            Button("Disconnect Anyway", role: .destructive) { Task { await model.disconnectAnyway() } }
        } message: {
            Text(verbatim: model.settingsRemovalFailure?.reason == .discardedChangesWait
                ? appSettingsWords.discardedChangesWait : appSettingsWords.removalNotTaken)
        }
        .task(id: NameRequest(connection: host.configuredConnection, isOnline: host.state == .online, readsProfile: host.readsProfile)) {
            if accountNameServer != host.configuredConnection {
                accountName = nil
                accountNameServer = host.configuredConnection
            }
            guard let connection = host.configuredConnection, host.state == .online else { return }
            accountName = host.readsProfile ? await MarfaServerCalls(connection: connection, signIns: host.signIns).ownerName() : nil
        }
    }

    private struct NameRequest: Hashable {
        let connection: MarfaConnection?
        let isOnline: Bool
        /// Read again once Allow More… or a new sign-in gives the read of the name.
        let readsProfile: Bool
    }

    // MARK: Not connected

    private var disconnected: some View {
        SettingsSection("Connect to a Marfa", line: "The app shows one Marfa at a time.") {
            if let address = host.unusableAddress {
                SettingsProblemRow(
                    title: Text("Change the Saved Address"), line: Text(verbatim: Words.savedAddressHasMore(address)), actions: [])
                    .accessibilityIdentifier("MarfaSavedAddressNeedsChange")
            }
            SettingsRow("Address") {
                SettingsField(
                    title: "Address", text: Bindable(model).address, onSubmit: { model.start(.connect(usingCode: false)) }
                )
                .disabled(model.isWorking)
                .accessibilityIdentifier("MarfaAddress")
            }
            SettingsRow("Sign In", line: "On the server’s own page, in a sheet.") {
                SettingsButton("Sign In…") { model.start(.connect(usingCode: false)) }
                    .disabled(!model.canConnect)
                    .accessibilityIdentifier("MarfaConnect")
            }
            codeSignInRow(canStart: model.canConnect, step: .connect(usingCode: true), identifier: "MarfaConnectCode")
            if model.isWorking { signInProgress }
        }
    }

    // MARK: Connected

    @ViewBuilder private func connected(to connection: MarfaConnection) -> some View {
        // Read again as the clock passes, so "2 minutes ago" turns to "3" on time.
        SyncStatusReading(host: host) { status in
            let name = LibraryDescription.name(libraries)
            let hostName = SettingsWording.hostName(of: connection.address)
            let standing = ConnectionStanding(
                state: host.state, status: status, lastSynced: host.lastSynced, now: .now, format: .stored())
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.cardGap) {
                SettingsHead(
                    symbol: "server.rack", tone: .blue, title: Text(verbatim: name),
                    line: Text(verbatim: [name == hostName || standing.action != .none ? nil : hostName, standing.line].compactMap { $0 }.joined(separator: ". "))
                ) {
                    headAction(standing)
                }
                .accessibilityIdentifier("LibrarySummary")
                if let detail = standing.detail {
                    SettingsNote(verbatim: detail)
                }
                if FillWording.shows(library?.syncReport.fill, in: host.state), let fill = library?.syncReport.fill {
                    SettingsNote(verbatim: String(localized: "Downloading library… \(FillWording.line(fill))"))
                        .monospacedDigit()
                        .accessibilityIdentifier("LibraryFillProgress")
                }
            }
        }
        account(name: LibraryDescription.name(libraries))
        if library != nil, !host.report.problems.isEmpty {
            SettingsSection("Problems", footer: "Until you decide, these changes stay on this Mac.") {
                ForEach(host.report.problems) { problem in
                    ConnectionProblem(problem: problem, isOnline: host.state == .online)
                }
            }
        }
    }

    @ViewBuilder private func headAction(_ standing: ConnectionStanding) -> some View {
        switch standing.action {
        case .signIn:
            signInButtons(
                title: "Sign In…", canStart: !model.isWorking, browser: .signInAgain(usingCode: false),
                code: .signInAgain(usingCode: true), identifier: "MarfaSignInAgain")
        case .tryAgain:
            HStack(spacing: SettingsTokens.Metric.buttonGap) {
                if let word = standing.word { SettingsValue(verbatim: word, dot: color(of: standing.tone)) }
                SettingsButton("Try Again") { host.refresh() }.accessibilityIdentifier("MarfaTryAgain")
            }
        case .none:
            if let word = standing.word { SettingsValue(verbatim: word, dot: color(of: standing.tone)) }
        }
    }

    private func color(of tone: ConnectionStanding.Tone) -> Color {
        switch tone {
        case .ok: SettingsTokens.ok
        case .warning: SettingsTokens.warning
        case .problem: SettingsTokens.Tone.red.color
        case .quiet: SettingsTokens.secondaryText
        }
    }

    private func account(name: String) -> some View {
        let account = ConnectionAccount(
            state: host.state, grants: host.grants, grantsRead: host.grantsRead, readsProfile: host.readsProfile, lacksAsked: host.lacksAsked,
            waiting: host.waitingChanges, serverName: name)
        return SettingsSection("Account") {
            if account.showsName {
                SettingsRow(title: Text("Signed In As"), line: account.nameLine.map { Text(verbatim: $0) }) {
                    SettingsValue(verbatim: accountName ?? "")
                }
                .accessibilityIdentifier("SignedInAs")
            }
            if account.showsPermissions {
                SettingsRow(title: Text("Look After This Marfa"), line: Text(verbatim: account.permissionsLine)) {
                    // Allow More… asks for everything a sign-in asks for, the read of the owner's name among it.
                    if account.offersMore {
                        SettingsButton(settingsHost.isAllowingMore ? "Waiting…" : "Allow More…") {
                            Task { _ = await settingsHost.allowMore(ConnectionAccount.asked) }
                        }
                        .disabled(settingsHost.isAllowingMore)
                        .accessibilityIdentifier("AllowMore")
                    } else {
                        SettingsValue(verbatim: account.permissionsValue)
                    }
                }
                .accessibilityIdentifier("LookAfterThisMarfa")
            }
            SettingsRow(title: Text("Unsent Changes"), line: account.unsentLine.map { Text(verbatim: $0) }) {
                SettingsValue(verbatim: account.unsent)
            }
        }
        .accessibilityIdentifier("ConnectionAccount")
    }

    private var otherServer: some View {
        SettingsSection("Other Marfas") {
            SettingsRow("Use Another Marfa", line: "The app shows one Marfa at a time.") {
                SettingsButton(isChoosingOther ? "Hide" : "Choose…") { isChoosingOther.toggle() }
            }
            if isChoosingOther {
                SettingsRow("Address", line: "Each server has its own copy on this Mac.") {
                    SettingsField(title: "Address", text: Bindable(model).otherAddress)
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("MarfaOtherAddress")
                }
                SettingsRow("Sign In and Switch") {
                    SettingsButton("Sign In and Switch…") { model.start(.switchServer(usingCode: false)) }
                        .disabled(!model.canSwitch)
                        .accessibilityIdentifier("MarfaSwitch")
                }
                codeSignInRow(canStart: model.canSwitch, step: .switchServer(usingCode: true), identifier: "MarfaSwitchCode")
                if model.isWorking { signInProgress }
            }
        }
    }

    private func disconnect(from connection: MarfaConnection) -> some View {
        SettingsSection("Disconnect") {
            SettingsRow(
                verbatim: String(localized: "Disconnect from \(LibraryDescription.name(libraries))"),
                line: String(localized: "Removes this Mac’s copy and signs the app out.")
            ) {
                HStack(spacing: SettingsTokens.Metric.buttonGap) {
                    if model.isWorking { ProgressView().controlSize(.small) }
                    SettingsButton("Disconnect…", role: .destructive) { model.requestDisconnect() }
                        .disabled(model.isWorking)
                        .accessibilityIdentifier(host.state == .keyRefused ? "MarfaRefusedDisconnect" : "MarfaDisconnect")
                }
            }
        }
    }

    // MARK: This App's Settings

    private var appSettingsWords: ConnectionSettings {
        ConnectionSettings(standing: libraries.preferences.standing, name: LibraryDescription.name(libraries))
    }

    @ViewBuilder private var appSettings: some View {
        let words = appSettingsWords
        if words.isShown {
            SettingsSection(name: Text("This App’s Settings"), footer: Text(ConnectionSettings.footer)) {
                SettingsRow(
                    verbatim: words.title, line: words.line, error: settingsProblem
                ) {
                    if let title = words.actionTitle {
                        SettingsButton(
                            title: Text(verbatim: title), role: words.action == .remove ? .destructive : .normal
                        ) { act(on: words.action) }
                        .disabled(isRemoving || settingsHost.isAllowingMore)
                        .accessibilityIdentifier(identifier(of: words.action))
                    }
                }
                .accessibilityIdentifier("AppSettingsRow")
            }
            .accessibilityIdentifier("AppSettings")
        }
    }

    private func identifier(of action: ConnectionSettings.Action) -> String {
        switch action {
        case .remove: "RemoveAppSettings"
        case .allowMore: "AllowMoreForAppSettings"
        case .keepAgain: "KeepAppSettingsAgain"
        case .none: ""
        }
    }

    private func act(on action: ConnectionSettings.Action) {
        settingsProblem = nil
        switch action {
        case .remove:
            isConfirmingRemoval = true
        case .allowMore:
            // The scopes that keep the settings are asked at every sign-in, so nothing more is named; the copy weighs its
            // slice again with the new sign-in and the section moves on by itself.
            Task { _ = await settingsHost.allowMore([]) }
        case .keepAgain:
            perform { try await libraries.preferences.startAgain() }
        case .none:
            break
        }
    }

    private func removeSettings() {
        perform { try await libraries.preferences.remove() }
    }

    private func perform(_ step: @escaping () async throws -> Void) {
        isRemoving = true
        Task {
            defer { isRemoving = false }
            do {
                try await step()
            } catch {
                settingsProblem = String(localized: "That didn’t work. Try again in a moment.")
            }
        }
    }

    /// The question before Disconnect, with the choice to take this app's settings out of the Marfa too where they are kept there.
    private func askToDisconnect() {
        let name = LibraryDescription.name(libraries)
        SettingsAlert.confirm(
            title: String(localized: "Disconnect from \(name)?"),
            message: String(localized: "The app removes its copy from this Mac and signs out. Webhooks it made are deleted. Your items stay."),
            confirm: String(localized: "Disconnect"),
            checkbox: model.offersSettingsRemoval ? appSettingsWords.disconnectChoice : nil,
            window: NSApp.keyWindow
        ) { confirmed, checked in
            guard confirmed else { return }
            model.alsoRemovesSettings = checked
            Task { await model.disconnect() }
        }
    }

    // MARK: Shared

    private func codeSignInRow(canStart: Bool, step: MarfaSettingsModel.SignInStep, identifier: String) -> some View {
        SettingsRow("Use a Code Instead", line: "From a device already signed in.") {
            SettingsButton("Enter Code…") { model.start(step) }
                .disabled(!canStart)
                .accessibilityIdentifier(identifier)
        }
    }

    private var signInProgress: some View {
        SettingsRow(
            model.code == nil ? "Working…" : "Waiting for Approval…",
            lead: .custom(AnyView(ProgressView().controlSize(.small)))
        ) {
            if model.canCancelSignIn {
                SettingsButton("Cancel") { model.cancelSignIn() }.accessibilityIdentifier("MarfaSignInCancel")
            }
        }
    }

    /// The two ways to sign in side by side, and Cancel while one waits on the person.
    private func signInButtons(
        title: LocalizedStringKey, canStart: Bool, browser: MarfaSettingsModel.SignInStep, code: MarfaSettingsModel.SignInStep,
        identifier: String
    ) -> some View {
        HStack(spacing: SettingsTokens.Metric.buttonGap) {
            if model.isWorking {
                ProgressView().controlSize(.small)
                if model.canCancelSignIn {
                    SettingsButton("Cancel") { model.cancelSignIn() }.accessibilityIdentifier("MarfaSignInCancel")
                }
            }
            SettingsButton("Use a Code Instead") { model.start(code) }
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
                name: Text("Approve This App with This Code"),
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

    @ViewBuilder private var noticeSection: some View {
        if let notice = model.notice {
            SettingsCard {
                SettingsProblemRow(title: Text(verbatim: notice.title), line: Text(verbatim: notice.message), actions: [])
                    .accessibilityIdentifier("MarfaNotice")
            }
        }
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
            SettingsRow(title: Text(verbatim: problem.copyText).monospaced(), size: .compact)
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
