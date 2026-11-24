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
/// `keys-and-oauth/app-source-code`), each with the name of what writes it and the types each credential under it may write. A
/// connector host's key holds no access to any type, and a `restored:` source can belong to no credential
/// (`keys-and-oauth/claims-reserved`), so neither is here.
nonisolated struct SourceWriters: Hashable, Sendable {
    /// What one key or app may write, read as the server reads its type map or its grant's scopes.
    enum Access: Hashable, Sendable {
        case key(types: [String: AccessLevel], madeByApp: Bool)
        case app(scopes: [String], vendors: [String])

        func writes(_ type: String) -> Bool {
            switch self {
            case .key(let map, let madeByApp): Self.level(of: type, in: map, madeByApp: madeByApp) == .write
            case .app(let scopes, let vendors): Self.grantWrites(type, scopes: scopes, vendors: vendors)
            }
        }

        /// The exact entry, else the wildcard with the longest root, else `*` (`keys-and-oauth/map-exact-first`,
        /// `map-longest-wildcard`, `map-global-last`, `map-wildcard-root`). A key an app made reaches `app.*` only through
        /// entries under it (`keys-and-oauth/app-key-own-vendor`).
        private static func level(of type: String, in map: [String: AccessLevel], madeByApp: Bool) -> AccessLevel {
            if let exact = map[type] { return exact }
            let wildcard = map.filter { $0.key.hasSuffix(".*") && covers(String($0.key.dropLast(2)), type) }
                .max { $0.key.count < $1.key.count }
            if let wildcard { return wildcard.value }
            if madeByApp, type.hasPrefix("app.") { return .none }
            return map["*"] ?? .none
        }

        /// A `<pattern>:write` scope: `*` is all data and `content` all but `system`, `marfa` and `app`, neither reaching
        /// `app.*` (`keys-and-oauth/content-excludes-app`); an app reaches its own vendors with any type write scope
        /// (`keys-and-oauth/app-reaches-own-vendor`).
        private static func grantWrites(_ type: String, scopes: [String], vendors: [String]) -> Bool {
            let patterns = scopes.filter { $0.hasSuffix(":write") }.map { String($0.dropLast(":write".count)) }
            let root = type.split(separator: ".").first.map(String.init) ?? type
            let typePatterns = patterns.filter { !["edge", "metadata", "profile"].contains($0.split(separator: ".").first.map(String.init)) }
            if vendors.contains(where: { type.hasPrefix($0 + ".") }), !typePatterns.isEmpty { return true }
            return patterns.contains { pattern in
                switch pattern {
                case "*": root != "app"
                case "content": !["system", "marfa", "app"].contains(root)
                default: pattern.hasSuffix(".*") ? covers(String(pattern.dropLast(2)), type) : pattern == type
                }
            }
        }

        private static func covers(_ wildcardRoot: String, _ type: String) -> Bool {
            type == wildcardRoot || type.hasPrefix(wildcardRoot + ".")
        }
    }

    let names: [String: String]
    let access: [String: [Access]]

    init(keys: [KeyInfo], apps: [AppAccess], now: Date = .now) {
        var names: [String: String] = [:]
        var access: [String: [Access]] = [:]
        for app in apps {
            names["oauth:" + app.clientID] = app.name ?? app.clientID
            access["oauth:" + app.clientID, default: []].append(.app(scopes: app.scopes, vendors: app.vendors))
        }
        for key in keys where key.expires.map({ $0 > now }) ?? true {
            guard !key.source.lowercased().hasPrefix("connector-host:") else { continue }
            names[key.source] = names[key.source] ?? key.label
            let keyAccess = Access.key(types: key.types, madeByApp: key.appClientID != nil)
            access[key.source, default: []].append(keyAccess)
            for claim in key.claims {
                if names[claim] == nil { names[claim] = claim }
                access[claim, default: []].append(keyAccess)
            }
        }
        self.names = names
        self.access = access
    }

    /// The first of `types` that no current key or app may write under any of `sources`, or nil where each has a writer.
    func unwritable(_ types: [String], underAnyOf sources: Set<String>) -> String? {
        types.first { type in !sources.contains { access[$0]?.contains { $0.writes(type) } == true } }
    }
}

nonisolated struct SourceRuleValue: Hashable, Sendable {
    var types: [String]
    var sources: [String]
}

nonisolated extension SourceLimit {
    /// What `rule` holds as read, or nil where it is not set.
    func value(of rule: SourceRule) -> SourceRuleValue? {
        switch rule {
        case .filter: isOn ? SourceRuleValue(types: types, sources: sources) : nil
        case .allowlist: allowlist.map { SourceRuleValue(types: $0.types, sources: $0.sources) }
        }
    }

    /// Sets `rule` alone, or turns it off with nil.
    mutating func set(_ rule: SourceRule, to value: SourceRuleValue?) {
        switch rule {
        case .filter:
            isOn = value != nil
            types = value?.types ?? []
            sources = value?.sources ?? []
        case .allowlist:
            allowlist = value.map { ($0.types, $0.sources) }
        }
    }
}

/// A source rule's page: Limit Sources, for the types checked every app and key reads only items from the sources checked, in
/// lists, search, exports and webhooks; Who May Write, for exactly the types checked every app and key adds items only under
/// the sources checked. Its sources are every one the instance holds, so a source a filter hides can be checked again, and for
/// Who May Write those of every current key and app, refusing a list under which none may write a type it names. Each is
/// written through `EnforcementSettings`: a change made elsewhere to the rule since the page read it is told and not written
/// over, and the other levers go back as the server then holds them. Another Marfa answering at the address is told in the
/// settings page's words and the draft starts again from it, so what was chosen for one Marfa is never written to another.
/// Turning a rule off removes it.
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
    /// Who May Write's keys and apps; nil until read, and never read for Limit Sources.
    private(set) var writers: SourceWriters?
    /// Why the apps couldn't be read for Who May Write's check, which then holds only keys.
    private(set) var appsFailure: OwnerFailure?
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
                ? nil : String(localized: "The app couldn’t read your keys, so it can’t check that one of them could still add these types.")
        }
        return lockout(writers, types, checkedSources)
    }

    /// Why no checked source could add one of `types`, naming the type, or nil where each has a writer. Where the apps
    /// couldn't be read, only keys were checked, and the line says so.
    private func lockout(_ writers: SourceWriters, _ types: Set<String>, _ sources: Set<String>) -> String? {
        guard let type = writers.unwritable(types.sorted(), underAnyOf: sources) else { return nil }
        let name = typeChoices.first { $0.code == type }?.title ?? type
        return appsFailure == nil
            ? String(localized: "No key or app that writes under the checked sources may add \(name) items, so nothing could. Check a source that can.")
            : String(localized: "No key that writes under the checked sources may add \(name) items, and the app can’t check your apps. Check a source a key can add them under, or allow the app to read your apps.")
    }

    /// Whether Save would turn the rule off, every type being unchecked, which asks first as Turn Off does.
    var saveTurnsOff: Bool { isOn && types.isEmpty }

    var canSave: Bool {
        guard hasEdits, !isSaving else { return false }
        if types.isEmpty { return isOn }
        return waitsFor == nil && (rule == .filter || writers != nil)
    }

    /// Reads the rule; with `choices`, also the types and sources its page offers, and for Who May Write the keys and apps that
    /// could write, waiting for a read already under way so they are never skipped. The Sources list needs only the rule.
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
                if rule == .allowlist { writers = try await readWriters() }
            },
        ] : [])
    }

    /// The keys, and the apps where the sign-in may read them. Without `grants.manage` the apps are left out and
    /// `appsFailure` says so, so a list a key writes under can still be saved.
    private func readWriters() async throws(OwnerFailure) -> SourceWriters {
        let keys = try await context.calls.keys()
        do {
            let apps = try await context.calls.apps()
            appsFailure = nil
            return SourceWriters(keys: keys, apps: apps)
        } catch {
            guard case .notPermitted = error else { throw error }
            appsFailure = error
            return SourceWriters(keys: keys, apps: [])
        }
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
        // A key or app may have ended since the page read them, so who could still write is read again first.
        if rule == .allowlist, let value {
            do {
                let now = try await readWriters()
                writers = now
                if let lockout = lockout(now, Set(value.types), Set(value.sources)) {
                    line = lockout
                    return
                }
            } catch {
                await refused(error)
                return
            }
        }
        let rule = rule
        let shown = limit.value(of: rule)
        do throws(EnforcementSettings.Failure) {
            let written = try await context.writeEnforcement(
                readFrom: limit.instanceID, unchangedSince: { $0.value(of: rule) == shown }
            ) { $0.set(rule, to: value) }
            self.limit = written
            types = Set(written.value(of: rule)?.types ?? [])
            checkedSources = Set(written.value(of: rule)?.sources ?? [])
        } catch {
            switch error {
            case .owner(let failure): await refused(failure)
            case .changedElsewhere(let levers):
                self.limit = levers
                line = changedElsewhere
            case .anotherMarfa: await anotherMarfa()
            }
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
        appsFailure = nil
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
