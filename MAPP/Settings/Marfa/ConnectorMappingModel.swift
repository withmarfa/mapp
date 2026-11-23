import Foundation
import Marfa
import Observation

/// How a field of the target type is filled, as the owner chooses it.
nonisolated enum MappingChoice: Hashable, Sendable {
    case none
    case field(String)
    case fixed
    case template
}

/// What the preview shows.
nonisolated enum MappingPreviewState: Hashable, Sendable {
    case none
    case asking
    /// The connector has not answered; it does at its next run.
    case waiting
    case ready(MappingPreviewItem)
    case failed(String?)
    case expired
    /// The preview could not be asked for or read, in the owner's words.
    case unavailable(String)
}

/// One connector's mapping: what each of its kinds brings, held as the owner's draft beside what the server stores. A change
/// is saved as it is made; a save the server refuses keeps the draft, shows what it refused on the field, and leaves the stored
/// mapping as it was.
@Observable @MainActor final class ConnectorMappingModel: OwnerDraftHolding {
    struct Kind: Equatable {
        /// What the server stores.
        var saved: KindMapping
        /// What the owner has made of it.
        var draft: KindMapping
        /// What the server refused in the draft, by place in the kind's entry.
        var faults: [MappingFault] = []
    }

    private let context: OwnerContext
    let plugin: PluginConnectorSummary

    private(set) var kinds: [String: Kind] = [:]
    private(set) var version = 0
    private(set) var rewrites: [PendingRewrite] = []
    private(set) var options: [MappingTypeOption] = []
    private(set) var types: [String: MappingTypeInfo] = [:]
    private(set) var failure: OwnerFailure?
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var isSaving = false
    /// A save that failed for want of the server, a permission or the like, not one the server judged.
    private(set) var saveFailure: OwnerFailure?
    /// The mapping changed somewhere else, so the draft was not saved. It is kept, and Reload carries it onto what is there now.
    private(set) var isStale = false
    private(set) var previews: [String: MappingPreviewState] = [:]
    /// How many existing items each kind's rewrite would move, once counted.
    private(set) var counts: [String: Int] = [:]
    private(set) var rewriteFailure: OwnerFailure?
    private(set) var isAsking = false
    /// The kind whose rewrite the owner is being asked about.
    var question: String?
    /// How many times a kind's mapping was last sent or read, so the preview asks again only when that changed.
    private(set) var previewRuns: [String: Int] = [:]

    private var queued: Set<String> = []
    private var generation: [String: Int] = [:]

    init(context: OwnerContext, plugin: PluginConnectorSummary) {
        self.context = context
        self.plugin = plugin
    }

    // MARK: Reading

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        let reading: ConnectorMappingReading
        do {
            reading = try await context.calls.connectorMapping(of: plugin.name)
            failure = nil
        } catch {
            failure = error
            await context.learn(from: error)
            return
        }
        options = (try? await context.calls.mappingTypeOptions()) ?? options
        take(reading)
        for entry in kinds.values { await ensureType(entry.saved.targetType) }
        for kind in plugin.kinds { await ensureType(kind.type) }
        for name in kinds.keys {
            previewRuns[name, default: 0] += 1
            await count(name)
        }
    }

    /// Takes what the server holds as the saved mapping. A kind with a change made and not saved keeps it.
    private func take(_ reading: ConnectorMappingReading) {
        version = reading.version
        rewrites = reading.rewrites
        for (name, mapping) in reading.kinds {
            if var held = kinds[name] {
                let clean = held.draft == held.saved
                held.saved = mapping
                if clean { held.draft = mapping; held.faults = [] }
                kinds[name] = held
            } else {
                kinds[name] = Kind(saved: mapping, draft: mapping)
            }
        }
    }

    func ensureType(_ id: String) async {
        guard !id.isEmpty, types[id] == nil else { return }
        if let info = try? await context.calls.mappingType(id) { types[id] = info }
    }

    func type(_ id: String) -> MappingTypeInfo? { types[id] }

    private var names: [String: String] {
        OwnerWording.typeNames(options.map { (id: $0.id, label: $0.label, parent: $0.parent) })
    }

    func typeName(_ id: String) -> String { names[id] ?? types[id]?.label ?? id }

    /// The types a kind can land as, with the kind's own type first and the one now chosen kept where it is not offered.
    func targetChoices(for kind: String) -> [MappingTypeOption] {
        var list = options
        let own = plugin.kinds.first { $0.name == kind }?.type
        if let own, let index = list.firstIndex(where: { $0.id == own }) { list.insert(list.remove(at: index), at: 0) }
        if let chosen = kinds[kind]?.draft.targetType, !list.contains(where: { $0.id == chosen }) {
            list.append(MappingTypeOption(id: chosen, label: types[chosen]?.label ?? chosen, parent: nil))
        }
        return list
    }

    func ownType(of kind: String) -> MappingTypeInfo? {
        plugin.kinds.first { $0.name == kind }.flatMap { types[$0.type] }
    }

    func draft(_ kind: String) -> KindMapping? { kinds[kind]?.draft }

    // MARK: Fields

    /// The fields of a kind's target type, required ones first.
    func targetFields(of kind: String) -> [MappingTypeField] {
        guard let target = kinds[kind].flatMap({ types[$0.draft.targetType] }) else { return [] }
        return target.fields.sorted { lhs, rhs in
            if lhs.required != rhs.required { return lhs.required }
            return MappingWording.fieldTitle(lhs).localizedStandardCompare(MappingWording.fieldTitle(rhs)) == .orderedAscending
        }
    }

    /// The fields of the kind's own type that can fill `field`: those of the same sort of value, and the one it is filled from now.
    func sources(for field: MappingTypeField, in kind: String) -> [MappingTypeField] {
        guard let own = ownType(of: kind) else { return [] }
        let current: String? = if case .field(let name)? = kinds[kind]?.draft.fields[field.name] { name } else { nil }
        return own.fields.filter { MappingWording.fits($0.kind, into: field.kind) || $0.name == current }
            .sorted { MappingWording.fieldTitle($0).localizedStandardCompare(MappingWording.fieldTitle($1)) == .orderedAscending }
    }

    func choice(of field: String, in kind: String) -> MappingChoice {
        switch kinds[kind]?.draft.fields[field] {
        case .field(let name)?: .field(name)
        case .fixed?: .fixed
        case .template?: .template
        case nil: .none
        }
    }

    /// What a fixed value or template holds, as text.
    func text(of field: String, in kind: String) -> String {
        switch kinds[kind]?.draft.fields[field] {
        case .fixed(let value)?: ConnectorsModel.text(value)
        case .template(let text)?: text
        default: ""
        }
    }

    func flag(of field: String, in kind: String) -> Bool {
        if case .fixed(.flag(let on))? = kinds[kind]?.draft.fields[field] { on } else { false }
    }

    /// The first of the fields the server refused for `field`, or a number typed that is not one.
    func error(for field: MappingTypeField, in kind: String) -> String? {
        if let word = numberError(field, in: kind) { return word }
        guard let entry = kinds[kind] else { return nil }
        guard let fault = entry.faults.first(where: { $0.path == "fields.\(field.name)" || $0.path.hasPrefix("fields.\(field.name).") }) else {
            return nil
        }
        let filled = entry.draft.fields[field.name] != nil
        if field.required, !filled, fault.path == "fields.\(field.name)" {
            return MappingWording.needs(typeName(entry.draft.targetType), field: MappingWording.fieldTitle(field))
        }
        return fault.message
    }

    private func numberError(_ field: MappingTypeField, in kind: String) -> String? {
        guard field.kind == .number || field.kind == .integer, case .fixed(.text(let typed))? = kinds[kind]?.draft.fields[field.name] else {
            return nil
        }
        return Self.number(typed, whole: field.kind == .integer) == nil && !typed.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(localized: "Enter a number.") : nil
    }

    private static func number(_ text: String, whole: Bool) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if whole { return Int(trimmed).map(Double.init) }
        return try? Double(trimmed, format: .number)
    }

    /// What a kind's target type is refused for, which no field of it names.
    func kindFault(_ kind: String) -> MappingFault? {
        kinds[kind]?.faults.first { !$0.path.hasPrefix("fields.") }
    }

    func isRefused(_ kind: String) -> Bool { !(kinds[kind]?.faults.isEmpty ?? true) }

    // MARK: Status words

    /// The status field of the target filled from a status field of the kind's own type, with that field's words. Only one
    /// pair is mapped word by word, since a kind has one set of overrides.
    func statusPair(of kind: String) -> (target: MappingTypeField, own: MappingTypeField)? {
        guard let entry = kinds[kind], let own = ownType(of: kind) else { return nil }
        for field in targetFields(of: kind).sorted(by: { $0.name < $1.name }) where field.kind == .status {
            if case .field(let name)? = entry.draft.fields[field.name], let source = own.field(name), source.kind == .status {
                return (field, source)
            }
        }
        return nil
    }

    func override(of word: String, in kind: String) -> String? { kinds[kind]?.draft.statusOverrides[word] }

    func setOverride(_ target: String?, for word: String, in kind: String) async {
        edit(kind) { draft in
            if let target { draft.statusOverrides[word] = target } else { draft.statusOverrides[word] = nil }
        }
        await commit(kind)
    }

    // MARK: Changing the draft

    private func edit(_ kind: String, _ change: (inout KindMapping) -> Void) {
        guard var entry = kinds[kind] else { return }
        change(&entry.draft)
        kinds[kind] = entry
    }

    func setEnabled(_ on: Bool, for kind: String) async {
        edit(kind) { $0.enabled = on }
        await commit(kind)
    }

    func setTier(_ tier: KeyTier, for kind: String) async {
        edit(kind) { $0.tier = tier }
        await commit(kind)
    }

    /// Lands the kind as another type, filling each field both types hold from the kind's own, as the server does for a mapping
    /// that names none.
    func setTarget(_ id: String, for kind: String) async {
        guard let entry = kinds[kind], entry.draft.targetType != id else { return }
        await ensureType(id)
        let shared = Set(ownType(of: kind)?.fields.map(\.name) ?? []).intersection(types[id]?.fields.map(\.name) ?? [])
        edit(kind) { draft in
            draft.targetType = id
            draft.fields = Dictionary(uniqueKeysWithValues: shared.map { ($0, MappingSource.field($0)) })
            draft.statusOverrides = [:]
        }
        await commit(kind)
    }

    func setChoice(_ choice: MappingChoice, for field: MappingTypeField, in kind: String) async {
        edit(kind) { draft in
            switch choice {
            case .none: draft.fields[field.name] = nil
            case .field(let name): draft.fields[field.name] = .field(name)
            case .template:
                if case .template? = draft.fields[field.name] { break }
                draft.fields[field.name] = .template("")
            case .fixed:
                if case .fixed? = draft.fields[field.name] { break }
                draft.fields[field.name] = .fixed(field.kind == .boolean ? .flag(false) : .text(""))
            }
        }
        await commit(kind)
    }

    /// Sets what a fixed value or a template holds, which is sent when the field is left or submitted.
    func type(_ text: String, into field: MappingTypeField, in kind: String) {
        edit(kind) { draft in
            switch draft.fields[field.name] {
            case .template?: draft.fields[field.name] = .template(text)
            case .fixed?: draft.fields[field.name] = .fixed(.text(text))
            default: break
            }
        }
    }

    func setFixed(_ value: ConnectorSettingValue, for field: MappingTypeField, in kind: String) async {
        edit(kind) { $0.fields[field.name] = .fixed(value) }
        await commit(kind)
    }

    // MARK: Saving

    /// What the draft says to the server: a fixed value or template left empty fills nothing, and a number typed is a number.
    func wire(_ kind: String) -> KindMapping? {
        guard let entry = kinds[kind] else { return nil }
        var mapping = entry.draft
        let target = types[mapping.targetType]
        for (name, source) in mapping.fields {
            switch source {
            case .template(let text) where text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty: mapping.fields[name] = nil
            case .fixed(.text(let text)):
                let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !typed.isEmpty else { mapping.fields[name] = nil; continue }
                switch target?.field(name)?.kind {
                case .number?, .integer?:
                    if let number = Self.number(typed, whole: target?.field(name)?.kind == .integer) { mapping.fields[name] = .fixed(.number(number)) }
                default: mapping.fields[name] = .fixed(.text(typed))
                }
            default: break
            }
        }
        return mapping
    }

    /// Whether the draft of a kind holds a change the server does not.
    func isUnsaved(_ kind: String) -> Bool {
        guard let entry = kinds[kind] else { return false }
        return wire(kind) != entry.saved || !entry.faults.isEmpty
    }

    var hasUnsaved: Bool { kinds.keys.contains(where: isUnsaved) }

    private func hasBadNumber(_ kind: String) -> Bool {
        targetFields(of: kind).contains { numberError($0, in: kind) != nil }
    }

    /// Saves a kind's draft, where it differs from what is stored. One save runs at a time; a change made while one runs is
    /// saved after it. The kinds the owner has not changed are sent as they are stored, so a kind the server refused does not
    /// hold the others back.
    func commit(_ kind: String) async {
        guard let entry = kinds[kind], let sent = wire(kind), sent != entry.saved, !hasBadNumber(kind) else { return }
        if isSaving { queued.insert(kind); return }
        isSaving = true
        saveFailure = nil
        previewRuns[kind, default: 0] += 1
        var body = kinds.mapValues(\.saved)
        body[kind] = sent
        let outcome: MappingSaveOutcome
        do {
            outcome = try await context.calls.saveConnectorMapping(of: plugin.name, version: version, kinds: body)
        } catch {
            isSaving = false
            saveFailure = error
            await context.learn(from: error)
            await drain()
            return
        }
        isSaving = false
        switch outcome {
        case .saved(let reading):
            isStale = false
            take(reading)
            kinds[kind]?.faults = []
            for entry in kinds.values { await ensureType(entry.saved.targetType) }
            await count(kind)
        case .refused(let faults):
            kinds[kind]?.faults = faults.map { fault in
                let prefix = "kinds.\(kind)."
                return MappingFault(path: fault.path.hasPrefix(prefix) ? String(fault.path.dropFirst(prefix.count)) : fault.path, message: fault.message)
            }
        case .stale:
            isStale = true
        }
        await drain()
    }

    private func drain() async {
        guard !queued.isEmpty, !isStale else { return }
        let next = queued.sorted()
        queued = []
        for kind in next { await commit(kind) }
    }

    /// Reads the mapping again after another app changed it, keeping every change made here and saving it on what is there now.
    func reload() async {
        let reading: ConnectorMappingReading
        do {
            reading = try await context.calls.connectorMapping(of: plugin.name)
        } catch {
            saveFailure = error
            await context.learn(from: error)
            return
        }
        saveFailure = nil
        take(reading)
        isStale = false
        for kind in kinds.keys.sorted() { await commit(kind) }
    }

    // MARK: Preview

    /// Asks the connector to render a recent item under the draft and follows its answer. It answers at its next run, so this
    /// waits; it stops when a newer ask replaces it or its task ends, and gives up when the server stops keeping the preview.
    func preview(_ kind: String, every interval: Duration = .seconds(2), now: () -> Date = { .now }) async {
        generation[kind, default: 0] += 1
        let mine = generation[kind] ?? 0
        guard let entry = kinds[kind] else { return }
        previews[kind] = .asking
        let started: MappingPreview
        do {
            started = try await context.calls.startMappingPreview(of: plugin.name, kind: kind, draft: wire(kind) == entry.saved ? nil : wire(kind))
        } catch {
            if generation[kind] == mine { previews[kind] = .unavailable(MappingWording.previewRefused(error)) }
            await context.learn(from: error)
            return
        }
        var current = started
        while generation[kind] == mine, !Task.isCancelled {
            switch current.status {
            case .ready(let item): previews[kind] = .ready(item); return
            case .failed(let reason): previews[kind] = .failed(reason); return
            case .pending: previews[kind] = .waiting
            }
            if now() >= current.expires { previews[kind] = .expired; return }
            try? await Task.sleep(for: interval)
            guard generation[kind] == mine, !Task.isCancelled else { return }
            do {
                current = try await context.calls.mappingPreview(of: plugin.name, id: current.id)
            } catch {
                previews[kind] = error == .notFound ? .expired : .unavailable(OwnerWording.line(error))
                return
            }
        }
    }

    func previewState(_ kind: String) -> MappingPreviewState { previews[kind] ?? .none }

    // MARK: Existing items

    func count(_ kind: String) async {
        guard let entry = kinds[kind], entry.saved.enabled else { counts[kind] = 0; return }
        if let answer = try? await context.calls.rewriteConnectorItems(of: plugin.name, kinds: [kind], dryRun: true) {
            counts[kind] = answer.kinds[kind]?.count ?? 0
        }
    }

    func pending(_ kind: String) -> [PendingRewrite] { rewrites.filter { $0.kinds.contains(kind) } }

    /// Whether Apply to Them… can be offered: the draft is saved, so what is applied is what the server holds.
    func canApply(_ kind: String) -> Bool { !isUnsaved(kind) && !isSaving && !isAsking && (counts[kind] ?? 0) > 0 }

    func askToApply(_ kind: String) { if canApply(kind) { question = kind } }

    func cancelQuestion() { question = nil }

    /// Asks the connector to move the kind's existing items, then reads the mapping to show the request as pending.
    func apply(_ kind: String) async {
        question = nil
        guard !isAsking else { return }
        isAsking = true
        defer { isAsking = false }
        rewriteFailure = nil
        do {
            _ = try await context.calls.rewriteConnectorItems(of: plugin.name, kinds: [kind], dryRun: false)
        } catch {
            rewriteFailure = error
            await context.learn(from: error)
            return
        }
        if let reading = try? await context.calls.connectorMapping(of: plugin.name) { take(reading) }
        await count(kind)
    }

    // MARK: Closing

    /// What the owner changed and the server does not hold, which the app gives back when Settings closes.
    func takeDrafts() -> [OwnerDraft] {
        var drafts: [OwnerDraft] = []
        for name in kinds.keys.sorted() where isUnsaved(name) {
            guard let mapping = wire(name) else { continue }
            drafts.append(.typed(title: String(localized: "\(ConnectorWording.kindTitle(name)) Mapping Not Saved"), text: MappingWording.summary(mapping)))
        }
        return drafts
    }
}
