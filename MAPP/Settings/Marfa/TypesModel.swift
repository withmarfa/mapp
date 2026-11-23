import Foundation
import Marfa
import Observation

/// What the Types page asks of the app that holds it: how many items a type holds, the icon a type shows now and the one
/// call that changes it, which the app makes through its library so the icon shows at once. All in the app's own terms, so
/// a test scripts them.
struct TypeAccess {
    var ownItems: (String) -> Int
    var currentIcon: (String) -> String?
    var setIcon: (String?, String) async -> OwnerFailure?
    var markSets: [MarfaMarkSet]
    var marks: (String, MarfaMarkSet) -> [String]
    /// The plural the working copy reads for a type, which a type that declares none shows by the regular rule.
    var plural: (String) -> String?
}

/// The Types page: the types the server lists, in what the owner made, what plugins brought and what Marfa ships, and a type's
/// own page. Only a type of the owner's changes; a plugin's or Marfa's takes a child type and an icon. A change is sent as the
/// type's definition read again with that one change made, so what another app changed meanwhile is kept, and a refusal names
/// the field it is about and keeps what was typed.
@Observable @MainActor final class TypesModel: OwnerDraftHolding {
    /// What a refusal can be about on a type's page.
    enum Field: Hashable {
        case name, plural, description, basedOn, word, meaning, newType
    }

    /// The four groups a status word sits in, in the order of a piece of work's life.
    static let groups: [(id: String, title: String)] = [
        ("not_started", String(localized: "Not Started")), ("in_progress", String(localized: "In Progress")),
        ("completed", String(localized: "Completed")), ("canceled", String(localized: "Canceled")),
    ]

    static let descriptionLimit = 200
    static let guidanceLimit = 1000
    static let wordMeaningLimit = 120

    private let context: OwnerContext
    private let calls: any TypeCalls
    private let access: TypeAccess

    private(set) var records: [TypeRecord] = []
    private(set) var pluginTitles: [String: String] = [:]
    private(set) var readings: [String: TypeReading] = [:]
    private(set) var failure: OwnerFailure?
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    /// The line a refusal gives, by the field it is about, for the type open now.
    private(set) var fieldErrors: [Field: String] = [:]
    /// A refusal that is not about one field, shown above the sections.
    private(set) var pageFailure: OwnerFailure?

    // The drafts of the open type: what was typed, kept until it is saved or the page leaves.
    private(set) var openID: String?
    private var draftedID: String?
    var name = ""
    var plural = ""
    var descriptionText = ""
    private(set) var addingGroup: String?
    var wordDraft = ""
    /// The word whose meaning is being written.
    private(set) var meaningWord: String?
    var meaningDraft = ""
    private(set) var isSavingMeaning = false

    // The sheet that makes a child type.
    private(set) var isMakingChild = false
    var childParent: String?
    var childName = ""
    /// How many changes to the type are queued or in flight. Each reads the type, makes its one change and replaces it, and
    /// a replacement carries no version, so two at once would send back each other's old values.
    private var pending = 0
    private var tail: Task<Void, Never>?
    var isWorking: Bool { pending > 0 }
    /// The text last sent for the name, plural or description, so a field left again without a new edit sends nothing while
    /// an edit back to what the server held before is still sent behind the one in flight.
    private var queuedText: [Field: String] = [:]
    /// Set when Settings closed while a change was queued, so the queue's end hands over what no change kept.
    private var closedWhileWorking = false
    /// The type a child type was made as, so the page can open it.
    private(set) var made: String?

    init(context: OwnerContext, calls: any TypeCalls, access: TypeAccess) {
        self.context = context
        self.calls = calls
        self.access = access
        iconSet = access.markSets.first ?? MarfaMarkSet(id: "", title: "")
    }

    // MARK: Reading

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            let listing = try await calls.types()
            records = listing.types.filter { !Self.isHidden($0.id) }
            pluginTitles = listing.pluginTitles
            failure = nil
        } catch {
            failure = Self.owner(error)
            await context.learn(from: Self.owner(error))
        }
        if let id = openID {
            open(id)
            await loadReading(of: id)
        }
    }

    /// `system.*` and `app.*` are machinery that no app lists.
    static func isHidden(_ id: String) -> Bool { id.hasPrefix("system.") || id.hasPrefix("app.") }

    static func owner(_ failure: TypeFailure) -> OwnerFailure {
        switch failure {
        case .owner(let failure): failure
        case .invalid(_, let message): .refused(message)
        case .pluginType: .refused(String(localized: "This type belongs to a plugin, so it can only change with the plugin."))
        case .changedOnServer: .conflict
        case .guidanceByApp: .refused(String(localized: "Guidance is written by the owner, not by an app."))
        }
    }

    func record(_ id: String) -> TypeRecord? { records.first { $0.id == id } }

    private func loadReading(of id: String) async {
        if let read = try? await calls.reading(of: id) { readings[id] = read }
    }

    // MARK: The list

    /// The owner's own types, and those an app made for them.
    var yours: [TypeRecord] { sorted(records.filter { $0.origin == .registered || $0.origin == .unknown }) }
    var fromPlugins: [TypeRecord] { sorted(records.filter { $0.origin == .plugin }) }
    var builtIn: [TypeRecord] { sorted(records.filter { $0.origin == .platform }) }

    private func sorted(_ types: [TypeRecord]) -> [TypeRecord] {
        types.sorted {
            let order = title(of: $0).localizedStandardCompare(title(of: $1))
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    /// Whether the owner can change the type: one they made, which no plugin installed and Marfa does not ship.
    func isEditable(_ type: TypeRecord) -> Bool { type.origin == .registered || type.origin == .unknown }

    func children(of id: String) -> [TypeRecord] { sorted(records.filter { $0.parent == id }) }

    /// The types below `id`, at any depth.
    func descendants(of id: String) -> [TypeRecord] {
        var found: [TypeRecord] = []
        var queue = [id]
        var seen: Set<String> = [id]
        while let next = queue.popLast() {
            for child in records where child.parent == next && seen.insert(child.id).inserted {
                found.append(child)
                queue.append(child.id)
            }
        }
        return found
    }

    /// How many items the type holds, its subtypes' included, as the library counts them.
    func count(of id: String) -> Int {
        access.ownItems(id) + descendants(of: id).reduce(0) { $0 + access.ownItems($1.id) }
    }

    /// The type's name for a row: the plural, which is how every list of types reads.
    func title(of id: String) -> String {
        guard let type = record(id) else { return id }
        return type.plural ?? readings[id]?.plural ?? access.plural(id) ?? type.label
    }

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
        let held = String(localized: "\(items) items.")
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
            addingGroup = nil
            wordDraft = ""
            meaningWord = nil
            queuedText = [:]
            Task { await loadReading(of: id) }
        }
        if draftedID != id, let type = record(id) {
            draftedID = id
            name = type.label
            plural = type.plural ?? ""
            descriptionText = type.description ?? ""
        }
    }

    func close() {
        openID = nil
        draftedID = nil
    }

    func reading(of id: String) -> TypeReading? { readings[id] }

    /// The types the open type could be based on: every listed type that is not it or below it.
    func basedOnChoices(for id: String) -> [TypeRecord] {
        let excluded = Set(descendants(of: id).map(\.id) + [id])
        return sorted(records.filter { !excluded.contains($0.id) })
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
    private func chain(of id: String) -> [TypeRecord] {
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

    /// The fields an item of the type holds, the nearest declaration of each, in the order of their names.
    func fields(of id: String) -> [TypeFieldRecord] {
        var byKey: [String: TypeFieldRecord] = [:]
        for type in chain(of: id) { byKey.merge(type.fields) { _, nearer in nearer } }
        return byKey.values.sorted { ($0.label ?? $0.key).localizedStandardCompare($1.label ?? $1.key) == .orderedAscending }
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

    // MARK: Changing the type

    /// Sends the name, plural or description as typed, unless nothing was typed since it was last sent or read. The server
    /// leaves out a change it already holds, so a change back to what the type held a moment ago is sent behind the one in flight.
    func commit(_ field: Field) async {
        guard let id = openID, let type = record(id), isEditable(type) else { return }
        let edit: TypeEdit
        let text: String
        switch field {
        case .name:
            text = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text != (queuedText[field] ?? type.label) else { return }
            guard !text.isEmpty else {
                fieldErrors[.name] = String(localized: "A type needs a name.")
                return
            }
            edit = .label(text)
        case .plural:
            text = plural.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text != (queuedText[field] ?? type.plural ?? "") else { return }
            edit = .plural(text)
        case .description:
            text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text != (queuedText[field] ?? type.description ?? "") else { return }
            edit = .description(text)
        default:
            return
        }
        queuedText[field] = text
        if await !apply(edit, to: id, field: field) { queuedText[field] = nil }
    }

    /// Sends the chosen parent. The choice is an act, so it is always queued; the server leaves out one the type holds.
    func setParent(_ parent: String?, of id: String) async {
        guard let type = record(id), isEditable(type) else { return }
        await apply(.parent(parent), to: id, field: .basedOn)
    }

    /// Makes `edit` on the server and reads the types again. Answers whether the server took it; on a refusal what was typed
    /// stays and the field it is about says why. `kept` runs once the change has landed, before the queue's end.
    @discardableResult
    private func apply(_ edit: TypeEdit, to id: String, field: Field, kept: @MainActor () -> Void = {}) async -> Bool {
        fieldErrors[field] = nil
        pageFailure = nil
        return await enqueue(kept: kept) { await self.send(edit, to: id, field: field) }
    }

    /// Runs `work` after every change queued before it. Changes run one at a time, in the order they were made, so each is built
    /// from the type as the one before it left it: a replacement carries no version, so two at once would send back each
    /// other's old values, and an icon written between a type's read and its replacement would be written over.
    private func enqueue(kept: @MainActor () -> Void = {}, _ work: @escaping @MainActor () async -> Bool) async -> Bool {
        pending += 1
        let previous = tail
        let task = Task { () -> Bool in
            await previous?.value
            return await work()
        }
        tail = Task { _ = await task.value }
        let took = await task.value
        if took { kept() }
        pending -= 1
        if pending == 0, closedWhileWorking {
            closedWhileWorking = false
            for draft in collectDrafts() { context.lateDraft(draft) }
        }
        return took
    }

    private func send(_ edit: TypeEdit, to id: String, field: Field) async -> Bool {
        do {
            try await calls.change(id, edit)
        } catch {
            await refused(error, field: field)
            return false
        }
        // A re-read that fails leaves the records as they were, so nothing is refilled from them.
        guard await reread() else { return true }
        if case .parent = edit { await loadReading(of: id) }
        if case .plural = edit { await loadReading(of: id) }
        // Another change is waiting behind this one: the field may hold what was typed since.
        if pending == 1 { showSaved(field, of: id) }
        return true
    }

    private func refused(_ error: TypeFailure, field: Field) async {
        switch error {
        case .invalid(let path, let message):
            let named = Self.field(named: path)
            let target = named ?? field
            fieldErrors[target] = Self.isLengthRule(message) ? Self.line(for: target) ?? message : message
        case .changedOnServer:
            pageFailure = .conflict
            await reread()
        case .owner(let failure):
            pageFailure = failure
            await context.learn(from: failure)
        case .pluginType, .guidanceByApp:
            pageFailure = Self.owner(error)
        }
    }

    /// Whether the server's sentence is about a length limit, which the page words with the limit it counts in code points.
    static func isLengthRule(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("at most") || lowered.contains("longer than") || lowered.contains("too long")
    }

    /// What a refusal of `field` says, in the page's words. The server's own sentence names the rule in its terms.
    static func line(for field: Field) -> String? {
        switch field {
        case .name: String(localized: "A name can be 100 characters at most.")
        case .plural: String(localized: "A plural can be 100 characters at most.")
        case .description: String(localized: "A description can be \(descriptionLimit) characters at most.")
        case .meaning: String(localized: "What a word means can be \(wordMeaningLimit) characters at most.")
        case .word: String(localized: "A status word starts with a letter, then letters, numbers and spaces.")
        case .basedOn, .newType: nil
        }
    }

    /// The field on the page that a path in the server's refusal names.
    static func field(named path: String?) -> Field? {
        guard let path else { return nil }
        if path.contains("status_values") { return path.hasSuffix("description") ? .meaning : .word }
        switch path {
        case "label": return .name
        case "plural": return .plural
        case "description": return .description
        case "parent": return .basedOn
        default: return nil
        }
    }

    /// Reads the types again, so the page shows what the server holds.
    @discardableResult
    private func reread() async -> Bool {
        guard let listing = try? await calls.types() else { return false }
        records = listing.types.filter { !Self.isHidden($0.id) }
        pluginTitles = listing.pluginTitles
        return true
    }

    /// Shows what the server holds in the field that was just sent, and leaves the others as typed.
    private func showSaved(_ field: Field, of id: String) {
        guard let type = record(id) else { return }
        queuedText[field] = nil
        switch field {
        case .name: name = type.label
        case .plural: plural = type.plural ?? ""
        case .description: descriptionText = type.description ?? ""
        default: break
        }
    }

    // MARK: The icon

    private(set) var iconTarget: String?
    var iconSearch = ""
    var iconSet: MarfaMarkSet
    private(set) var iconFailure: String?
    private(set) var isChangingIcon = false

    var markSets: [MarfaMarkSet] { access.markSets }
    var iconChoices: [String] { Array(access.marks(iconSearch, iconSet).prefix(60)) }
    var currentIcon: String? { iconTarget.flatMap(access.currentIcon) }

    func beginIcon(of id: String) {
        iconTarget = id
        iconSearch = ""
        iconFailure = nil
        iconSet = access.currentIcon(id).flatMap { icon in access.markSets.first { icon.hasPrefix($0.id + ":") } } ?? access.markSets.first ?? iconSet
    }

    func closeIcon() {
        guard !isChangingIcon else { return }
        iconTarget = nil
        iconFailure = nil
    }

    /// Sets the icon, or with nil takes the owner's icon away so the type shows its maker's. It waits behind the changes queued
    /// before it, which would otherwise read the type before it and write the old icon back.
    func chooseIcon(_ icon: String?) async {
        guard let id = iconTarget, !isChangingIcon else { return }
        isChangingIcon = true
        iconFailure = nil
        defer { isChangingIcon = false }
        let took = await enqueue {
            guard let refused = await self.access.setIcon(icon, id) else { return true }
            await self.context.learn(from: refused)
            self.iconFailure = OwnerWording.line(refused, on: .types)
            return false
        }
        if took { iconTarget = nil }
    }

    // MARK: A child type

    /// Opens the sheet that makes a type. A child of a type is made from its page; a new type from the list picks its own base.
    func beginChild(of parent: String?) {
        childParent = parent ?? (record("core.note") != nil ? "core.note" : records.first?.id)
        childName = ""
        fieldErrors[.newType] = nil
        isMakingChild = true
    }

    func cancelChild() {
        guard !isWorking else { return }
        isMakingChild = false
        fieldErrors[.newType] = nil
    }

    var trimmedChildName: String { childName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canMakeChild: Bool { !isWorking && !trimmedChildName.isEmpty && childParent != nil }

    /// Whether a sheet is open: the icon's, a new type's or a word's meaning.
    var hasSheet: Bool { iconTarget != nil || isMakingChild || meaningWord != nil }

    func closeSheet() {
        if iconTarget != nil { closeIcon() } else if isMakingChild { cancelChild() } else { cancelMeaning() }
    }

    /// The identifier a new type gets under `user.`: the name in lowercase letters, digits and underscores, made unique among
    /// the types listed. The server judges the rest.
    func identifier(forNamed text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var slug = String(folded.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "_" })
        while slug.contains("__") { slug = slug.replacingOccurrences(of: "__", with: "_") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if slug.isEmpty || !(slug.first?.isLetter ?? false) { slug = "type_" + slug }
        let held = Set(records.map(\.id))
        var id = "user." + slug
        var number = 2
        while held.contains(id) {
            id = "user.\(slug)_\(number)"
            number += 1
        }
        return id
    }

    func makeChild() async {
        guard canMakeChild, let parent = childParent else { return }
        fieldErrors[.newType] = nil
        let id = identifier(forNamed: trimmedChildName)
        _ = await enqueue { await self.addChild(id: id, below: parent) }
    }

    private func addChild(id: String, below parent: String) async -> Bool {
        do {
            try await calls.addChild(id: id, label: trimmedChildName, below: parent)
        } catch {
            if case .owner(let failure) = error { await context.learn(from: failure) }
            if case .invalid(_, let message) = error {
                fieldErrors[.newType] = message
            } else {
                fieldErrors[.newType] = OwnerWording.line(Self.owner(error), on: .types)
            }
            return false
        }
        isMakingChild = false
        childName = ""
        records = ((try? await calls.types().types) ?? records).filter { !Self.isHidden($0.id) }
        made = id
        return true
    }

    func acknowledgeMade() { made = nil }

    // MARK: Drafts

    /// What was typed and not kept goes back to the person when Settings closes. While a change is queued or in flight it is
    /// not yet known what the server keeps, so what is left is handed over when the queue ends, as a key's is.
    func takeDrafts() -> [OwnerDraft] {
        if isWorking {
            closedWhileWorking = true
            return []
        }
        return collectDrafts()
    }

    private func collectDrafts() -> [OwnerDraft] {
        var drafts: [OwnerDraft] = []
        if isMakingChild, !trimmedChildName.isEmpty {
            drafts.append(.typed(title: String(localized: "Type Name Not Kept"), text: trimmedChildName))
            isMakingChild = false
        }
        if let id = openID, let type = record(id), isEditable(type) {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, name != type.label {
                drafts.append(.typed(title: String(localized: "Type Name Change Not Kept"), text: name))
                self.name = type.label
            }
            let plural = plural.trimmingCharacters(in: .whitespacesAndNewlines)
            if !plural.isEmpty, plural != (type.plural ?? "") {
                drafts.append(.typed(title: String(localized: "Type Plural Not Kept"), text: plural))
                self.plural = type.plural ?? ""
            }
            let description = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if description != (type.description ?? "") {
                drafts.append(.typed(title: String(localized: "Type Description Not Kept"), text: description))
                descriptionText = type.description ?? ""
            }
        }
        if meaningWord != nil, !meaningDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drafts.append(.typed(title: String(localized: "Word Meaning Not Kept"), text: meaningDraft.trimmingCharacters(in: .whitespacesAndNewlines)))
            meaningWord = nil
        }
        if !wordDraft.isEmpty {
            drafts.append(.typed(title: String(localized: "Status Word Not Kept"), text: wordDraft))
            wordDraft = ""
            addingGroup = nil
        }
        return drafts
    }
}
