import Foundation
import Marfa
import Observation

/// One of the two source rules for every app and key, each the types it covers and the sources it names.
nonisolated enum SourceRule: Hashable, Sendable {
    /// Limit Sources (`enforcement.source_filter`): for the types named, only items from the sources named are read.
    case filter
    /// Who May Write (`enforcement.source_allowlist`): for exactly the types named, only the sources named may add items.
    case allowlist

    var title: String {
        switch self {
        case .filter: String(localized: "Limit Sources")
        case .allowlist: String(localized: "Who May Write")
        }
    }

    /// What the app isn't allowed to do on the rule's page without `config.manage`.
    var permissionLine: String {
        switch self {
        case .filter: String(localized: "The app isn’t allowed to read or change which sources apps and keys read.")
        case .allowlist: String(localized: "The app isn’t allowed to read or change which sources may add items.")
        }
    }
}

/// The sources a current key or app can write under (`items/source-own`, `items/source-claimed`,
/// `keys-and-oauth/app-source-code`), each with the name of what writes it. A connector host's key holds no access to any
/// type, and a `restored:` source can belong to no credential (`keys-and-oauth/claims-reserved`), so neither is here.
nonisolated struct SourceWriters: Hashable, Sendable {
    let names: [String: String]

    init(keys: [KeyInfo], apps: [AppAccess], now: Date = .now) {
        var names: [String: String] = [:]
        for app in apps { names["oauth:" + app.clientID] = app.name ?? app.clientID }
        for key in keys where key.expires.map({ $0 > now }) ?? true {
            guard !key.source.lowercased().hasPrefix("connector-host:") else { continue }
            names[key.source] = names[key.source] ?? key.label
            for claim in key.claims where names[claim] == nil { names[claim] = claim }
        }
        self.names = names
    }

    func canWrite(underAnyOf sources: Set<String>) -> Bool { sources.contains { names[$0] != nil } }
}

nonisolated struct SourceRuleValue: Hashable, Sendable {
    var types: [String]
    var sources: [String]
}

extension SourceLimit {
    /// What `rule` holds as read, or nil where it is not set.
    func value(of rule: SourceRule) -> SourceRuleValue? {
        switch rule {
        case .filter: isOn ? SourceRuleValue(types: types, sources: sources) : nil
        case .allowlist: allowlist.map { SourceRuleValue(types: $0.types, sources: $0.sources) }
        }
    }
}

/// A source rule's page: Limit Sources, for the types checked every app and key reads only items from the sources checked, in
/// lists, search, exports and webhooks; Who May Write, for exactly the types checked every app and key adds items only under
/// the sources checked. Its sources are every one the instance holds and those of every current key and app, so a source a
/// filter hides can be checked again, and Who May Write refuses a list no current key or app could write under. Each is
/// written whole after a fresh read: a change made elsewhere to the rule before the write is told and
/// not written over, and the other levers are sent as that read found them. Another Marfa answering at the address is told in the settings page's words and the
/// draft starts again from it, so what was chosen for one Marfa is never written to another. Turning a rule off removes it.
@Observable @MainActor final class SourceLimitModel: OwnerDraftHolding {
    struct Choice: Identifiable, Hashable {
        let code: String
        let title: String
        var id: String { code }
    }

    let rule: SourceRule
    private let context: OwnerContext

    private(set) var limit: SourceLimit?
    private(set) var typeNames: [String: String] = [:]
    /// Every source the instance holds, read from the server, not from the items a source filter lets the app count.
    private(set) var known: [OwnerSource] = []
    /// Nil until the keys and apps are read.
    private(set) var writers: SourceWriters?
    var types: Set<String> = []
    var checkedSources: Set<String> = []
    private let loader = OwnerLoader()
    private let typesRead = OwnerLoader.ReadStatus()
    private let sourcesRead = OwnerLoader.ReadStatus()
    var failure: OwnerFailure? { loader.failure }
    var typesFailure: OwnerFailure? { typesRead.failure }
    var sourcesFailure: OwnerFailure? { sourcesRead.failure }
    /// One line under the page's rows for what the server refused or the page can't send.
    private(set) var line: String?
    private(set) var isSaving = false
    var hasLoaded: Bool { loader.hasLoaded }

    init(rule: SourceRule, context: OwnerContext) {
        self.rule = rule
        self.context = context
    }

    /// The rule as read, or nil where it is not set.
    var value: SourceRuleValue? { limit?.value(of: rule) }
    var isOn: Bool { value != nil }

    /// The types a limit can name, by name: the server's own, with any the limit names that the server no longer lists.
    var typeChoices: [Choice] {
        let known = typeNames.filter { !$0.key.hasPrefix("system") }
        var codes = Set(known.keys)
        codes.formUnion(value?.types ?? [])
        return codes.map { Choice(code: $0, title: known[$0] ?? $0) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The sources a rule can name: every one the instance holds, those of keys and apps that have written nothing yet, and
    /// any the rule names that the server no longer lists.
    var sourceChoices: [Choice] {
        var titles: [String: String] = [:]
        for source in known where !source.code.isEmpty { titles[source.code] = source.name }
        for (code, name) in writers?.names ?? [:] where titles[code] == nil { titles[code] = name }
        for code in value?.sources ?? [] where titles[code] == nil { titles[code] = code }
        return titles.map { Choice(code: $0.key, title: $0.value) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var hasEdits: Bool {
        guard limit != nil else { return false }
        return types != Set(value?.types ?? []) || checkedSources != Set(value?.sources ?? [])
    }

    /// Why what is checked can't be saved: a rule that names types and no source would hide every item of those types from every
    /// app, and an allow-list naming no source a current key or app writes under would let none add one.
    var waitsFor: String? {
        guard !types.isEmpty else { return nil }
        if checkedSources.isEmpty {
            return switch rule {
            case .filter: String(localized: "Check a source too. With none, no app or key could read items of these types.")
            case .allowlist: String(localized: "Check a source too. With none, no app or key could add items of these types.")
            }
        }
        guard rule == .allowlist else { return nil }
        guard let writers else {
            return sourcesFailure == nil
                ? nil : String(localized: "The app couldn’t read your keys and apps, so it can’t check that one of them could still add these types.")
        }
        return Self.lockout(writers, checkedSources)
    }

    private static func lockout(_ writers: SourceWriters, _ sources: Set<String>) -> String? {
        writers.canWrite(underAnyOf: sources)
            ? nil : String(localized: "No key or app writes under the checked sources, so nothing could add items of these types. Check one that does.")
    }

    /// Whether Save would turn the rule off, every type being unchecked, which asks first as Turn Off does.
    var saveTurnsOff: Bool { isOn && types.isEmpty }

    var canSave: Bool {
        guard hasEdits, !isSaving else { return false }
        if types.isEmpty { return isOn }
        return waitsFor == nil && (rule == .filter || writers != nil)
    }

    /// Reads the rule; with `choices`, also the types, sources, keys and apps its page offers, waiting for a read already under
    /// way so they are never skipped. The Sources list needs only the rule.
    func load(choices: Bool = true) async {
        await loader.load(in: context, waitForPrevious: choices, primary: { () throws(OwnerFailure) in
            let read = try await context.calls.sourceLimit()
            // Judge the draft against the limit the person was shown.
            let keepsDraft = hasEdits && hasLoaded
            limit = read
            if !keepsDraft {
                types = Set(read.value(of: rule)?.types ?? [])
                checkedSources = Set(read.value(of: rule)?.sources ?? [])
            }
        }, secondary: choices ? [
            .required(typesRead) { [self] () throws(OwnerFailure) in typeNames = try await context.calls.typeNames() },
            .required(sourcesRead) { [self] () throws(OwnerFailure) in
                known = try await context.calls.sources()
                writers = try await readWriters()
            },
        ] : [])
    }

    private func readWriters() async throws(OwnerFailure) -> SourceWriters {
        SourceWriters(keys: try await context.calls.keys(), apps: try await context.calls.apps())
    }

    func revert() {
        guard limit != nil else { return }
        types = Set(value?.types ?? [])
        checkedSources = Set(value?.sources ?? [])
        line = nil
    }

    /// Sends what is checked. Turning the rule off goes through `turnOff()`, after the question.
    func save() async {
        guard canSave, !types.isEmpty, let limit else { return }
        await write(limit, to: SourceRuleValue(types: types.sorted(), sources: checkedSources.sorted()))
    }

    func turnOff() async {
        guard let limit, !isSaving else { return }
        await write(limit, to: nil)
    }

    private func write(_ limit: SourceLimit, to value: SourceRuleValue?) async {
        isSaving = true
        line = nil
        defer { isSaving = false }
        do {
            // The server guards only which instance is written, not the levers, so they are read again just before: this rule
            // changed elsewhere since is told, not written over, and the other levers go back as they are now, as a type's Strict
            // switch sends these rules back.
            let current = try await context.calls.sourceLimit()
            if let was = limit.instanceID, let now = current.instanceID, was != now {
                await anotherMarfa()
                return
            }
            guard current.value(of: rule) == limit.value(of: rule) else {
                self.limit = current
                line = changedElsewhere
                return
            }
            // A key or app may have ended since the page read them, so who could still write is read again too.
            if rule == .allowlist, let value {
                let now = try await readWriters()
                writers = now
                if let lockout = Self.lockout(now, Set(value.sources)) {
                    line = lockout
                    return
                }
            }
            let written = try await context.calls.setSourceRule(rule, of: current, to: value)
            self.limit = written
            types = Set(written.value(of: rule)?.types ?? [])
            checkedSources = Set(written.value(of: rule)?.sources ?? [])
        } catch {
            await refused(error)
        }
    }

    /// What is told when the rule was found changed since it was read.
    private var changedElsewhere: String {
        String(localized: "\(rule.title) was changed somewhere else. Nothing was sent. Check what you chose, then save again.")
    }

    /// What was typed stays; the page says why, and where the limit changed elsewhere it is read again.
    private func refused(_ failure: OwnerFailure) async {
        if failure == .instanceChanged {
            await anotherMarfa()
            return
        }
        line = failure == .conflict ? changedElsewhere : OwnerWording.line(failure)
        await context.learn(from: failure)
        if failure == .conflict, let read = try? await context.calls.sourceLimit() { limit = read }
    }

    /// Another Marfa answers at the address: nothing was written, and the limit, the types and the sources are read again from
    /// it, so what was chosen for the first is dropped rather than kept to be written to this one.
    private func anotherMarfa() async {
        limit = nil
        typeNames = [:]
        known = []
        writers = nil
        types = []
        checkedSources = []
        await load()
        line = InstanceConfigFailure.instanceChanged.message
    }

    /// What was chosen and not saved goes back to the person when Settings closes.
    func takeDrafts() -> [OwnerDraft] {
        guard hasEdits else { return [] }
        let chosen = typeChoices.filter { types.contains($0.code) }.map(\.title).joined(separator: ", ")
        let from = sourceChoices.filter { checkedSources.contains($0.code) }.map(\.title).joined(separator: ", ")
        revert()
        let title =
            switch rule {
            case .filter: String(localized: "Limit Sources Not Saved")
            case .allowlist: String(localized: "Who May Write Not Saved")
            }
        return [.typed(title: title, text: "\(chosen)\n\(from)")]
    }
}
