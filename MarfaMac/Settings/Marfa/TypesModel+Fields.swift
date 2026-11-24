import Foundation
import Marfa

extension TypesModel {
    // MARK: Fields

    /// The fields an item of the type holds, the nearest declaration of each, in the order of their names.
    func fields(of id: String) -> [TypeFieldRecord] {
        var byKey: [String: TypeFieldRecord] = [:]
        for type in chain(of: id) { byKey.merge(type.fields) { _, nearer in nearer } }
        return byKey.values.sorted { ($0.label ?? $0.key).localizedStandardCompare($1.label ?? $1.key) == .orderedAscending }
    }

    /// The fields the open type declares itself and the owner can change: those no type above declares. A field a child
    /// redeclares to add words is the parent's.
    func ownFields(of id: String) -> [TypeFieldRecord] {
        guard let type = record(id), isEditable(type) else { return [] }
        let above = Set(chain(of: id).dropLast().flatMap { $0.fields.keys })
        return type.fields.values.filter { !above.contains($0.key) }.sorted(by: Self.byName)
    }

    /// The fields a type above gives, which the type's page shows locked.
    func inheritedFields(of id: String) -> [TypeFieldRecord] {
        let own = Set(ownFields(of: id).map(\.key))
        return fields(of: id).filter { !own.contains($0.key) }
    }

    private static func byName(_ lhs: TypeFieldRecord, _ rhs: TypeFieldRecord) -> Bool {
        (lhs.label ?? lhs.key).localizedStandardCompare(rhs.label ?? rhs.key) == .orderedAscending
    }

    func ownField(_ key: String, of id: String) -> TypeFieldRecord? { ownFields(of: id).first { $0.key == key } }

    /// What a field is called for people: its label, else its name written for reading.
    static func title(of field: TypeFieldRecord) -> String { field.label ?? title(ofWord: field.key) }

    /// Opens a field's page, its drafts what the server holds.
    func openField(_ key: String, of id: String) {
        open(id)
        guard openFieldKey != key else { return }
        openFieldKey = key
        isAddingChoice = false
        choiceDraft = ""
        fieldErrors[.fieldMeaning] = nil
        fieldErrors[.fieldLongest] = nil
        fieldErrors[.choice] = nil
        syncFieldDrafts()
    }

    func closeField() {
        openFieldKey = nil
        isAddingChoice = false
    }

    func syncFieldDrafts() {
        guard let id = openID, let key = openFieldKey, let field = ownField(key, of: id) else { return }
        fieldMeaning = field.meaning ?? ""
        fieldLongest = field.longest.map(String.init) ?? ""
    }

    /// The line under a field in the list: its kind, and that it is required.
    func line(of field: TypeFieldRecord) -> String {
        let kind = FieldKind.title(ofKind: field.kind)
        return field.isRequired ? String(localized: "\(kind), required.") : String(localized: "\(kind).")
    }

    func commitFieldMeaning() async {
        guard let id = openID, let key = openFieldKey, let field = ownField(key, of: id) else { return }
        let text = fieldMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != (field.meaning ?? "") else { return }
        await apply(.field(key: key, .meaning(text)), to: id, field: .fieldMeaning)
    }

    func setRequired(_ on: Bool) async {
        guard let id = openID, let key = openFieldKey else { return }
        await apply(.field(key: key, .required(on)), to: id, field: .fieldRule)
    }

    func setSearchable(_ on: Bool) async {
        guard let id = openID, let key = openFieldKey else { return }
        await apply(.field(key: key, .searchable(on)), to: id, field: .fieldSearchable)
    }

    /// Sets how long a text field can be, or with nothing typed takes the limit away.
    func commitLongest() async {
        guard let id = openID, let key = openFieldKey, let field = ownField(key, of: id) else { return }
        let text = fieldLongest.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit: Int?
        if text.isEmpty {
            limit = nil
        } else if let number = Int(text), number >= 1 {
            limit = number
        } else {
            fieldErrors[.fieldLongest] = Self.line(for: .fieldLongest)
            return
        }
        guard limit != field.longest else { return }
        await apply(.field(key: key, .longest(limit)), to: id, field: .fieldLongest)
    }

    func beginChoice() {
        fieldErrors[.choice] = nil
        isAddingChoice = true
        choiceDraft = ""
    }

    func cancelChoice() {
        isAddingChoice = false
        choiceDraft = ""
        fieldErrors[.choice] = nil
    }

    /// Adds the typed choice after the ones the field offers. A choice is never renamed: an item keeps the word it holds.
    func commitChoice() async {
        guard let id = openID, let key = openFieldKey, let field = ownField(key, of: id) else { return }
        let word = choiceDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return cancelChoice() }
        guard !field.choices.contains(word) else {
            fieldErrors[.choice] = String(localized: "“\(word)” is already a choice.")
            return
        }
        if await apply(.field(key: key, .addChoice(word)), to: id, field: .choice) { cancelChoice() }
    }

    func removeChoice(_ word: String) async {
        guard let id = openID, let key = openFieldKey, let field = ownField(key, of: id) else { return }
        guard field.choices.count > 1 else {
            fieldErrors[.choice] = String(localized: "A choice field needs at least one choice.")
            return
        }
        await apply(.field(key: key, .removeChoice(word)), to: id, field: .choice)
    }

    // The sheet that renames a field.

    func beginRename() {
        guard let id = openID, let key = openFieldKey, let field = ownField(key, of: id) else { return }
        fieldNameDraft = Self.title(of: field)
        fieldErrors[.fieldName] = nil
        isRenamingField = true
    }

    func cancelRename() {
        guard !isWorking else { return }
        isRenamingField = false
        fieldErrors[.fieldName] = nil
    }

    /// Changes the name people read. The field's own name stays, since items hold their values under it.
    func commitRename() async {
        guard let id = openID, let key = openFieldKey else { return }
        let text = fieldNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            fieldErrors[.fieldName] = String(localized: "A field needs a name.")
            return
        }
        let clash = fields(of: id).contains { $0.key != key && Self.title(of: $0).compare(text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        guard !clash else {
            fieldErrors[.fieldName] = String(localized: "This type already has a field named “\(text)”.")
            return
        }
        if await apply(.field(key: key, .label(text)), to: id, field: .fieldName) { isRenamingField = false }
    }

    // The sheet that adds a field.

    func beginField() {
        newFieldName = ""
        newFieldKind = .text
        newFieldChoices = ""
        newFieldRequired = false
        newFieldSearchable = true
        fieldErrors[.newField] = nil
        isAddingField = true
    }

    func cancelField() {
        guard !isWorking else { return }
        isAddingField = false
        fieldErrors[.newField] = nil
    }

    var trimmedFieldName: String { newFieldName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The choices typed for a new choice field, one for each comma or line, without blanks or repeats.
    var typedChoices: [String] {
        var seen: Set<String> = []
        return newFieldChoices.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var canMakeField: Bool { !isWorking && !trimmedFieldName.isEmpty && (newFieldKind != .choice || !typedChoices.isEmpty) }

    /// The name a new field gets on the server, made from what was typed and different from every field the type holds.
    func key(forNamed text: String, in id: String) -> String {
        let slug = Self.slug(of: text, prefix: "field_")
        let held = Set(fields(of: id).map(\.key))
        var key = slug
        var number = 2
        while held.contains(key) {
            key = "\(slug)_\(number)"
            number += 1
        }
        return key
    }

    func makeField() async {
        guard canMakeField, let id = openID else { return }
        let name = trimmedFieldName
        let clash = fields(of: id).contains { Self.title(of: $0).compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        guard !clash else {
            fieldErrors[.newField] = String(localized: "This type already has a field named “\(name)”.")
            return
        }
        let edit = TypeEdit.addField(
            NewFieldRecord(
                key: key(forNamed: name, in: id), label: name, kind: newFieldKind, choices: newFieldKind == .choice ? typedChoices : [],
                isRequired: newFieldRequired, isSearchable: newFieldSearchable))
        if await apply(edit, to: id, field: .newField) { isAddingField = false }
    }

    // MARK: Rules

    /// What the type's page offers for how long feed items stay: the days offered, and the type's own window if it is another.
    func feedWindows(for id: String) -> [FeedWindow] {
        var windows: [FeedWindow] = [7, 30, 90, 365].map { .days($0) }
        if case .days(let own)? = record(id)?.feedWindow, !windows.contains(.days(own)) {
            windows.append(.days(own))
            windows.sort { Self.rank($0) < Self.rank($1) }
        }
        return [.never] + windows
    }

    private static func rank(_ window: FeedWindow) -> Int {
        if case .days(let days) = window { days } else { Int.max }
    }

    /// The window the type's page shows chosen: its own, else (where no type above gives one) that Marfa keeps feed items.
    func feedSelection(of id: String) -> FeedWindow? {
        guard let type = record(id) else { return nil }
        if let own = type.feedWindow { return own }
        return hasParent(type) ? nil : .never
    }

    func mergeSelection(of id: String) -> String? {
        guard let type = record(id) else { return nil }
        if let own = type.mergeStrategy { return own }
        return hasParent(type) ? nil : "last_writer_wins"
    }

    func hasParent(_ type: TypeRecord) -> Bool { type.parent.flatMap(record) != nil }

    func setFeedWindow(_ window: FeedWindow?, of id: String) async {
        guard let type = record(id), isEditable(type), window != feedSelection(of: id) else { return }
        await apply(.feedWindow(window), to: id, field: .feed)
    }

    func setMergeStrategy(_ name: String?, of id: String) async {
        guard let type = record(id), isEditable(type), name != mergeSelection(of: id) else { return }
        await apply(.mergeStrategy(name), to: id, field: .merge)
    }

    /// The lengths Keep Versions offers, and the type's own where it is another.
    func versionDays(for id: String) -> [Int] {
        var days = [7, 30, 90, 365, 730]
        if case .days(let own)? = record(id)?.versionWindow, !days.contains(own) {
            days.append(own)
            days.sort()
        }
        return days
    }

    /// What the type sets for its versions; nil where it leaves them to the type above or to History.
    func versionSelection(of id: String) -> VersionWindow? { record(id)?.versionWindow }

    /// Whether a type above sets how long versions stay, so leaving it to the type above is not the same as History.
    func versionsComeFromAbove(_ id: String) -> Bool { chain(of: id).dropLast().contains { $0.versionWindow != nil } }

    /// A change to how long versions stay, worked out from what the server holds just before it is sent.
    struct VersionChange: Equatable {
        /// What the type keeps now.
        let now: VersionKeeping
        /// What it keeps after the change.
        let new: VersionKeeping
        /// Whether the change can delete versions, which can't be recovered, so it is sent only once the person agrees.
        var mayDelete: Bool { !new.keepsAll(of: now) }
    }

    /// Sets how long the type keeps versions, or with nil leaves it to the type above. It waits behind the changes queued
    /// before it, then reads the type, the types above and History's settings again: a change that can delete versions is
    /// sent only once `confirm` agrees to what that read says, and only while the server still holds what it read.
    func setVersionWindow(_ window: VersionWindow?, of id: String, confirm: @escaping @MainActor (VersionChange) async -> Bool) async {
        guard let type = record(id), isEditable(type), window != .custom, window != versionSelection(of: id) else { return }
        let days: Int? = if case .days(let days)? = window { days } else { nil }
        fieldErrors[.versions] = nil
        pageFailure = nil
        _ = await enqueue { () async -> Bool in
            let read: VersionKeepingReading
            do throws(TypeFailure) {
                read = try await self.calls.versionKeeping(of: id)
            } catch {
                await self.refused(error, field: .versions)
                return false
            }
            let change = VersionChange(now: read.now, new: read.after(days))
            if change.mayDelete, !(await confirm(change)) { return false }
            return await self.send(.versionWindow(days, readAs: read), to: id, field: .versions)
        }
    }

    /// Reads which types strict mode names, where the sign-in may read the configuration. A failed read leaves the switch out.
    func loadStrict() async {
        guard context.grants().contains(.configManage), let read = try? await context.calls.sourceLimit() else {
            strictTypes = nil
            return
        }
        strictTypes = Set(read.strictTypes ?? [])
        strictInstance = read.instanceID
    }

    func isStrict(_ id: String) -> Bool { strictTypes?.contains(id) ?? false }

    /// Adds the type to strict mode or takes it out, through the app's one enforcement writer, which changes only this type's
    /// place in strict mode and sends the other levers back as the server holds them. A refusal leaves the switch as the server
    /// holds it.
    func setStrict(_ isOn: Bool, of id: String) async {
        guard let type = record(id), isEditable(type), isOn != isStrict(id) else { return }
        fieldErrors[.strict] = nil
        strictTypes?.formSymmetricDifference([id])
        do throws(EnforcementSettings.Failure) {
            let written = try await context.writeEnforcement(readFrom: strictInstance) { levers in
                var strict = levers.strictTypes ?? []
                strict.removeAll { $0 == id }
                if isOn { strict.append(id) }
                levers.strictTypes = strict.isEmpty ? nil : strict
            }
            strictTypes = Set(written.strictTypes ?? [])
        } catch {
            switch error {
            case .owner(let failure):
                await context.learn(from: failure)
                fieldErrors[.strict] = OwnerWording.line(failure, on: .types)
            case .anotherMarfa, .changedElsewhere:
                fieldErrors[.strict] = InstanceConfigFailure.instanceChanged.message
            }
            let shown = strictTypes
            await loadStrict()
            if strictTypes == nil, let shown { strictTypes = shown.symmetricDifference([id]) }
        }
    }
}
