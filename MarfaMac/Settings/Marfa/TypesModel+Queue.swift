import Foundation
import Marfa

extension TypesModel {
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
        case .guidance:
            // Guidance is Markdown a plugin or the command line may have left with trailing lines, so what the type holds
            // is compared as it reads here: a field opened and left again sends nothing.
            text = guidanceText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text != (queuedText[field] ?? (type.guidance ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            guard Self.length(of: text) <= Self.guidanceLimit else {
                fieldErrors[.guidance] = Self.line(for: .guidance)
                return
            }
            fieldErrors[.guidance] = nil
            edit = .guidance(text)
        default:
            return
        }
        queuedText[field] = text
        if await !apply(edit, to: id, field: field), !(field == .guidance && guidanceNeedsCommand) { queuedText[field] = nil }
    }

    /// Sends the chosen parent. The choice is an act, so it is always queued; the server leaves out one the type holds.
    func setParent(_ parent: String?, of id: String) async {
        guard let type = record(id), isEditable(type) else { return }
        await apply(.parent(parent), to: id, field: .basedOn)
    }

    /// Makes `edit` on the server and reads the types again. Answers whether the server took it; on a refusal what was typed
    /// stays and the field it is about says why. `kept` runs once the change has landed, before the queue's end.
    @discardableResult
    func apply(_ edit: TypeEdit, to id: String, field: Field, kept: @MainActor () -> Void = {}) async -> Bool {
        fieldErrors[field] = nil
        pageFailure = nil
        return await enqueue(kept: kept) { await self.send(edit, to: id, field: field) }
    }

    /// Runs `work` after every change queued before it. Changes run one at a time, in the order they were made, so each is built
    /// from the type as the one before it left it: a replacement carries no version, so two at once would send back each
    /// other's old values, and an icon written between a type's read and its replacement would be written over.
    func enqueue(kept: @MainActor () -> Void = {}, _ work: @escaping @MainActor () async -> Bool) async -> Bool {
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
        if case .guidance = edit {
            guidanceNeedsCommand = false
            await loadReading(of: id)
        }
        // Another change is waiting behind this one: the field may hold what was typed since.
        if pending == 1 { showSaved(field, of: id) }
        return true
    }

    private func refused(_ error: TypeFailure, field: Field) async {
        switch error {
        case .invalid(let path, let message):
            let named = field == .newField ? nil : Self.field(named: path)
            let target = named ?? field
            fieldErrors[target] = Self.isLengthRule(message) ? Self.line(for: target) ?? message : message
        case .changedOnServer:
            pageFailure = .conflict
            await reread()
        case .owner(let failure):
            pageFailure = failure
            await context.learn(from: failure)
        case .guidanceByApp:
            // The typed text stays in its field, and the command that writes it is given beside it.
            guidanceNeedsCommand = true
        case .canceled:
            // The owner closed the sign-in: nothing was sent and nothing is said.
            break
        case .pluginType, .inUse, .hasSubtypes:
            pageFailure = Self.owner(error)
        }
    }

    /// The command that writes a type's guidance from the command line: the type's definition in a file, with the guidance in
    /// the file of the same name that ends in `.md` beside it.
    static func guidanceCommand(for id: String) -> String { "marfa types replace \(id) --file \(id).json" }

    func copyGuidanceCommand(_ command: String) {
        OwnerClipboard.copyText(command)
        copiedCommand = command
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
        case .guidance: String(localized: "Guidance can be \(guidanceLimit) characters at most.")
        case .meaning: String(localized: "What a word means can be \(wordMeaningLimit) characters at most.")
        case .word: String(localized: "A status word starts with a letter, then letters, numbers and spaces.")
        case .fieldName: String(localized: "A field’s name can be 100 characters at most.")
        case .fieldMeaning: String(localized: "What a field means can be \(fieldMeaningLimit) characters at most.")
        case .fieldLongest: String(localized: "The longest a field can be is a whole number of at least 1.")
        case .basedOn, .newType, .newField, .fieldRule, .fieldSearchable, .fieldRemove, .choice, .feed, .merge: nil
        }
    }

    /// The field on the page that a path in the server's refusal names.
    static func field(named path: String?) -> Field? {
        guard let path else { return nil }
        if path.contains("status_values") { return path.hasSuffix("description") ? .meaning : .word }
        if path.hasPrefix("fields.") {
            if path.hasSuffix(".description") { return .fieldMeaning }
            if path.hasSuffix(".label") { return .fieldName }
            if path.hasSuffix(".max_length") { return .fieldLongest }
            if path.hasSuffix(".enum_values") { return .choice }
        }
        if path.hasPrefix("retention_policy") { return .feed }
        if path.hasPrefix("merge_policy") { return .merge }
        switch path {
        case "label": return .name
        case "plural": return .plural
        case "description": return .description
        case "guidance": return .guidance
        case "parent": return .basedOn
        default: return nil
        }
    }

    /// Shows what the server holds in the field that was just sent, and leaves the others as typed.
    private func showSaved(_ field: Field, of id: String) {
        guard let type = record(id) else { return }
        queuedText[field] = nil
        switch field {
        case .name: name = type.label
        case .plural: plural = type.plural ?? ""
        case .description: descriptionText = type.description ?? ""
        case .guidance: guidanceText = type.guidance ?? ""
        case .fieldMeaning, .fieldLongest, .fieldName, .fieldRule, .fieldSearchable: syncFieldDrafts()
        default: break
        }
    }

    /// What was typed and not kept goes back to the person when Settings closes. While a change is queued or in flight it is
    /// not yet known what the server keeps, so what is left is handed over when the queue ends, as a key's is.
    func takeDrafts() -> [OwnerDraft] {
        if isWorking {
            closedWhileWorking = true
            return []
        }
        return collectDrafts()
    }
}
