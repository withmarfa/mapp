import Foundation
import Marfa
import Observation

/// The Types page: the types the server lists, in what the owner made, what plugins brought and what Marfa ships, and a type's
/// own page. Only a type of the owner's changes; a plugin's or Marfa's takes a child type and an icon. A change is sent as the
/// type's definition read again with that one change made, so what another app changed meanwhile is kept, and a refusal names
/// the field it is about and keeps what was typed.
@Observable @MainActor final class TypesModel: OwnerDraftHolding {
    /// What a refusal can be about on a type's page.
    enum Field: Hashable {
        case name, plural, description, guidance, basedOn, word, meaning, newType
        case fieldName, fieldMeaning, fieldLongest, fieldRule, fieldSearchable, fieldRemove, choice, newField, feed, merge
    }

    /// The four groups a status word sits in, in the order of a piece of work's life.
    static let groups: [(id: String, title: String)] = [
        ("not_started", String(localized: "Not Started")), ("in_progress", String(localized: "In Progress")),
        ("completed", String(localized: "Completed")), ("canceled", String(localized: "Canceled")),
    ]

    static let descriptionLimit = 200
    static let guidanceLimit = 1000
    static let wordMeaningLimit = 120
    static let fieldMeaningLimit = 300

    let context: OwnerContext
    let calls: any TypeCalls
    let access: TypeAccess

    var records: [TypeRecord] = [] {
        didSet { refreshList() }
    }
    private(set) var pluginTitles: [String: String] = [:]
    private(set) var readings: [String: TypeReading] = [:] {
        didSet { refreshList() }
    }
    private var list = TypeList()
    @ObservationIgnored private var listGeneration = 0
    private let loader = OwnerLoader()
    private var detailReads: [String: OwnerLoader.ReadStatus] = [:]
    var failure: OwnerFailure? { loader.failure }
    var hasLoaded: Bool { loader.hasLoaded }
    /// The line a refusal gives, by the field it is about, for the type open now.
    var fieldErrors: [Field: String] = [:]
    /// A refusal that is not about one field, shown above the sections.
    var pageFailure: OwnerFailure?

    // The drafts of the open type: what was typed, kept until it is saved or the page leaves.
    private(set) var openID: String?
    private var draftedID: String?
    var name = ""
    var plural = ""
    var descriptionText = ""
    var guidanceText = ""
    /// Whether the server refused the open type's guidance from an app, so the page gives the command that writes it.
    var guidanceNeedsCommand = false
    var copiedCommand: String?
    var addingGroup: String?
    var wordDraft = ""
    /// The word whose meaning is being written.
    var meaningWord: String?
    var meaningDraft = ""
    private(set) var isSavingMeaning = false

    // The open field's page and the sheets that make or rename a field.
    var openFieldKey: String?
    var fieldMeaning = ""
    var fieldLongest = ""
    var isAddingChoice = false
    var choiceDraft = ""
    var isAddingField = false
    var newFieldName = ""
    var newFieldKind = FieldKind.text
    var newFieldChoices = ""
    var isRenamingField = false
    var fieldNameDraft = ""

    // Deleting the open type.
    var isDeleting = false
    var deleteFailure: String?
    /// The type that was deleted, so the page can leave it.
    var deleted: String?

    // The sheet that makes a child type.
    var isMakingChild = false
    var childParent: String?
    var childName = ""

    var iconTarget: String?
    var iconSearch = ""
    var iconSet: MarfaMarkSet
    var iconFailure: String?
    var isChangingIcon = false

    /// How many changes to the type are queued or in flight. Each reads the type, makes its one change and replaces it, and
    /// a replacement carries no version, so two at once would send back each other's old values.
    var pending = 0
    var tail: Task<Void, Never>?
    var isWorking: Bool { pending > 0 }
    /// The text last sent for the name, plural or description, so a field left again without a new edit sends nothing while
    /// an edit back to what the server held before is still sent behind the one in flight.
    var queuedText: [Field: String] = [:]
    /// Set when Settings closed while a change was queued, so the queue's end hands over what no change kept.
    var closedWhileWorking = false
    /// The type a child type was made as, so the page can open it.
    var made: String?

    init(context: OwnerContext, calls: any TypeCalls, access: TypeAccess) {
        self.context = context
        self.calls = calls
        self.access = access
        iconSet = access.markSets.first ?? MarfaMarkSet(id: "", title: "")
    }

    // MARK: Reading

    func load() async {
        await loader.load(in: context, primary: { () throws(OwnerFailure) in
            do throws(TypeFailure) {
                let listing = try await calls.types()
                records = listing.types.filter { !Self.isHidden($0.id) }
                pluginTitles = listing.pluginTitles
            } catch {
                throw Self.owner(error)
            }
        }, after: {
            if let id = openID {
                open(id)
                await loadReading(of: id)
            }
        })
    }

    /// `system.*` and `app.*` are machinery that no app lists.
    static func isHidden(_ id: String) -> Bool { id.hasPrefix("system.") || id.hasPrefix("app.") }

    static func owner(_ failure: TypeFailure) -> OwnerFailure {
        switch failure {
        case .owner(let failure): failure
        case .invalid(_, let message): .refused(message)
        case .pluginType: .refused(String(localized: "This type belongs to a plugin, so it can only change with the plugin."))
        case .changedOnServer: .conflict
        case .guidanceByApp: .refused(String(localized: "This Marfa takes guidance only from the command line for now."))
        case .canceled: .notConfirmed
        case .inUse, .hasSubtypes: .conflict
        }
    }

    func record(_ id: String) -> TypeRecord? { list.recordsByID[id] }

    func loadReading(of id: String) async {
        let status = detailReads[id, default: OwnerLoader.ReadStatus()]
        if detailReads[id] == nil { detailReads[id] = status }
        await loader.read(.required(status) { [self] () throws(OwnerFailure) in
            do throws(TypeFailure) {
                readings[id] = try await calls.reading(of: id)
            } catch {
                throw Self.owner(error)
            }
        }, in: context)
    }

    func readingFailure(of id: String) -> OwnerFailure? { detailReads[id]?.failure }

    /// Reads the types again, so the page shows what the server holds.
    @discardableResult
    func reread() async -> Bool {
        guard let listing = try? await calls.types() else { return false }
        records = listing.types.filter { !Self.isHidden($0.id) }
        pluginTitles = listing.pluginTitles
        return true
    }

    // MARK: The list

    private struct TypeList {
        var recordsByID: [String: TypeRecord] = [:]
        var titles: [String: String] = [:]
        var childrenByParent: [String: [TypeRecord]] = [:]
        var sortedChildrenByParent: [String: [TypeRecord]] = [:]
        var counts: [String: Int] = [:]
        var sorted: [TypeRecord] = []
        var yours: [TypeRecord] = []
        var fromPlugins: [TypeRecord] = []
        var builtIn: [TypeRecord] = []

        /// The types below `id`, at any depth.
        func descendants(of id: String) -> [TypeRecord] {
            var found: [TypeRecord] = []
            var queue = [id]
            var seen: Set<String> = [id]
            while let next = queue.popLast() {
                for child in childrenByParent[next, default: []] where seen.insert(child.id).inserted {
                    found.append(child)
                    queue.append(child.id)
                }
            }
            return found
        }
    }

    private func refreshList() {
        listGeneration += 1
        let generation = listGeneration
        let records = records
        let readings = readings
        let access = access
        list = withObservationTracking {
            var next = TypeList()
            var ownCounts: [String: Int] = [:]
            for type in records {
                if let parent = type.parent { next.childrenByParent[parent, default: []].append(type) }
                guard next.recordsByID[type.id] == nil else { continue }
                next.recordsByID[type.id] = type
                next.titles[type.id] = type.plural ?? readings[type.id]?.plural ?? access.plural(type.id) ?? type.label
                ownCounts[type.id] = access.ownItems(type.id)
            }
            let titles = next.titles
            next.sorted = records.sorted {
                let order = titles[$0.id, default: $0.id].localizedStandardCompare(titles[$1.id, default: $1.id])
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
            for type in next.sorted {
                if let parent = type.parent { next.sortedChildrenByParent[parent, default: []].append(type) }
                switch type.origin {
                case .registered, .unknown: next.yours.append(type)
                case .plugin: next.fromPlugins.append(type)
                case .platform: next.builtIn.append(type)
                }
            }
            for (id, ownCount) in ownCounts {
                let childCount = next.descendants(of: id).reduce(0) { $0 + ownCounts[$1.id, default: 0] }
                next.counts[id] = ownCount + childCount
            }
            return next
        } onChange: { [weak self] in
            // The working copy can change its plurals and counts without a new list from the server.
            Task { @MainActor [weak self] in
                guard let self, self.listGeneration == generation else { return }
                self.refreshList()
            }
        }
    }

    /// The owner's own types, and those an app made for them.
    var yours: [TypeRecord] { list.yours }
    var fromPlugins: [TypeRecord] { list.fromPlugins }
    var builtIn: [TypeRecord] { list.builtIn }

    /// Whether the owner can change the type: one they made, which no plugin installed and Marfa does not ship.
    func isEditable(_ type: TypeRecord) -> Bool { type.origin == .registered || type.origin == .unknown }

    func children(of id: String) -> [TypeRecord] { list.sortedChildrenByParent[id, default: []] }

    /// How many items the type holds, its subtypes' included, as the library counts them.
    func count(of id: String) -> Int {
        list.counts[id] ?? (access.ownItems(id) + list.descendants(of: id).reduce(0) { $0 + access.ownItems($1.id) })
    }

    /// The type's name for a row: the plural, which is how every list of types reads.
    func title(of id: String) -> String { list.titles[id, default: id] }

    func title(of type: TypeRecord) -> String { title(of: type.id) }

    func title(ofPlugin name: String) -> String { pluginTitles[name] ?? Self.title(ofPlugin: name) }

    /// The line under a type in the list: where it came from, what it is based on and what is based on it.
    func subtitle(of type: TypeRecord) -> String? {
        var parts: [String] = []
        if type.origin == .plugin, let plugin = type.plugin { parts.append(String(localized: "From \(title(ofPlugin: plugin.name)).")) }
        if let parent = type.parent, record(parent) != nil { parts.append(String(localized: "Based on \(title(of: parent)).")) }
        let below = children(of: type.id).map { title(of: $0) }
        if !below.isEmpty, below.count <= 4 { parts.append(String(localized: "With \(below.formatted(.list(type: .and))).")) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// A plugin's name for people: `google-calendar` reads "Google Calendar".
    static func title(ofPlugin name: String) -> String {
        name.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// The line under a type's name on its own page.
    func headLine(of type: TypeRecord) -> String {
        let items = count(of: type.id)
        let held = String(AttributedString(localized: "^[\(items) item](inflect: true).").characters)
        switch type.origin {
        case .platform: return String(localized: "Built into Marfa. ") + held
        case .plugin:
            guard let plugin = type.plugin else { return held }
            return String(localized: "From the \(title(ofPlugin: plugin.name)) plugin, \(plugin.version). ") + held
        case .registered, .unknown:
            if let parent = type.parent, record(parent) != nil { return String(localized: "Based on \(title(of: parent)). ") + held }
            return held
        }
    }

    // MARK: A type's page

    /// Opens a type: its drafts are what the server holds. Called again once the types have loaded, it fills the drafts
    /// of a type that was open before they were read, and never replaces what is being typed.
    func open(_ id: String) {
        if openID != id {
            openID = id
            draftedID = nil
            fieldErrors = [:]
            pageFailure = nil
            guidanceNeedsCommand = false
            copiedCommand = nil
            addingGroup = nil
            wordDraft = ""
            meaningWord = nil
            queuedText = [:]
            openFieldKey = nil
            deleteFailure = nil
            Task { await loadReading(of: id) }
        }
        if draftedID != id, let type = record(id) {
            draftedID = id
            name = type.label
            plural = type.plural ?? ""
            descriptionText = type.description ?? ""
            guidanceText = type.guidance ?? ""
        }
    }

    func close() {
        openID = nil
        draftedID = nil
    }

    func reading(of id: String) -> TypeReading? { readings[id] }

    /// The types the open type could be based on: every listed type that is not it or below it.
    func basedOnChoices(for id: String) -> [TypeRecord] {
        let excluded = Set(list.descendants(of: id).map(\.id) + [id])
        return list.sorted.filter { !excluded.contains($0.id) }
    }

    /// The number of characters, counting what a person sees as the server does: in Unicode code points, so an emoji is one.
    static func length(of text: String) -> Int { text.unicodeScalars.count }

    // MARK: Words

    /// A word written for reading: `in_progress` reads "In Progress".
    static func title(ofWord value: String) -> String {
        let words = value.split(whereSeparator: { $0 == "_" || $0 == "-" }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return Bundle.main.localizedString(forKey: words, value: words, table: nil)
    }

    /// What a typed word is named on the server: lowercase, with a space or a hyphen as an underscore. The server judges the rest.
    static func value(ofTyped text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" }).joined(separator: "_")
    }

    /// The type and every type above it, the farthest first.
    func chain(of id: String) -> [TypeRecord] {
        var found: [TypeRecord] = []
        var next: String? = id
        var seen: Set<String> = []
        while let current = next, seen.insert(current).inserted, let type = record(current) {
            found.insert(type, at: 0)
            next = type.parent
        }
        return found
    }

    /// The words of `group` for the open type: those a type above gives (locked) first, then its own.
    func words(of id: String, in group: String) -> [SettingsWord] {
        let types = chain(of: id)
        let editable = record(id).map(isEditable) ?? false
        return types.flatMap { type in
            type.fields.values.flatMap(\.statusWords).filter { $0.group == group }.map { word in
                SettingsWord(
                    id: word.value, title: Self.title(ofWord: word.value), meaning: word.meaning,
                    isLocked: type.id != id || !editable)
            }
        }
    }

    /// Whether the open type, or one above it, has a status field to add words to.
    func hasStatus(_ id: String) -> Bool {
        chain(of: id).contains { $0.fields.values.contains { $0.kind == "status" } }
    }


    func beginWord(in group: String) {
        guard addingGroup == nil || addingGroup == group else { return }
        fieldErrors[.word] = nil
        addingGroup = group
        wordDraft = ""
    }

    func cancelWord() {
        addingGroup = nil
        wordDraft = ""
        fieldErrors[.word] = nil
    }

    /// Keeps the typed word. A refusal leaves the field open with what was typed, and says why under the section.
    func commitWord() async {
        guard let id = openID, let group = addingGroup else { return }
        let value = Self.value(ofTyped: wordDraft)
        guard !value.isEmpty else { return cancelWord() }
        await apply(.addWord(group: group, value: value), to: id, field: .word) {
            self.addingGroup = nil
            self.wordDraft = ""
        }
    }

    func beginMeaning(of word: String, in id: String) {
        meaningWord = word
        fieldErrors[.meaning] = nil
        meaningDraft = chain(of: id).last?.fields.values.flatMap(\.statusWords).first { $0.value == word }?.meaning ?? ""
    }

    func cancelMeaning() {
        guard !isSavingMeaning else { return }
        meaningWord = nil
        fieldErrors[.meaning] = nil
    }

    func saveMeaning() async {
        guard let id = openID, let word = meaningWord, !isSavingMeaning else { return }
        isSavingMeaning = true
        defer { isSavingMeaning = false }
        await apply(.wordMeaning(value: word, text: meaningDraft.trimmingCharacters(in: .whitespacesAndNewlines)), to: id, field: .meaning) {
            self.meaningWord = nil
        }
    }
}
