import Foundation
import Marfa
import Observation

/// The Connectors page: each installed plugin's connector, how it stands and which machine runs it, and a page for each with
/// Pause and Resume, Run Now, its settings, what it brings and, for one that declares it, its vendor sign-in. Pause, Resume
/// and Run Now are choices the server stores, which the connector follows at its next run; this page never starts a run.
@Observable @MainActor final class ConnectorsModel: OwnerDraftHolding {
    /// An installed connector and what has been read about it. A part not read yet, or not readable, is nil.
    struct Entry: Identifiable, Equatable {
        var summary: PluginConnectorSummary
        var control: ConnectorControl?
        var registration: ConnectorRegistration?
        var settings: ConnectorSettingsReading?

        var id: String { summary.name }
    }

    /// A change waiting on the owner's answer.
    struct Question: Identifiable, Equatable {
        enum Change: Equatable {
            case removeSecret(setting: String)
            /// Taking the connector off its machine.
            case noMachine
        }

        let id = UUID()
        let plugin: String
        let change: Change
        let title: String
        let message: String
        let confirm: String
    }

    /// The sheet that sets or changes a secret.
    struct SecretSheet: Equatable {
        let plugin: String
        let setting: String
        let label: String
        /// Set, or set and unreadable, so it can be removed.
        let hasValue: Bool
    }

    private let context: OwnerContext

    private(set) var entries: [Entry] = []
    private(set) var hosts: [ConnectorHostInfo] = []
    private(set) var typeNames: [String: String] = [:]
    private let loader = OwnerLoader()
    var failure: OwnerFailure? { loader.failure }
    private let hostsRead = OwnerLoader.ReadStatus()
    var hostsFailure: OwnerFailure? { hostsRead.failure }
    var hasLoaded: Bool { loader.hasLoaded }
    /// One line under a connector's rows whose change was refused, by the plugin's name.
    private(set) var rowErrors: [String: OwnerFailure] = [:]
    /// One line under a setting whose change was refused, by `plugin/setting`.
    private(set) var settingErrors: [String: String] = [:]
    /// The plugins with a change under way, so a second tap waits.
    private(set) var working: Set<String> = []
    /// The plugin whose sign-in is open in the system's sheet.
    private(set) var signingIn: String?
    /// Why a sign-in did not start or finish, by the plugin's name.
    private(set) var signInProblems: [String: String] = [:]
    /// What was typed into a setting's field and not sent, by `plugin/setting`.
    var drafts: [String: String] = [:]
    var question: Question?
    var sheet: SecretSheet?
    /// What was typed in the secret sheet. Held only while the sheet is open, never handed over.
    var secretDraft = ""
    private(set) var secretError: String?
    private(set) var isSavingSecret = false
    /// The plugins found gone while their page was open.
    private(set) var gone: Set<String> = []
    /// Add a Connector, while its sheet is open.
    private(set) var adding: AddConnectorModel?

    init(context: OwnerContext) {
        self.context = context
    }

    func entry(_ plugin: String) -> Entry? { entries.first { $0.id == plugin } }

    private func index(_ plugin: String) -> Int? { entries.firstIndex { $0.id == plugin } }

    func host(_ id: String?) -> ConnectorHostInfo? { id.flatMap { id in hosts.first { $0.id == id } } }

    func hostName(of entry: Entry) -> String? { host(hostID(of: entry))?.name }

    /// The machine a connector is assigned to, as last read: its own state once read, which says nil for no machine, else
    /// the list's.
    func hostID(of entry: Entry) -> String? {
        if let control = entry.control { return control.host }
        return entry.summary.hostID
    }

    func health(of entry: Entry, now: Date = .now) -> ConnectorHealth {
        if entry.control?.host != nil, hostsFailure != nil { return .unread }
        return ConnectorHealth.of(
            control: entry.control, registration: entry.registration, settings: entry.settings,
            host: host(entry.control?.host), now: now)
    }

    /// The labels of an entry's settings by name, for a line that names the settings it needs.
    func labels(of entry: Entry) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (entry.settings?.settings ?? []).map { ($0.name, $0.label) })
    }

    /// The label of a type, or its id where the Marfa has no name for it.
    func typeName(_ id: String) -> String { typeNames[id] ?? id }

    // MARK: Reading

    /// Reads the list, which the page shows at once, then each connector's own state, a few at a time.
    func load() async {
        await loader.load(in: context, primary: { () throws(OwnerFailure) in
            let found = try await context.calls.connectorPlugins()
            entries = found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.map { summary in
                let held = entry(summary.name)
                return Entry(summary: summary, control: held?.control, registration: held?.registration, settings: held?.settings)
            }
            gone = gone.filter { name in entries.contains { $0.id == name } }
        }, secondary: [
            readHosts,
            .quiet { [self] () throws(OwnerFailure) in typeNames = try await context.calls.typeNames() },
        ], after: {
            let calls = context.calls
            await readEach(
                of: entries.map(\.id),
                read: { name in await Self.read(name, with: calls) },
                take: { name, read in take(read, for: name) })
        })
    }

    private var readHosts: OwnerLoader.Secondary {
        .required(hostsRead) { () throws(OwnerFailure) in self.hosts = try await self.context.calls.connectorHosts() }
    }

    /// Reads one connector again, such as after a change or when its page opens.
    func reload(_ plugin: String) async {
        let calls = context.calls
        take(await Self.read(plugin, with: calls), for: plugin)
        await loader.read(readHosts, in: context)
    }

    private struct Read: Sendable {
        var control: ConnectorControl?
        var registration: ConnectorRegistration?
        var settings: ConnectorSettingsReading?
        var failure: OwnerFailure?
    }

    private nonisolated static func read(_ plugin: String, with calls: any OwnerCalls) async -> Read {
        var read = Read()
        do {
            read.control = try await calls.connectorControl(of: plugin)
            if let registration = read.control?.registration { read.registration = try? await calls.connectorRegistration(registration) }
            read.settings = try await calls.connectorSettings(of: plugin)
        } catch {
            read.failure = error
        }
        return read
    }

    private func take(_ read: Read, for plugin: String) {
        guard let index = index(plugin) else { return }
        if let failure = read.failure {
            if failure == .notFound { markGone(plugin) }
            Task { await context.learn(from: failure) }
            return
        }
        entries[index].control = read.control
        entries[index].registration = read.registration
        entries[index].settings = read.settings
    }

    private func markGone(_ plugin: String) {
        gone.insert(plugin)
        entries.removeAll { $0.id == plugin }
    }

    func isGone(_ plugin: String) -> Bool { gone.contains(plugin) }

    // MARK: What the owner chooses

    private func change(_ plugin: String, _ call: (any OwnerCalls) async throws(OwnerFailure) -> ConnectorControl) async {
        guard !working.contains(plugin), let index = index(plugin) else { return }
        working.insert(plugin)
        defer { working.remove(plugin) }
        rowErrors[plugin] = nil
        do {
            entries[index].control = try await call(context.calls)
        } catch {
            rowErrors[plugin] = error
            if error == .notFound { markGone(plugin) }
            await context.learn(from: error)
        }
    }

    func setPaused(_ paused: Bool, for plugin: String) async {
        await change(plugin) { calls throws(OwnerFailure) in
            paused ? try await calls.pauseConnector(plugin) : try await calls.resumeConnector(plugin)
        }
    }

    /// Re-reads after a paused refusal so the owner can resume a connector that was paused elsewhere.
    func runNow(_ plugin: String) async {
        await change(plugin) { calls throws(OwnerFailure) in try await calls.runConnector(plugin) }
        if rowErrors[plugin] == nil || rowErrors[plugin] == .connectorPaused { await reload(plugin) }
    }

    /// While a run is asked for, reads the connector again until the server clears the request, which it does when the
    /// connector reports the run, not when it starts. A run that outlasts `attempts` reads keeps "Run requested" until the page
    /// is read again. It also stops when the page that called it closes.
    func followRun(_ plugin: String, every interval: Duration = .seconds(5), attempts: Int = 18) async {
        for _ in 0..<attempts {
            guard entry(plugin)?.control?.runRequested != nil else { return }
            try? await Task.sleep(for: interval)
            if Task.isCancelled { return }
            await reload(plugin)
        }
    }

    /// Moves a connector to another machine, or to none with nil.
    func assign(_ plugin: String, toHost host: String?) async {
        guard !working.contains(plugin), let entry = entry(plugin), hostID(of: entry) != host else { return }
        working.insert(plugin)
        defer { working.remove(plugin) }
        rowErrors[plugin] = nil
        do {
            try await context.calls.assignConnector(plugin, toHost: host)
        } catch {
            rowErrors[plugin] = error
            if error == .notFound { markGone(plugin) }
            await context.learn(from: error)
            return
        }
        // Shown at once, so the machine it left never stands in for it while it is read again.
        if let index = index(plugin) {
            entries[index].control?.host = host
            entries[index].summary.hostID = host
        }
        await reload(plugin)
    }

    /// No Machine: a connector that is running stops until a machine is chosen, so the owner is asked first; one paused is
    /// moved at once. Whether it runs is read again first, so one another app resumed since is asked about; where that read
    /// fails, the owner is asked.
    func chooseNoMachine(for plugin: String) async {
        guard !working.contains(plugin), let held = entry(plugin), hostID(of: held) != nil else { return }
        working.insert(plugin)
        var paused = false
        do {
            let fresh = try await context.calls.connectorControl(of: plugin)
            if let index = index(plugin) { entries[index].control = fresh }
            paused = fresh.paused
        } catch {
            if error == .notFound { markGone(plugin) }
            await context.learn(from: error)
        }
        working.remove(plugin)
        guard let entry = entry(plugin), let host = hostID(of: entry) else { return }
        if paused {
            await assign(plugin, toHost: nil)
            return
        }
        let title = entry.summary.title
        let machine = self.host(host)?.name
        question = Question(
            plugin: plugin, change: .noMachine,
            title: machine.map { String(localized: "Take \(title) off “\($0)”?") } ?? String(localized: "Take \(title) off its machine?"),
            message: String(localized: "It stops running until you choose a machine for it. Its settings and mapping are kept."),
            confirm: String(localized: "Take Off"))
    }

    // MARK: Add a Connector

    /// The installed connectors no machine runs, which Add a Connector offers.
    var unplaced: [PluginConnectorSummary] { entries.filter { hostID(of: $0) == nil }.map(\.summary) }

    func beginAdding() {
        guard !unplaced.isEmpty else { return }
        adding = AddConnectorModel(context: context, candidates: unplaced, hosts: hosts) { [weak self] plugin in
            guard let self else { return }
            // A connector put on a machine already linked needs nothing more, so the sheet closes.
            if let adding = self.adding, adding.placed == nil { self.adding = nil }
            await self.reload(plugin)
        }
    }

    /// Closes Add a Connector; the link it showed goes with it.
    func closeAdding() {
        guard adding?.isWorking != true else { return }
        adding?.close()
        adding = nil
    }

    // MARK: Settings

    static func key(_ plugin: String, _ setting: String) -> String { plugin + "/" + setting }

    /// The text a setting's field shows: what was typed, or the value set, or the default.
    func text(of setting: ConnectorSetting, in plugin: String) -> String {
        if let typed = drafts[Self.key(plugin, setting.name)] { return typed }
        return Self.text(setting.value)
    }

    static func text(_ value: ConnectorSettingValue?) -> String {
        switch value {
        case .text(let text)?: text
        case .number(let number)?: number.formatted(.number.grouping(.never))
        case .flag(let flag)?: flag ? "true" : "false"
        case nil: ""
        }
    }

    /// Whether a setting's field holds what the owner typed and did not send.
    func isEdited(_ setting: ConnectorSetting, in plugin: String) -> Bool {
        guard let typed = drafts[Self.key(plugin, setting.name)] else { return false }
        return typed.trimmingCharacters(in: .whitespacesAndNewlines) != Self.text(setting.value)
    }

    /// Sends what a text or number field holds. Empty takes the value away, so the default applies. A refusal keeps what was
    /// typed.
    func commit(_ setting: ConnectorSetting, in plugin: String) async {
        let key = Self.key(plugin, setting.name)
        guard isEdited(setting, in: plugin), let typed = drafts[key] else {
            drafts[key] = nil
            return
        }
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let change: ConnectorSettingChange
        if trimmed.isEmpty {
            change = .clear
        } else if setting.kind == .number {
            guard let number = try? Double(trimmed, format: .number) else {
                settingErrors[key] = String(localized: "Enter a number.")
                return
            }
            change = .set(.number(number))
        } else {
            change = .set(.text(trimmed))
        }
        if await send(change, for: setting, in: plugin) { drafts[key] = nil }
    }

    func set(_ value: ConnectorSettingValue?, for setting: ConnectorSetting, in plugin: String) async {
        _ = await send(value.map { .set($0) } ?? .clear, for: setting, in: plugin)
    }

    /// Sends one setting and takes every setting as the server now holds them, so what is missing is told as it is now.
    private func send(_ change: ConnectorSettingChange, for setting: ConnectorSetting, in plugin: String) async -> Bool {
        let key = Self.key(plugin, setting.name)
        settingErrors[key] = nil
        do {
            let reading = try await context.calls.changeConnectorSettings(of: plugin, [setting.name: change])
            if let index = index(plugin) { entries[index].settings = reading }
            return true
        } catch {
            settingErrors[key] = OwnerWording.line(error)
            if error == .notFound { markGone(plugin) }
            await context.learn(from: error)
            return false
        }
    }

    // MARK: Secrets

    func beginSecret(_ setting: ConnectorSetting, in plugin: String) {
        secretDraft = ""
        secretError = nil
        sheet = SecretSheet(plugin: plugin, setting: setting.name, label: setting.label, hasValue: setting.isSet || setting.unreadable)
    }

    var canSaveSecret: Bool { !secretDraft.isEmpty && !isSavingSecret }

    func saveSecret() async {
        guard let sheet, canSaveSecret else { return }
        isSavingSecret = true
        do {
            let reading = try await context.calls.changeConnectorSettings(of: sheet.plugin, [sheet.setting: .set(.text(secretDraft))])
            if let index = index(sheet.plugin) { entries[index].settings = reading }
            isSavingSecret = false
            closeSheet()
        } catch {
            isSavingSecret = false
            secretError = OwnerWording.line(error)
            await context.learn(from: error)
        }
    }

    /// Closes the sheet and drops what was typed in it.
    func closeSheet() {
        guard !isSavingSecret else { return }
        sheet = nil
        secretDraft = ""
        secretError = nil
    }

    /// Remove… in the secret's sheet: the sheet closes and the owner is asked.
    func askToRemoveSecret() {
        guard let sheet, sheet.hasValue, !isSavingSecret else { return }
        closeSheet()
        question = Question(
            plugin: sheet.plugin, change: .removeSecret(setting: sheet.setting), title: String(localized: "Remove “\(sheet.label)”?"),
            message: String(localized: "The connector doesn’t have it at its next run. To use it again, you type it again."),
            confirm: String(localized: "Remove"))
    }

    func cancelQuestion() { question = nil }

    func confirm(_ asked: Question) async {
        question = nil
        switch asked.change {
        case .removeSecret(let name):
            guard let setting = entry(asked.plugin)?.settings?.settings.first(where: { $0.name == name }) else { return }
            _ = await send(.clear, for: setting, in: asked.plugin)
        case .noMachine:
            await assign(asked.plugin, toHost: nil)
        }
    }

    // MARK: Vendor sign-in

    /// Starts the sign-in, shows the address in the system's sheet, then reads how it ended. Nothing the provider said is
    /// shown: the server gives one outcome word, which `ConnectorWording.signInFailure` puts into words.
    func signIn(
        _ plugin: String, returningTo address: String, show: (URL) async -> Bool
    ) async {
        guard signingIn == nil, let entry = entry(plugin), let declared = entry.summary.signIn else { return }
        signingIn = plugin
        defer { signingIn = nil }
        signInProblems[plugin] = nil
        let provider = ConnectorWording.provider(declared.provider)
        let start: ConnectorSignInStart
        do {
            start = try await context.calls.startConnectorSignIn(of: plugin, returningTo: address)
        } catch {
            if case .signInNeeds(let names) = error {
                let labels = labels(of: entry)
                signInProblems[plugin] = ConnectorWording.signInNeeds(names.map { labels[$0] ?? $0 })
            } else {
                signInProblems[plugin] = OwnerWording.line(error)
            }
            await context.learn(from: error)
            return
        }
        _ = await show(start.address)
        do {
            let reading = try await context.calls.connectorSignInStatus(of: plugin)
            // A later start, from another window or another app, replaced this sign-in: its outcome is not this one's.
            if reading.id != start.id {
                signInProblems[plugin] = ConnectorWording.signInFailure(nil, provider: provider)
            } else {
                switch reading.status {
                case .signedIn: break
                case .failed(let reason): signInProblems[plugin] = ConnectorWording.signInFailure(reason, provider: provider)
                case .none, .pending, .expired: signInProblems[plugin] = ConnectorWording.signInFailure(nil, provider: provider)
                }
            }
        } catch {
            signInProblems[plugin] = OwnerWording.line(error)
        }
        await reload(plugin)
    }

    /// Whether a connector holds the token its sign-in gets: the setting `tokenSetting` names has a value.
    func isSignedIn(_ entry: Entry) -> Bool {
        guard let declared = entry.summary.signIn else { return false }
        return entry.settings?.settings.first { $0.name == declared.tokenSetting }?.isSet ?? false
    }

    /// The settings the page draws: what the sign-in sets is shown as the sign-in instead.
    func shownSettings(of entry: Entry) -> [ConnectorSetting] {
        let hidden = entry.summary.signIn?.tokenSetting
        return (entry.settings?.settings ?? []).filter { $0.name != hidden }
    }

    // MARK: Closing

    /// What was typed in a setting's field and not sent, which the app gives back when Settings closes. A secret typed in its
    /// sheet is dropped, never handed over, and so is a machine's link: only that it can't be shown again is told.
    func takeDrafts() -> [OwnerDraft] {
        defer {
            drafts = [:]
            sheet = nil
            secretDraft = ""
            secretError = nil
            adding = nil
        }
        var typed: [OwnerDraft] = adding?.takeDrafts() ?? []
        for entry in entries {
            for setting in entry.settings?.settings ?? [] where !setting.secret && isEdited(setting, in: entry.id) {
                let text = drafts[Self.key(entry.id, setting.name)] ?? ""
                typed.append(.typed(title: String(localized: "\(setting.label) Not Saved"), text: text))
            }
        }
        return typed
    }
}
