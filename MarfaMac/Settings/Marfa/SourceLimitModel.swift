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
/// the sources checked. Each is written whole after a fresh read: a change made elsewhere to the rule before the write is told and
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
    private let sources: () -> [MarfaSourceRow]

    private(set) var limit: SourceLimit?
    private(set) var typeNames: [String: String] = [:]
    var types: Set<String> = []
    var checkedSources: Set<String> = []
    private let loader = OwnerLoader()
    private let typesRead = OwnerLoader.ReadStatus()
    var failure: OwnerFailure? { loader.failure }
    var typesFailure: OwnerFailure? { typesRead.failure }
    /// One line under the page's rows for what the server refused or the page can't send.
    private(set) var line: String?
    private(set) var isSaving = false
    var hasLoaded: Bool { loader.hasLoaded }

    init(rule: SourceRule, context: OwnerContext, sources: @escaping () -> [MarfaSourceRow]) {
        self.rule = rule
        self.context = context
        self.sources = sources
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

    /// The sources a limit can name: those with items, and any the limit names that have none now.
    var sourceChoices: [Choice] {
        var choices = sources().map { Choice(code: $0.code, title: $0.name) }
        for code in (value?.sources ?? []) where !choices.contains(where: { $0.code == code }) {
            choices.append(Choice(code: code, title: code))
        }
        return choices
    }

    var hasEdits: Bool {
        guard limit != nil else { return false }
        return types != Set(value?.types ?? []) || checkedSources != Set(value?.sources ?? [])
    }

    /// Why what is checked can't be saved: a rule that names types and no source would hide every item of those types from every
    /// app, or let no app or key add one.
    var waitsFor: String? {
        guard !types.isEmpty, checkedSources.isEmpty else { return nil }
        return switch rule {
        case .filter: String(localized: "Check a source too. With none, no app or key could read items of these types.")
        case .allowlist: String(localized: "Check a source too. With none, no app or key could add items of these types.")
        }
    }

    var canSave: Bool { hasEdits && !isSaving && waitsFor == nil }

    func load() async {
        await loader.load(in: context, primary: { () throws(OwnerFailure) in
            let read = try await context.calls.sourceLimit()
            // Judge the draft against the limit the person was shown.
            let keepsDraft = hasEdits && hasLoaded
            limit = read
            if !keepsDraft {
                types = Set(read.value(of: rule)?.types ?? [])
                checkedSources = Set(read.value(of: rule)?.sources ?? [])
            }
        }, secondary: [
            .required(typesRead) { [self] () throws(OwnerFailure) in typeNames = try await context.calls.typeNames() },
        ])
    }

    func revert() {
        guard limit != nil else { return }
        types = Set(value?.types ?? [])
        checkedSources = Set(value?.sources ?? [])
        line = nil
    }

    func save() async {
        guard canSave, let limit else { return }
        await write(limit, to: types.isEmpty ? nil : SourceRuleValue(types: types.sorted(), sources: checkedSources.sorted()))
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
