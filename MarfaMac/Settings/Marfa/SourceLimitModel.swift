import Foundation
import Marfa
import Observation

/// Limit Sources: for the types checked, every app and key reads only items from the sources checked, in lists, search, exports
/// and webhooks. It is the server's source filter, written through `EnforcementSettings`, so the other two levers go back as
/// the server holds them and a filter changed elsewhere since the page read it is told and not written over. Another Marfa
/// answering at the address is told in the settings page's words and the draft starts again from it, so what was chosen for
/// one Marfa is never written to another. Turning it off removes the filter.
@Observable @MainActor final class SourceLimitModel: OwnerDraftHolding {
    struct Choice: Identifiable, Hashable {
        let code: String
        let title: String
        var id: String { code }
    }

    private static let changedElsewhere = String(localized: "The limit was changed somewhere else. Nothing was sent. Check what you chose, then save again.")

    private let context: OwnerContext
    private let sources: () -> [MarfaSourceRow]

    private(set) var limit: Enforcement?
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

    init(context: OwnerContext, sources: @escaping () -> [MarfaSourceRow]) {
        self.context = context
        self.sources = sources
    }

    var isOn: Bool { limit?.filter != nil }

    /// The types a limit can name, by name: the server's own, with any the limit names that the server no longer lists.
    var typeChoices: [Choice] {
        let known = typeNames.filter { !$0.key.hasPrefix("system") }
        var codes = Set(known.keys)
        codes.formUnion(limit?.filter?.types ?? [])
        return codes.map { Choice(code: $0, title: known[$0] ?? $0) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The sources a limit can name: those with items, and any the limit names that have none now.
    var sourceChoices: [Choice] {
        var choices = sources().map { Choice(code: $0.code, title: $0.name) }
        for code in (limit?.filter?.sources ?? []) where !choices.contains(where: { $0.code == code }) {
            choices.append(Choice(code: code, title: code))
        }
        return choices
    }

    var hasEdits: Bool {
        guard let limit else { return false }
        return types != Set(limit.filter?.types ?? []) || checkedSources != Set(limit.filter?.sources ?? [])
    }

    /// A limit that names types but no source would hide every item of those types from every app, so it waits for a source.
    var canSave: Bool { hasEdits && !isSaving && (types.isEmpty || !checkedSources.isEmpty) }

    func load() async {
        await loader.load(in: context, primary: { () throws(OwnerFailure) in
            let read = try await context.calls.enforcement()
            // Judge the draft against the limit the person was shown.
            let keepsDraft = hasEdits && hasLoaded
            limit = read
            if !keepsDraft {
                types = Set(read.filter?.types ?? [])
                checkedSources = Set(read.filter?.sources ?? [])
            }
        }, secondary: [
            .required(typesRead) { [self] () throws(OwnerFailure) in typeNames = try await context.calls.typeNames() },
        ])
    }

    func revert() {
        guard let limit else { return }
        types = Set(limit.filter?.types ?? [])
        checkedSources = Set(limit.filter?.sources ?? [])
        line = nil
    }

    func save() async {
        guard canSave, let limit else { return }
        await write(limit, to: types.isEmpty ? nil : Enforcement.Lever(types: types.sorted(), sources: checkedSources.sorted()))
    }

    func turnOff() async {
        guard let limit, !isSaving else { return }
        await write(limit, to: nil)
    }

    private func write(_ limit: Enforcement, to filter: Enforcement.Lever?) async {
        isSaving = true
        line = nil
        defer { isSaving = false }
        do throws(EnforcementSettings.Failure) {
            let written = try await context.writeEnforcement(readFrom: limit.instanceID, unchangedSince: { $0.filter == limit.filter }) {
                $0.filter = filter
            }
            self.limit = written
            types = Set(written.filter?.types ?? [])
            checkedSources = Set(written.filter?.sources ?? [])
        } catch {
            switch error {
            case .anotherMarfa: await anotherMarfa()
            case .changedElsewhere(let current):
                self.limit = current
                line = Self.changedElsewhere
            case .owner(let failure): await refused(failure)
            }
        }
    }

    /// What was typed stays; the page says why, and where the limit changed elsewhere it is read again.
    private func refused(_ failure: OwnerFailure) async {
        line = failure == .conflict ? Self.changedElsewhere : OwnerWording.line(failure)
        await context.learn(from: failure)
        if failure == .conflict, let read = try? await context.calls.enforcement() { limit = read }
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
