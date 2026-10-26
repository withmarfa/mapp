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

    /// A retention made shorter than the server shows now, which the person agrees to before it is sent.
    struct Shortening: Hashable, Sendable {
        let setting: InstanceSetting
        let from: Int
        let to: Int
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

    /// The configuration as the server last gave it; nil until one has been read, and again after the server
    /// refuses the key's permission.
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
    /// Set while the person is asked to agree to a shorter retention.
    var pending: Pending?

    @ObservationIgnored private var targetID: String?
    @ObservationIgnored private var generation = 0

    init(provider: @escaping Provider) {
        self.provider = provider
    }

    // MARK: Reading

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
        guard loaded != nil, !isSaving, problems.isEmpty, let patch else { return false }
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

    /// The retentions `patch` makes shorter, against what the page shows now: the value set, else the documented default.
    func shortenings(of patch: InstanceConfigPatch) -> [Shortening] {
        guard let loaded else { return [] }
        return InstanceSetting.allCases.compactMap { setting in
            guard patch.settings.contains(setting), setting.isNumber, let from = loaded.effectiveNumber(setting) else { return nil }
            let to: Int?
            if case .number(let number)? = patch.values[setting] { to = number } else { to = setting.documentedDefault }
            guard let to, setting.keepsLonger(from, than: to) else { return nil }
            return Shortening(setting: setting, from: from, to: to)
        }
    }

    private func send(_ patch: InstanceConfigPatch) async {
        guard let target = adopt(), !isSaving else { return }
        let generation = generation
        isSaving = true
        failure = nil
        elsewhere = []
        saved = []
        defer { if generation == self.generation { isSaving = false } }
        do {
            // A setting changed elsewhere since it was read is shown, not replaced.
            let current = try await target.source.read()
            guard generation == self.generation else { return }
            let moved = InstanceSetting.allCases.filter { patch.settings.contains($0) && current.values[$0] != loaded?.values[$0] }
            absorb(current)
            guard moved.isEmpty else {
                elsewhere = moved
                return
            }
            let answer = try await target.source.update(patch)
            guard generation == self.generation else { return }
            absorb(answer, resetting: patch.settings)
            saved = InstanceSetting.allCases.filter(patch.settings.contains).map {
                "\($0.title): \(InstanceWording.value(answer, $0))"
            }
            if patch.settings.contains(.name) { onRenamed() }
        } catch {
            guard generation == self.generation else { return }
            fail(error)
        }
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
        // A key that may no longer manage the settings shows none, rather than fields that can't be saved.
        if error == .notPermitted { loaded = nil }
    }
}

/// The words for a setting's value and for what a shorter retention may remove.
nonisolated enum InstanceWording {
    static func days(_ count: Int) -> String {
        String(localized: "\(count) days")
    }

    /// A setting's value as the server holds it, or its default where unset.
    static func value(_ config: InstanceConfig, _ setting: InstanceSetting) -> String {
        switch setting {
        case .name:
            config.name ?? String(localized: "Marfa (default)")
        case .versionMaxVersions:
            config.number(setting).map { String($0) } ?? String(localized: "default, \(setting.documentedDefault ?? 0)")
        case .trashRetentionDays:
            switch config.number(setting) {
            case 0?: String(localized: "no limit")
            case let count?: days(count)
            case nil: String(localized: "default, \(days(setting.documentedDefault ?? 0))")
            }
        default:
            config.number(setting).map(days) ?? String(localized: "default, \(days(setting.documentedDefault ?? 0))")
        }
    }

    /// What `shortening` may remove, in plain words.
    static func consequence(_ shortening: InstanceSettingsModel.Shortening) -> String {
        switch shortening.setting {
        case .trashRetentionDays:
            String(localized: "Items deleted more than \(days(shortening.to)) ago will be removed for good, with their history, the next time the server tidies up. They can’t be recovered.")
        case .versionMaxVersions:
            String(localized: "An item with more than \(shortening.to) versions will lose its oldest ones for good the next time the server tidies up.")
        default:
            String(localized: "“\(shortening.setting.title)” changes to \(days(shortening.to)). Older versions of items may be removed for good the next time the server tidies up, so Version History will show fewer.")
        }
    }
}
