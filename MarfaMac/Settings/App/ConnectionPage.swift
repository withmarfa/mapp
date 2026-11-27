import AppKit
import SwiftUI

/// The configured Marfa, its sign-in and this Mac’s copy, or the entry to sign in.
struct ConnectionPage: View {
    let settingsHost: AppSettingsHost
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library
    @Environment(\.settingsNavigation) private var navigation
    @Environment(\.colorScheme) private var colorScheme
    @State private var isChoosingOther = false
    /// The owner's name and the server it was read from, kept while that server does not answer.
    @State private var accountName: String?
    @State private var accountNameServer: MarfaConnection?

    private var host: MarfaHost { libraries.host }
    private var model: MarfaSettingsModel { libraries.marfaSettings }

    var body: some View {
        Group {
            if let connection = host.configuredConnection {
                SettingsPageColumn {
                    connected(to: connection)
                    codeSection
                    noticeSection
                    ConnectionCopySections()
                        .id(connection)
                    let hasOtherMarfas = host.hasOtherMarfas(besides: connection)
                    if hasOtherMarfas || isChoosingOther { otherServer(hasOtherMarfas: hasOtherMarfas) }
                    disconnect
                }
            } else {
                disconnected
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ConnectionPage")
        .settingsSheet(presenting: model.showsConnectSheet && host.configuredConnection == nil, dismiss: dismissConnect) {
            ConnectToMarfaSheet(model: model, dismiss: dismissConnect)
        }
        .onDisappear { model.closeConnectSheet() }
        .task(id: NameRequest(connection: host.configuredConnection, isOnline: host.state == .online, readsProfile: host.readsProfile)) {
            if accountNameServer != host.configuredConnection {
                accountName = nil
                accountNameServer = host.configuredConnection
                isChoosingOther = false
            }
            if host.configuredConnection != nil { model.showsConnectSheet = false }
            guard let connection = host.configuredConnection, host.state == .online else { return }
            let name = host.readsProfile ? await MarfaServerCalls(connection: connection, signIns: host.signIns).ownerName() : nil
            if !Task.isCancelled, host.configuredConnection == connection { accountName = name }
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
        VStack(spacing: 0) {
            if host.unusableAddress != nil || (model.notice != nil && !model.showsConnectSheet) {
                SettingsPageColumn(scrolls: false) {
                    if let address = host.unusableAddress {
                        SettingsCard {
                            SettingsProblemRow(
                                title: Text("Change the Saved Address"), line: Text(verbatim: Words.savedAddressHasMore(address)),
                                actions: [])
                                .accessibilityIdentifier("MarfaSavedAddressNeedsChange")
                        }
                    }
                    if !model.showsConnectSheet { noticeSection }
                }
            }
            Group {
                if !model.showsConnectSheet {
                    VStack(spacing: SettingsTokens.Metric.State.spacing) {
                        Text("Not Signed In").settingsFont(.stateTitle).accessibilityAddTraits(.isHeader)
                        Text("Sign in to your Marfa to open your library.")
                            .settingsFont(.small)
                            .foregroundStyle(SettingsTokens.secondaryText)
                        SettingsButton("Sign In", role: .confirm) { model.showsConnectSheet = true }
                            .padding(.top, SettingsTokens.Metric.State.actionGap)
                            .accessibilityIdentifier("MarfaOpenConnect")
                    }
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, SettingsTokens.Metric.pageSide)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SettingsTokens.page)
    }

    private func dismissConnect() {
        if model.isWorking { model.cancelSignIn() }
        else { model.closeConnectSheet() }
    }

    // MARK: Connected

    @ViewBuilder private func connected(to connection: MarfaConnection) -> some View {
        let account = ConnectionAccount(
            state: host.state, grants: host.grants, grantsRead: host.grantsRead, readsProfile: host.readsProfile,
            lacksAsked: host.lacksAsked, waiting: host.waitingChanges)
        let status = ConnectionAddressStatus(state: host.state, updateReady: settingsHost.overview.updateReady != nil)
        SettingsSection("Marfa") {
            SettingsRow("Address") {
                HStack(spacing: SettingsTokens.Metric.buttonGap) {
                    SettingsValue(verbatim: SettingsWording.hostName(of: connection.address), glyph: .link)
                        .help(Text(verbatim: connection.address.absoluteString))
                    statusMark(status)
                }
            }
            .accessibilityIdentifier("LibrarySummary")
            .contextMenu {
                Button("Use Another Marfa…") { isChoosingOther = true }
            }
            if account.showsName {
                let page = SettingsPage.account
                SettingsLinkRow(
                    verbatim: String(localized: "Signed in as"), line: account.nameLine, lead: accountTile(symbol: page.symbol),
                    value: (accountNameServer == connection ? accountName : nil) ?? settingsHost.overview.owner, lines: nil
                ) { navigation?.show(page) }
                .accessibilityIdentifier("SignedInAs")
            }
            if let value = account.permissionsValue {
                SettingsRow(verbatim: String(localized: "Permissions"), line: account.permissionsLine, lines: nil) {
                    HStack(spacing: SettingsTokens.Metric.buttonGap) {
                        SettingsValue(verbatim: value)
                        if account.offersMore {
                            SettingsButton(settingsHost.isAllowingMore ? "Waiting…" : "Allow More…") {
                                Task { _ = await settingsHost.allowMore(ConnectionAccount.asked) }
                            }
                            .disabled(model.isWorking || settingsHost.isAllowingMore)
                            .accessibilityIdentifier("AllowMore")
                        }
                    }
                }
                .accessibilityIdentifier("ConnectionPermissions")
            }
            SettingsRow(title: Text("Unsent changes"), line: account.unsentLine.map { Text(verbatim: $0) }) {
                SettingsValue(verbatim: account.unsent)
            }
            connectionActions
        }
        .accessibilityIdentifier("ConnectionAccount")
        if FillWording.shows(library?.syncReport.fill, in: host.state), let fill = library?.syncReport.fill {
            SettingsNote(verbatim: String(localized: "Downloading library… \(FillWording.line(fill))"))
                .monospacedDigit()
                .accessibilityIdentifier("LibraryFillProgress")
        }
        if library != nil, !host.report.problems.isEmpty {
            SettingsSection("Problems", footer: "Until you decide, these changes stay on this Mac.") {
                ForEach(host.report.problems) { problem in
                    ConnectionProblem(problem: problem, isOnline: host.state == .online)
                }
            }
        }
    }

    private func accountTile(symbol: String) -> SettingsLead {
        let size = SettingsTokens.Metric.tile
        return .custom(AnyView(
            RoundedRectangle(cornerRadius: size * SettingsTokens.Metric.tileRounding)
                .fill(colorScheme == .dark ? SettingsTokens.accountLinkIndigoDark : SettingsTokens.accountLinkIndigo)
                .frame(width: size, height: size)
                .overlay { SettingsTileGlyph(symbol: symbol, tileSize: size).foregroundStyle(SettingsTokens.tileForeground) }
                .accessibilityHidden(true)
        ))
    }

    private func statusMark(_ status: ConnectionAddressStatus) -> some View {
        let color = switch status.tone {
        case .green: SettingsTokens.ok
        case .orange: SettingsTokens.warning
        case .red: SettingsTokens.errorRed
        }
        let words = Text(verbatim: status.words)
        return Image(systemName: status.symbol)
            .font(.system(size: SettingsTokens.Metric.statusMark, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(status.tone == .green ? color : SettingsTokens.tileForeground, color)
            .fixedSize()
            .help(words)
            .accessibilityLabel(words)
    }

    @ViewBuilder private var connectionActions: some View {
        switch host.state {
        case .keyRefused:
            SettingsRow("Sign in again", line: "This Mac’s copy is kept.") {
                signInButtons(
                    title: "Sign In…", canStart: !model.isWorking, browser: .signInAgain(usingCode: false),
                    code: .signInAgain(usingCode: true), identifier: "MarfaSignInAgain")
            }
        case .offline:
            SettingsRow(title: Text("Not answering"), line: model.status.detail.map { Text(verbatim: $0) }, lines: nil) {
                SettingsButton("Try Again") { host.refresh() }.accessibilityIdentifier("MarfaTryAgain")
            }
        case .unavailable, .otherVersion, .inUse:
            SettingsProblemRow(
                title: Text(verbatim: model.status.title), line: model.status.detail.map { Text(verbatim: $0) }, actions: [])
        case .disconnected, .connecting, .online:
            EmptyView()
        }
    }

    private func otherServer(hasOtherMarfas: Bool) -> some View {
        SettingsSection(name: hasOtherMarfas ? Text("Other Marfas") : nil) {
            SettingsRow("Use another Marfa", line: "The app shows one Marfa at a time.") {
                SettingsButton(isChoosingOther ? "Hide" : "Choose…") { isChoosingOther.toggle() }
            }
            if isChoosingOther {
                SettingsRow("Address", line: "Each Marfa has its own copy on this Mac.") {
                    SettingsField(title: "Address", text: Bindable(model).otherAddress)
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("MarfaOtherAddress")
                }
                SettingsRow("Sign in and switch") {
                    SettingsButton("Sign In and Switch…") { model.start(.switchServer(usingCode: false)) }
                        .disabled(!model.canSwitch)
                        .accessibilityIdentifier("MarfaSwitch")
                }
                codeSignInRow(canStart: model.canSwitch, step: .switchServer(usingCode: true), identifier: "MarfaSwitchCode")
                if model.isWorking { signInProgress }
            }
        }
    }

    private var disconnect: some View {
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
            ConnectionCodeSection(code: code)
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

private extension SettingsTokens {
    static let accountLinkIndigo = Color(red: 88 / 255, green: 86 / 255, blue: 214 / 255)
    static let accountLinkIndigoDark = Color(red: 125 / 255, green: 122 / 255, blue: 1)
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
