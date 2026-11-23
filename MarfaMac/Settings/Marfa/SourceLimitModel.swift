import Foundation
import Marfa
import Observation

/// Limit Sources: for the types checked, every app and key reads only items from the sources checked, in lists, search, exports
/// and webhooks. It is the server's source filter, written whole with the other two levers as they were read, so a change
/// made elsewhere before the write is told and not written over. Another Marfa answering at the address is told in the settings
/// page's words and the draft starts again from it, so what was chosen for one Marfa is never written to another. Turning it
/// off removes the filter.
@Observable @MainActor final class SourceLimitModel: OwnerDraftHolding {
    struct Choice: Identifiable, Hashable {
        let code: String
        let title: String
        var id: String { code }
    }

    private static let changedElsewhere = String(localized: "The limit was changed somewhere else. Nothing was sent. Check what you chose, then save again.")

    private let context: OwnerContext
    private let sources: () -> [MarfaSourceRow]

    private(set) var limit: SourceLimit?
    private(set) var typeNames: [String: String] = [:]
    var types: Set<String> = []
    var checkedSources: Set<String> = []
    private(set) var failure: OwnerFailure?
    /// One line under the page's rows for what the server refused or the page can't send.
    private(set) var line: String?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var hasLoaded = false

    init(context: OwnerContext, sources: @escaping () -> [MarfaSourceRow]) {
        self.context = context
        self.sources = sources
    }

    var isOn: Bool { limit?.isOn ?? false }

    /// The types a limit can name, by name: the server's own, with any the limit names that the server no longer lists.
    var typeChoices: [Choice] {
        let known = typeNames.filter { !$0.key.hasPrefix("system") }
        var codes = Set(known.keys)
        codes.formUnion(limit?.types ?? [])
        return codes.map { Choice(code: $0, title: known[$0] ?? $0) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The sources a limit can name: those with items, and any the limit names that have none now.
    var sourceChoices: [Choice] {
        var choices = sources().map { Choice(code: $0.code, title: $0.name) }
        for code in (limit?.sources ?? []) where !choices.contains(where: { $0.code == code }) {
            choices.append(Choice(code: code, title: code))
        }
        return choices
    }

    var hasEdits: Bool {
        guard let limit else { return false }
        return types != Set(limit.types) || checkedSources != Set(limit.sources)
    }

    /// A limit that names types but no source would hide every item of those types from every app, so it waits for a source.
    var canSave: Bool { hasEdits && !isSaving && (types.isEmpty || !checkedSources.isEmpty) }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            let read = try await context.calls.sourceLimit()
            // Whether the person has edited is judged against the limit they were shown, not the one just read.
            let keepsDraft = hasEdits && hasLoaded
            limit = read
            if !keepsDraft {
                types = Set(read.types)
                checkedSources = Set(read.sources)
            }
            failure = nil
        } catch {
            failure = error
            await context.learn(from: error)
            return
        }
        typeNames = (try? await context.calls.typeNames()) ?? typeNames
    }

    func revert() {
        guard let limit else { return }
        types = Set(limit.types)
        checkedSources = Set(limit.sources)
        line = nil
    }

    func save() async {
        guard canSave, let limit else { return }
        await write(limit, to: types.isEmpty ? nil : (types.sorted(), checkedSources.sorted()))
    }

    func turnOff() async {
        guard let limit, !isSaving else { return }
        await write(limit, to: nil)
    }

    private func write(_ limit: SourceLimit, to filter: (types: [String], sources: [String])?) async {
        isSaving = true
        line = nil
        defer { isSaving = false }
        do {
            // The server guards only which instance is written, not the levers, so what was read is read again just before: a
            // lever changed elsewhere since is told, not written over.
            let current = try await context.calls.sourceLimit()
            if let was = limit.instanceID, let now = current.instanceID, was != now {
                await anotherMarfa()
                return
            }
            guard current == limit else {
                self.limit = current
                line = Self.changedElsewhere
                return
            }
            let written = try await context.calls.setSourceLimit(current, to: filter)
            self.limit = written
            types = Set(written.types)
            checkedSources = Set(written.sources)
        } catch {
            await refused(error)
        }
    }

    /// What was typed stays; the page says why, and where the limit changed elsewhere it is read again.
    private func refused(_ failure: OwnerFailure) async {
        if failure == .instanceChanged {
            await anotherMarfa()
            return
        }
        line = failure == .conflict ? Self.changedElsewhere : OwnerWording.line(failure)
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
        return [.typed(title: String(localized: "Limit Sources Not Saved"), text: "\(chosen)\n\(from)")]
    }
}
