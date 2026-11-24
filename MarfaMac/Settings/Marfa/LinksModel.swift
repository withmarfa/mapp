import Foundation
import Marfa
import Observation

/// The Links page: the link types the owner registered, those plugins brought and those Marfa ships. The owner's own open a
/// page of their own with Delete…, which asks first; a new one is made in a sheet. Nothing is changed before the server
/// answers, and after any answer the list is read again, so it shows what the server holds.
@Observable @MainActor final class LinksModel: OwnerDraftHolding {
    /// A delete waiting for the owner's answer.
    struct Question: Identifiable, Equatable {
        let id: String
        let title: String
        let message: String
    }

    private let context: OwnerContext

    private(set) var linkTypes: [OwnerLinkType] = []
    private(set) var typeNames: [String: String] = [:]
    private(set) var hasLoaded = false
    private(set) var failure: OwnerFailure?

    // The sheet.
    private(set) var isMaking = false
    var name = ""
    var otherEndName = ""
    /// The item type each end takes, or nil for any type.
    var fromType: String?
    var toType: String?
    var cardinality = LinkCardinality.manyToMany
    private(set) var isWorking = false
    /// Why the server refused the new link type, kept beside what was typed.
    private(set) var makeFailure: OwnerFailure?
    /// The link type just made, so the page can open it.
    private(set) var made: String?
    /// Settings closed during registration, so a refused draft goes through the late handover.
    private var closedWhileWorking = false

    // Deleting.
    private(set) var question: Question?
    private(set) var isDeleting = false
    /// Why the last delete was not done, in words.
    private(set) var deleteFailure: (id: String, line: String)?
    /// The link type just deleted, so its page can close.
    private(set) var deleted: String?

    init(context: OwnerContext) {
        self.context = context
    }

    // MARK: Reading

    func load() async { await reread() }

    /// Reads the list again, and answers why it could not be read; a list read before stands.
    @discardableResult private func reread() async -> OwnerFailure? {
        defer { hasLoaded = true }
        do {
            let listing = try await context.calls.linkTypes()
            linkTypes = listing.linkTypes
            typeNames = listing.typeNames
            failure = nil
            return nil
        } catch {
            await context.learn(from: error)
            if !hasLoaded { failure = error }
            return error
        }
    }

    /// The owner's own: registered here or by another app, and brought by no plugin.
    var yours: [OwnerLinkType] { sorted(linkTypes.filter { !$0.shipped && $0.plugin == nil }) }
    var fromPlugins: [OwnerLinkType] { sorted(linkTypes.filter { !$0.shipped && $0.plugin != nil }) }
    var builtIn: [OwnerLinkType] { sorted(linkTypes.filter(\.shipped)) }

    private func sorted(_ types: [OwnerLinkType]) -> [OwnerLinkType] {
        types.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    func linkType(_ id: String) -> OwnerLinkType? { linkTypes.first { $0.id == id } }

    /// Whether the owner may delete it here: their own, which no plugin brought.
    func isYours(_ type: OwnerLinkType) -> Bool { !type.shipped && type.plugin == nil }

    func line(of type: OwnerLinkType) -> String {
        let from = Self.endpointNames(type.fromTypes, names: typeNames)
        let to = Self.endpointNames(type.toTypes, names: typeNames)
        if let plugin = type.plugin {
            return String(
                localized: "From \(plugin). From \(from) to \(to). \(type.cardinality.sentence)",
                comment: "Link type row. The placeholders are the plugin name, source type names, destination type names, and a sentence describing the link cardinality.")
        }
        return String(
            localized: "From \(from) to \(to). \(type.cardinality.sentence)",
            comment: "Link type row. The placeholders are the source type names, destination type names, and a sentence describing the link cardinality.")
    }

    /// What the Types page's row says: the first two link types and how many more.
    var summary: String? {
        let names = (builtIn + yours + fromPlugins).map(\.label)
        guard let first = names.first else { return nil }
        guard names.count > 1 else { return first }
        let second = names[1]
        if names.count == 2 { return String(localized: "\(first) and \(second).") }
        return String(localized: "\(first), \(second), and \(names.count - 2) more.")
    }

    private static func endpointNames(_ constraints: [String], names: [String: String]) -> String {
        if constraints.isEmpty || constraints.contains("*") { return String(localized: "Any Type") }
        let parts = constraints.map { constraint in
            if constraint.hasPrefix("role:") {
                return String(localized: "Role \(String(constraint.dropFirst(5)))")
            }
            return names[constraint] ?? constraint
        }
        return parts.formatted(.list(type: .or))
    }

    // MARK: New Link Type…

    /// The item types an end may be set to, by name: none that Marfa or an app keeps to itself.
    var typeChoices: [(id: String, name: String)] {
        typeNames.filter { !$0.key.hasPrefix("system.") && !$0.key.hasPrefix("app.") }
            .map { (id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedOtherEnd: String { otherEndName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canMake: Bool { !trimmedName.isEmpty && !isWorking }

    func beginNew() {
        name = ""
        otherEndName = ""
        fromType = nil
        toType = nil
        cardinality = .manyToMany
        makeFailure = nil
        isMaking = true
    }

    func cancelNew() {
        guard !isWorking else { return }
        isMaking = false
        makeFailure = nil
    }

    /// The server's 128-byte limit for dotted ASCII IDs (`edges/types-register-id`, `types/id-grammar`).
    static let identifierLimit = 128
    private static let identifierRoot = "user."

    /// The ID a new link type gets under `user.`, as the owner's own item types do: the name in lowercase letters, digits
    /// and underscores, cut to fit `identifierLimit`, and made unique among the IDs and reverse names listed, which the
    /// server refuses as held (`edges/types-name-held`).
    func identifier(forNamed text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var slug = String(folded.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "_" })
        while slug.contains("__") { slug = slug.replacingOccurrences(of: "__", with: "_") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if slug.isEmpty || !(slug.first?.isLetter ?? false) { slug = "link_" + slug }
        let taken = Set(linkTypes.map(\.id) + linkTypes.compactMap(\.reverseName))
        let room = Self.identifierLimit - Self.identifierRoot.count
        func fitted(_ suffix: String) -> String {
            var made = String(slug.prefix(room - suffix.count))
            while made.hasSuffix("_") { made.removeLast() }
            return Self.identifierRoot + made + suffix
        }
        var id = fitted("")
        var number = 2
        while taken.contains(id) {
            id = fitted("_\(number)")
            number += 1
        }
        return id
    }

    func make() async {
        guard canMake else { return }
        isWorking = true
        makeFailure = nil
        let typed = typedDraft()
        // The ID is made against the list as the server holds it now; a list that can't be read leaves the last one.
        await reread()
        let new = NewLinkType(
            id: identifier(forNamed: trimmedName), label: trimmedName, reverseLabel: trimmedOtherEnd.isEmpty ? nil : trimmedOtherEnd,
            cardinality: cardinality, fromTypes: [fromType ?? "*"], toTypes: [toType ?? "*"])
        do {
            let registered = try await context.calls.register(new)
            isWorking = false
            if closedWhileWorking {
                closedWhileWorking = false
            } else {
                isMaking = false
                made = registered.id
            }
            await load()
        } catch {
            isWorking = false
            await context.learn(from: error)
            if closedWhileWorking {
                closedWhileWorking = false
                if let typed { context.lateDraft(typed) }
            } else {
                makeFailure = error
            }
        }
    }

    func acknowledgeMade() { made = nil }

    /// The words for a refused new link type, in place of the server's.
    var makeFailureLine: String? {
        guard let makeFailure else { return nil }
        switch makeFailure {
        case .notPermitted(let scope) where scope == ClientOwnerCalls.registeringLinkTypes:
            return String(localized: "The app isn’t allowed to add link types. Choose Allow More… to ask for it.")
        case .refused(let reason): return reason
        default: return OwnerWording.line(makeFailure, on: .types)
        }
    }

    var makeNeedsPermission: Bool {
        if case .notPermitted = makeFailure { true } else { false }
    }

    /// Allow More… from the sheet's refusal: an approval drops the refusal, and Create Link Type asks the server again.
    func allowMore() async {
        guard makeNeedsPermission else { return }
        if await context.allowMore([]) == .allowed, makeNeedsPermission { makeFailure = nil }
    }

    func takeDrafts() -> [OwnerDraft] {
        guard isMaking else { return [] }
        if isWorking {
            closedWhileWorking = true
            return []
        }
        isMaking = false
        return typedDraft().map { [$0] } ?? []
    }

    /// Every field of New Link Type…, where a name at either end was typed, or nil where none was.
    private func typedDraft() -> OwnerDraft? {
        guard !trimmedName.isEmpty || !trimmedOtherEnd.isEmpty else { return nil }
        let lines = [
            trimmedName.isEmpty ? nil : String(localized: "Name: \(trimmedName)"),
            trimmedOtherEnd.isEmpty ? nil : String(localized: "Name at the Other End: \(trimmedOtherEnd)"),
            String(localized: "From: \(endName(fromType))"),
            String(localized: "To: \(endName(toType))"),
            String(localized: "How Many: \(cardinality.title)"),
        ].compactMap { $0 }
        return .typed(title: String(localized: "Link Type Not Made"), text: lines.joined(separator: "\n"))
    }

    private func endName(_ type: String?) -> String {
        guard let type else { return String(localized: "Any Type") }
        return typeNames[type] ?? type
    }

    // MARK: Delete…

    /// Asks before anything is sent: the owner answers `confirmDelete` or `cancelDelete`.
    func askToDelete(_ id: String) {
        guard let type = linkType(id), isYours(type), !isDeleting else { return }
        question = Question(
            id: id, title: String(localized: "Delete \(type.label)?"),
            message: String(localized: "Marfa deletes a link type only while no item uses it. Deleting can’t be undone."))
    }

    func cancelDelete() { question = nil }

    /// Deletes what `asked` names, the question the owner answered, which the alert gives back since closing it clears
    /// `question`. The list is read again first, and nothing is sent unless the type is still listed and still the owner's.
    func confirmDelete(_ asked: Question) async {
        guard !isDeleting else { return }
        question = nil
        isDeleting = true
        deleteFailure = nil
        defer { isDeleting = false }
        if let failure = await reread() {
            deleteFailure = (asked.id, OwnerWording.line(failure, on: .types))
            return
        }
        // Deleted somewhere else: its page says it is gone.
        guard let type = linkType(asked.id) else { return }
        let name = type.label
        guard isYours(type) else {
            deleteFailure = (asked.id, String(localized: "\(name) now comes from a plugin or from Marfa, so it wasn’t deleted."))
            return
        }
        do {
            switch try await context.calls.deleteLinkType(asked.id) {
            case .deleted, .gone:
                deleted = asked.id
            case .inUse:
                deleteFailure = (asked.id, String(localized: "Items still link with \(name), so it was kept. Remove those links first."))
            }
        } catch {
            await context.learn(from: error)
            deleteFailure = (asked.id, OwnerWording.line(error, on: .types))
        }
        await load()
    }

    func acknowledgeDeleted() { deleted = nil }

    func deleteLine(for id: String) -> String? {
        guard let deleteFailure, deleteFailure.id == id else { return nil }
        return deleteFailure.line
    }
}
