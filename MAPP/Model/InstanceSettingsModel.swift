import Foundation
import Observation

/// What This Marfa shows and changes: the server's own settings, held as the person's draft beside the last answer
/// the server gave. Nothing is sent until Save, a save sends only the settings that differ from that answer, and
/// a shorter retention is sent only after the person has agreed to what it may remove. The server's answer is shown
/// after every save, and a refusal keeps what was typed.
@Observable @MainActor final class InstanceSettingsModel {
    /// The server to ask and a name for it, so a different server starts again from nothing.
    struct Target {
        let id: String
        let source: any InstanceConfigSource
    }

    /// A retention that may keep things for less time than the server does now, which the person agrees to before it
    /// is sent.
    struct Shortening: Hashable, Sendable {
        enum Change: Hashable, Sendable {
            /// The server holds `from` and the person typed the shorter `to`.
            case shorter(from: Int, to: Int)
            /// Nothing is set, so the server uses a default that a key can't read, and `to` may be shorter than it.
            case mayBeShorter(to: Int)
            /// The setting is removed, so a default that a key can't read replaces `from`.
            case toDefault(from: Int)
        }

        let setting: InstanceSetting
        let change: Change
    }

    struct Pending: Identifiable {
        let id = UUID()
        let patch: InstanceConfigPatch
        let shortenings: [Shortening]
    }

    typealias Provider = @MainActor () -> Target?

    private let provider: Provider
    /// Run after a name change is taken, so the rest of the app reads the new name.
    @ObservationIgnored var onRenamed: @MainActor () -> Void = {}

    /// The configuration as the server last gave it; nil until one has been read.
    private(set) var loaded: InstanceConfig?
    /// What each field shows. It starts as the server's answer and holds what the person typed.
    var draft: [InstanceSetting: String] = [:]
    private(set) var isLoading = false
    private(set) var isSaving = false
    /// Why the last read or save failed; cleared when one succeeds.
    private(set) var failure: InstanceConfigFailure?
    /// Settings found changed on the server since they were read, when a save was about to replace them.
    private(set) var elsewhere: [InstanceSetting] = []
    /// What the server answered for the settings the last save changed.
    private(set) var saved: [String] = []
    /// Another instance was found answering at this address when a save was about to reach it. Nothing was sent, and
    /// the page starts again from that instance's settings.
    private(set) var serverChanged = false
    /// Set while the person is asked to agree to a shorter retention.
    var pending: Pending?

    @ObservationIgnored private var targetID: String?
    @ObservationIgnored private var generation = 0

    init(provider: @escaping Provider) {
        self.provider = provider
    }

    // MARK: Reading

    /// Whether the settings can be shown and saved: they have been read, and the key may still manage them. A key
    /// that may not shows none, rather than fields that can't be saved, but what was typed is kept for when it may.
    var isAvailable: Bool { loaded != nil && failure != .notPermitted }

    /// Whether a server is set to ask at all.
    var hasServer: Bool { provider() != nil }

    /// Reads the settings. A draft the person has already edited is kept, and the fields they have not touched take
    /// the new answer.
    func load() async {
        guard let target = adopt(), !isLoading, !isSaving else { return }
        let generation = generation
        isLoading = true
        defer { if generation == self.generation { isLoading = false } }
        do {
            let config = try await target.source.read()
            guard generation == self.generation else { return }
            absorb(config)
            failure = nil
        } catch {
            guard generation == self.generation else { return }
            fail(error)
        }
    }

    /// Gives the draft the server's answer again, dropping what was typed.
    func revert() {
        guard let loaded else { return }
        for setting in InstanceSetting.allCases { draft[setting] = loaded.text(setting) }
        elsewhere = []
        saved = []
        serverChanged = false
        if case .refused? = failure { failure = nil }
    }

    // MARK: The draft

    func isEdited(_ setting: InstanceSetting) -> Bool {
        guard let loaded, let text = draft[setting] else { return false }
        return text != loaded.text(setting)
    }

    var hasEdits: Bool { InstanceSetting.allCases.contains(where: isEdited) }

    /// What is wrong with what was typed, by field. A window shorter than an earlier one is flagged only when both are
    /// typed; otherwise the server judges the order, since it counts its own defaults.
    var problems: [InstanceSetting: InstanceSettingProblem] {
        var found: [InstanceSetting: InstanceSettingProblem] = [:]
        var windows: [(InstanceSetting, Int)] = []
        for setting in InstanceSetting.allCases {
            switch setting.entry(from: text(setting)) {
            case .invalid(let problem): found[setting] = problem
            case .value(.number(let number)) where InstanceSetting.versionWindows.contains(setting):
                if let earlier = windows.first(where: { $0.1 > number }) {
                    found[setting] = .shorterThan(earlier.0)
                }
                windows.append((setting, number))
            default: break
            }
        }
        return found
    }

    /// Exactly what Save sends: the settings whose typed value differs from the server's, and the settings emptied so
    /// their defaults apply. Nil where nothing has been read.
    var patch: InstanceConfigPatch? {
        guard let loaded else { return nil }
        var patch = InstanceConfigPatch()
        for setting in InstanceSetting.allCases {
            switch setting.entry(from: text(setting)) {
            case .invalid: continue
            case .unset: if loaded.values[setting] != nil { patch.clear.insert(setting) }
            case .value(let value): if loaded.values[setting] != value { patch.values[setting] = value }
            }
        }
        return patch
    }

    var canSave: Bool {
        guard isAvailable, !isSaving, problems.isEmpty, let patch else { return false }
        return !patch.isEmpty
    }

    private func text(_ setting: InstanceSetting) -> String {
        draft[setting] ?? loaded?.text(setting) ?? ""
    }

    // MARK: Saving

    /// Sends the changes, or first asks the person to agree where one keeps things for less time.
    func save() async {
        guard canSave, let patch else { return }
        let shortenings = shortenings(of: patch)
        if shortenings.isEmpty {
            await send(patch)
        } else {
            pending = Pending(patch: patch, shortenings: shortenings)
        }
    }

    /// Sends what the person agreed to. It takes the question itself, since the dialog clears `pending` as it closes.
    func confirm(_ agreed: Pending) async {
        pending = nil
        await send(agreed.patch)
    }

    func cancelPending() {
        pending = nil
    }

    /// The retentions `patch` may make shorter. Only a value the server holds is compared with: an unset setting
    /// uses a default whoever runs the server may have changed and a key can't read, so a value typed for it asks
    /// unless nothing could keep more, and clearing a setting asks unless nothing could keep less.
    func shortenings(of patch: InstanceConfigPatch) -> [Shortening] {
        guard let loaded else { return [] }
        return InstanceSetting.allCases.compactMap { setting in
            guard patch.settings.contains(setting), setting.isNumber else { return nil }
            let held = loaded.number(setting)
            let change: Shortening.Change
            if case .number(let to)? = patch.values[setting] {
                if let held {
                    guard setting.keepsLonger(held, than: to) else { return nil }
                    change = .shorter(from: held, to: to)
                } else {
                    guard !setting.isUnlimited(to) else { return nil }
                    change = .mayBeShorter(to: to)
                }
            } else {
                guard let held, setting.keepsLonger(held, than: setting.shortestKept) else { return nil }
                change = .toDefault(from: held)
            }
            return Shortening(setting: setting, change: change)
        }
    }

    private func send(_ patch: InstanceConfigPatch) async {
        // A patch made for the server the page was reading is never sent to another one that has replaced it.
        let before = generation
        guard let target = adopt(), generation == before, !isSaving else { return }
        let generation = generation
        // The instance the person was shown, which the change is addressed to.
        let expected = loaded?.instanceID
        isSaving = true
        failure = nil
        elsewhere = []
        saved = []
        serverChanged = false
        defer { if generation == self.generation { isSaving = false } }
        do {
            // A setting changed elsewhere since it was read is shown, not replaced.
            let current = try await target.source.read()
            guard generation == self.generation else { return }
            if let expected, let now = current.instanceID, now != expected {
                await instanceChanged()
                return
            }
            let moved = InstanceSetting.allCases.filter { patch.settings.contains($0) && current.values[$0] != loaded?.values[$0] }
            absorb(current)
            guard moved.isEmpty else {
                elsewhere = moved
                return
            }
            let answer = try await target.source.update(patch, expecting: expected)
            guard generation == self.generation else { return }
            absorb(answer, resetting: patch.settings)
            saved = InstanceSetting.allCases.filter(patch.settings.contains).map {
                "\($0.title): \(InstanceWording.value(answer, $0))"
            }
            if patch.settings.contains(.name) { onRenamed() }
        } catch {
            guard generation == self.generation else { return }
            if error == .instanceChanged { await instanceChanged() } else { fail(error) }
        }
    }

    /// Starts again, as for any other server, from what the instance now answering at the address holds.
    private func instanceChanged() async {
        reset()
        serverChanged = true
        await load()
    }

    /// What the page says about settings found changed elsewhere, with the value the server holds now.
    var elsewhereMessage: String? {
        guard !elsewhere.isEmpty, let loaded else { return nil }
        let now = elsewhere.map { "\($0.title): \(InstanceWording.value(loaded, $0))" }.joined(separator: "; ")
        return String(localized: "These changed on the server since you opened this page: \(now). Nothing was sent. Check what you typed, then save again.")
    }

    // MARK: State

    private func adopt() -> Target? {
        let target = provider()
        if target?.id != targetID {
            reset()
            targetID = target?.id
        }
        return target
    }

    private func reset() {
        generation += 1
        loaded = nil
        draft = [:]
        failure = nil
        elsewhere = []
        saved = []
        serverChanged = false
        pending = nil
        isLoading = false
        isSaving = false
    }

    /// Takes the server's answer as the new base. A field the person edited keeps its text, except those named in
    /// `resetting`, which show what the server answered.
    private func absorb(_ config: InstanceConfig, resetting: Set<InstanceSetting> = []) {
        let edited = Set(InstanceSetting.allCases.filter(isEdited)).subtracting(resetting)
        loaded = config
        for setting in InstanceSetting.allCases where !edited.contains(setting) {
            draft[setting] = config.text(setting)
        }
    }

    private func fail(_ error: InstanceConfigFailure) {
        failure = error
    }
}

/// The words for a setting's value and for what a shorter retention may remove.
nonisolated enum InstanceWording {
    static func days(_ count: Int) -> String {
        String(localized: "\(count) days")
    }

    /// A number the server holds for a setting.
    static func amount(_ setting: InstanceSetting, _ number: Int) -> String {
        switch setting {
        case .versionMaxVersions: String(number)
        case .trashRetentionDays where number == 0: String(localized: "no limit")
        default: days(number)
        }
    }

    /// A setting's value as the server holds it, or its default where unset.
    static func value(_ config: InstanceConfig, _ setting: InstanceSetting) -> String {
        if setting == .name { return config.name ?? String(localized: "Marfa (default)") }
        if let number = config.number(setting) { return amount(setting, number) }
        if setting == .versionMaxVersions { return String(localized: "default, \(setting.documentedDefault ?? 0)") }
        return String(localized: "default, \(days(setting.documentedDefault ?? 0))")
    }

    /// What `shortening` may remove, in plain words. Where the server's current setting is not known, it says the
    /// change may remove items sooner than that setting.
    static func consequence(_ shortening: InstanceSettingsModel.Shortening) -> String {
        let setting = shortening.setting
        switch shortening.change {
        case .shorter(_, let to):
            return removal(setting, keeping: to)
        case .mayBeShorter(let to):
            return String(localized: "“\(setting.title)” may remove items sooner than the server’s current setting.") + " " + removal(setting, keeping: to)
        case .toDefault(let from):
            return String(localized: "Emptying “\(setting.title)” goes back to the server’s own default, which MAPP can’t read. That may remove items sooner than the server’s current setting, \(amount(setting, from)). What it removes can’t be recovered.")
        }
    }

    private static func removal(_ setting: InstanceSetting, keeping limit: Int) -> String {
        switch setting {
        case .trashRetentionDays:
            String(localized: "Items deleted more than \(days(limit)) ago will be removed for good, with their history, the next time the server tidies up. They can’t be recovered.")
        case .versionMaxVersions:
            String(localized: "An item with more than \(limit) versions will lose its oldest ones for good the next time the server tidies up.")
        default:
            String(localized: "“\(setting.title)” changes to \(days(limit)). Older versions of items may be removed for good the next time the server tidies up, so Version History will show fewer.")
        }
    }
}
