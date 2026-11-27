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

    /// A retention that may keep things for less time than the server does now, or a reserve of free disk that may be
    /// smaller, which the person agrees to before it is sent.
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
        var revertsOnFailure = false
    }

    typealias Provider = @MainActor () -> Target?

    private let provider: Provider
    /// Run after a save is taken, with the server's answer and the settings it changed, so the rest of the app reads
    /// the new name and the bin's new retention.
    @ObservationIgnored var onSaved: @MainActor (InstanceConfig, Set<InstanceSetting>, String) -> Void = { _, _, _ in }

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

    /// The settings of a change agreed to or being sent, marked before the call so nothing in between counts them as unsent.
    @ObservationIgnored private var sending: Set<InstanceSetting> = []
    @ObservationIgnored private var targetID: String?
    @ObservationIgnored private var generation = 0

    init(provider: @escaping Provider) {
        self.provider = provider
    }

    // MARK: Reading

    /// Whether the settings can be shown and saved: they have been read, and the key may still manage them. A key
    /// that may not shows none, rather than fields that can't be saved, but what was typed is kept for when it may.
    var isAvailable: Bool { loaded != nil && failure != .notPermitted }

    /// Reads the settings. A draft the person has already edited is kept, and the fields they have not touched take
    /// the new answer.
    func load() async {
        guard let target = adopt() else {
            failure = .unsupported
            return
        }
        guard !isLoading, !isSaving else { return }
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
            switch error {
            case .failed(let detail), .refused(let detail): OwnerSettingsLog.failure(detail)
            default: break
            }
            fail(error)
        }
    }

    /// Gives the draft the server's answer again, dropping what was typed and any question about it. A change already on its
    /// way keeps its text until the server answers, so a refusal can still show it.
    func revert() {
        pending = nil
        guard let loaded else { return }
        for setting in InstanceSetting.allCases where !sending.contains(setting) { draft[setting] = loaded.text(setting) }
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

    /// What was typed and is not on its way to the server: a change already agreed and being sent is not among it, so
    /// closing Settings then does not report it as not saved. A change the server refuses is unsent again.
    var hasUnsentEdits: Bool { InstanceSetting.allCases.contains(where: isUnsent) }

    func isUnsent(_ setting: InstanceSetting) -> Bool { isEdited(setting) && !sending.contains(setting) }

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
    var patch: InstanceConfigPatch? { patch(for: Set(InstanceSetting.allCases)) }

    /// What a save of `settings` alone sends: a page changes only the settings it shows, whatever another page holds typed.
    func patch(for settings: Set<InstanceSetting>) -> InstanceConfigPatch? {
        guard let loaded else { return nil }
        var patch = InstanceConfigPatch()
        for setting in InstanceSetting.allCases where settings.contains(setting) {
            switch setting.entry(from: text(setting)) {
            case .invalid: continue
            case .unset: if loaded.values[setting] != nil { patch.clear.insert(setting) }
            case .value(let value): if loaded.values[setting] != value { patch.values[setting] = value }
            }
        }
        return patch
    }

    var canSave: Bool { canSave(Set(InstanceSetting.allCases)) }

    /// Whether `settings` can be sent: what they hold is valid, differs from the server's, and nothing is being sent.
    func canSave(_ settings: Set<InstanceSetting>) -> Bool {
        guard isAvailable, !isSaving, pending == nil, sending.isDisjoint(with: settings), let patch = patch(for: settings), !patch.isEmpty else { return false }
        return problems.keys.allSatisfy { !settings.contains($0) }
    }

    private func text(_ setting: InstanceSetting) -> String {
        draft[setting] ?? loaded?.text(setting) ?? ""
    }

    // MARK: Saving

    /// Sends the changes, or first asks the person to agree where one keeps things for less time.
    func save() async { await save(Set(InstanceSetting.allCases)) }

    /// Sends the changes to `settings` alone. While a question is open, or a change is on its way, it does nothing.
    func save(_ settings: Set<InstanceSetting>, revertsOnFailure: Bool = false) async {
        guard canSave(settings), let patch = patch(for: settings) else { return }
        let shortenings = shortenings(of: patch)
        if shortenings.isEmpty {
            await send(patch, revertsOnFailure: revertsOnFailure)
        } else {
            pending = Pending(patch: patch, shortenings: shortenings, revertsOnFailure: revertsOnFailure)
        }
    }

    /// Sends what the person agreed to. It takes the question itself, since the dialog clears `pending` as it closes.
    func confirm(_ agreed: Pending) async {
        await agree(agreed).value
    }

    /// Takes the agreement at once, so closing the dialog does not put the fields back, then sends in the background.
    @discardableResult func agree(_ agreed: Pending) -> Task<Void, Never> {
        pending = nil
        sending.formUnion(agreed.patch.settings)
        return Task { await send(agreed.patch, revertsOnFailure: agreed.revertsOnFailure) }
    }

    /// The person kept things as they were: what was chosen is put back, so the field shows what the server holds.
    func cancelPending() {
        guard let pending, let loaded else {
            self.pending = nil
            return
        }
        for setting in pending.patch.settings { draft[setting] = loaded.text(setting) }
        self.pending = nil
    }

    /// The retentions `patch` may make shorter. Only a value the server holds is compared with: an unset setting
    /// uses a default whoever runs the server may have changed and a key can't read, so a value typed for it asks
    /// unless nothing could keep more, and clearing a setting asks unless nothing could keep less.
    func shortenings(of patch: InstanceConfigPatch) -> [Shortening] {
        guard let loaded else { return [] }
        return InstanceSetting.allCases.compactMap { setting in
            guard patch.settings.contains(setting) else { return nil }
            if setting == .diskReserveMegabytes { return lowerReserve(patch, loaded) }
            guard setting.isRetention else { return nil }
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

    /// Keeping less free on disk asks, since a number typed on the way to a larger one (a 5 before 500) is sent when the field is
    /// left. Where the server holds nothing, the documented default is what is lowered.
    private func lowerReserve(_ patch: InstanceConfigPatch, _ loaded: InstanceConfig) -> Shortening? {
        let setting = InstanceSetting.diskReserveMegabytes
        guard let standard = setting.documentedDefault else { return nil }
        let held = loaded.number(setting) ?? standard
        let to: Int
        if case .number(let typed)? = patch.values[setting] { to = typed } else { to = standard }
        return to < held ? Shortening(setting: setting, change: .shorter(from: held, to: to)) : nil
    }

    private func send(_ patch: InstanceConfigPatch, revertsOnFailure: Bool) async {
        sending.formUnion(patch.settings)
        defer { sending.subtract(patch.settings) }
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
            onSaved(answer, patch.settings, target.id)
        } catch {
            guard generation == self.generation else { return }
            if revertsOnFailure, let loaded {
                for setting in patch.settings { draft[setting] = loaded.text(setting) }
            }
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
        sending = []
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
        count == 1 ? String(localized: "1 day") : String(localized: "\(count) days")
    }

    /// A number the server holds for a setting, in the unit the page shows.
    static func amount(_ setting: InstanceSetting, _ number: Int) -> String {
        if setting.zeroMeansNoLimit && number == 0 { return String(localized: "no limit") }
        switch setting {
        case .versionMaxVersions: return number == 1 ? String(localized: "1 version") : String(localized: "\(number) versions")
        case .blobMinCopies: return number == 1 ? String(localized: "1 copy") : String(localized: "\(number) copies")
        case .diskReserveMegabytes, .mcpFetchMaxMegabytes: return String(localized: "\(number) MB")
        case .blobCleanupGraceSeconds: return seconds(number)
        default: return days(number)
        }
    }

    static func seconds(_ count: Int) -> String {
        if count == 0 { return String(localized: "at the next sweep") }
        if count % 86_400 == 0 { return days(count / 86_400) }
        if count % 3_600 == 0 { return count == 3_600 ? String(localized: "1 hour") : String(localized: "\(count / 3_600) hours") }
        return String(localized: "\(count) seconds")
    }

    /// A setting's value as the server holds it, or its default where unset.
    static func value(_ config: InstanceConfig, _ setting: InstanceSetting) -> String {
        switch setting.kind {
        case .text: return config.name ?? String(localized: "Marfa (default)")
        case .flag:
            guard let flag = config.flag(setting) else { return String(localized: "default, on") }
            return flag ? String(localized: "on") : String(localized: "off")
        case .count:
            if let number = config.number(setting) { return amount(setting, number) }
            return String(localized: "default, \(amount(setting, setting.documentedDefault ?? 0))")
        }
    }

    /// What `shortening` may remove, in plain words. Where the server's current setting is not known, it says the
    /// change may remove things sooner than that setting.
    static func consequence(_ shortening: InstanceSettingsModel.Shortening) -> String {
        let setting = shortening.setting
        switch shortening.change {
        case .shorter(let from, let to):
            if setting == .diskReserveMegabytes { return String(localized: "Uploads will stop below \(amount(setting, to)) free instead of below \(amount(setting, from)), which leaves the server less room to work in.") }
            return removal(setting, keeping: to)
        case .mayBeShorter(let to):
            return String(localized: "This may remove \(setting.removes) sooner than the server’s current setting.") + " " + removal(setting, keeping: to)
        case .toDefault(let from):
            return String(localized: "Going back to the default for “\(setting.title)” uses the server’s own default, which the app can’t read. That may remove \(setting.removes) sooner than the server’s current setting, \(amount(setting, from)). What it removes can’t be recovered.")
        }
    }

    private static func removal(_ setting: InstanceSetting, keeping limit: Int) -> String {
        switch setting {
        case .blobCleanupGraceSeconds:
            limit == 0
                ? String(localized: "The next sweep can permanently remove files already reported as unused.")
                : String(localized: "A sweep can permanently remove a file after it has been reported as unused for \(seconds(limit)).")
        case .trashRetentionDays:
            String(localized: "Items deleted more than \(days(limit)) ago will be permanently deleted, with their history, the next time the server tidies up. They can’t be recovered.")
        case .versionMaxVersions:
            String(localized: "An item with more than \(limit) versions will have its oldest versions permanently deleted the next time the server tidies up.")
        case .versionRecentDays, .versionDailyDays, .versionWeeklyDays:
            String(localized: "“\(setting.title)” changes to \(days(limit)). Older versions of items may be permanently deleted the next time the server tidies up, so Version History will show fewer.")
        default:
            String(localized: "“\(setting.title)” changes to \(days(limit)). Anything older than that, in \(setting.removes), will be permanently deleted the next time the server tidies up. It can’t be recovered.")
        }
    }
}

nonisolated extension InstanceSetting {
    /// What a shorter setting removes, as the object of a sentence.
    var removes: String {
        switch self {
        case .blobCleanupGraceSeconds: String(localized: "unused files")
        case .trashRetentionDays: String(localized: "deleted items")
        case .versionRecentDays, .versionDailyDays, .versionWeeklyDays, .versionMaxVersions: String(localized: "versions")
        case .auditRetentionDays: String(localized: "activity and webhook deliveries")
        case .eventLogRetentionDays: String(localized: "events")
        case .rowLogRetentionDays: String(localized: "table changes")
        case .inboundHandledRetentionDays, .inboundPendingRetentionDays: String(localized: "connector deliveries")
        default: String(localized: "things")
        }
    }
}
