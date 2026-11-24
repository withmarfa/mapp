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
    /// The sheet was closed while its call ran, so what it typed was already handed over.
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

    func load() async {
        do {
            let listing = try await context.calls.linkTypes()
            linkTypes = listing.linkTypes
            typeNames = listing.typeNames
            failure = nil
        } catch {
            await context.learn(from: error)
            if !hasLoaded { failure = error }
        }
        hasLoaded = true
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

    /// "From a job to a person. Many to one."
    func line(of type: OwnerLinkType) -> String {
        let ends = String(localized: "From \(Self.phrase(type.fromTypes, names: typeNames)) to \(Self.phrase(type.toTypes, names: typeNames)).")
        if let plugin = type.plugin { return String(localized: "From \(plugin).") + " " + ends + " " + type.cardinality.sentence }
        return ends + " " + type.cardinality.sentence
    }

    /// What the Types page's row says: the first two link types and how many more.
    var summary: String? {
        let names = (builtIn + yours + fromPlugins).map(\.label)
        guard let first = names.first else { return nil }
        guard names.count > 1 else { return first }
        let second = Self.lowered(names[1])
        if names.count == 2 { return String(localized: "\(first) and \(second).") }
        return String(localized: "\(first), \(second), and \(names.count - 2) more.")
    }

    /// One end's item types in words: "any item", "a job" or "a job or a task".
    static func phrase(_ constraints: [String], names: [String: String]) -> String {
        if constraints.isEmpty || constraints.contains("*") { return String(localized: "any item") }
        let parts = constraints.map { constraint in
            if constraint.hasPrefix("role:") {
                return String(localized: "any \(lowered(String(constraint.dropFirst(5))))")
            }
            return article(lowered(names[constraint] ?? constraint))
        }
        return parts.formatted(.list(type: .or))
    }

    /// A name as it reads inside a sentence: a word whose only capital is its first is lowered, so "Pull Request" reads
    /// "pull request" and "GitHub Issue" reads "GitHub issue".
    static func lowered(_ name: String) -> String {
        name.split(separator: " ", omittingEmptySubsequences: false).map { word in
            word.dropFirst().contains(where: \.isUppercase) ? String(word) : word.lowercased()
        }.joined(separator: " ")
    }

    private static func article(_ noun: String) -> String {
        guard let first = noun.first?.lowercased() else { return noun }
        return "aeiou".contains(first) ? String(localized: "an \(noun)") : String(localized: "a \(noun)")
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

    /// The ID a new link type gets under `user.`, as the owner's own item types do: the name in lowercase letters, digits
    /// and underscores, made unique among the link types listed.
    func identifier(forNamed text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        var slug = String(folded.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "_" })
        while slug.contains("__") { slug = slug.replacingOccurrences(of: "__", with: "_") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if slug.isEmpty || !(slug.first?.isLetter ?? false) { slug = "link_" + slug }
        if slug.hasSuffix("_") { slug.removeLast() }
        let taken = Set(linkTypes.map(\.id))
        var id = "user." + slug
        var number = 2
        while taken.contains(id) {
            id = "user.\(slug)_\(number)"
            number += 1
        }
        return id
    }

    func make() async {
        guard canMake else { return }
        isWorking = true
        makeFailure = nil
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
                context.lateDraft(.typed(title: String(localized: "Link Type Not Made"), text: new.label))
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

    func takeDrafts() -> [OwnerDraft] {
        guard isMaking else { return [] }
        if isWorking {
            closedWhileWorking = true
            return []
        }
        isMaking = false
        guard !trimmedName.isEmpty else { return [] }
        return [.typed(title: String(localized: "Link Type Not Made"), text: trimmedName)]
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

    func confirmDelete() async {
        guard let asked = question else { return }
        question = nil
        isDeleting = true
        deleteFailure = nil
        defer { isDeleting = false }
        let name = linkType(asked.id)?.label ?? asked.id
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
