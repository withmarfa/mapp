import Foundation
import Marfa

extension TypesModel {
    // MARK: Removing

    /// Removes the open field. Each item keeps the value it holds under the field's name (`types/field-removed`).
    func removeField() async {
        guard let id = openID, let key = openFieldKey else { return }
        if await apply(.removeField(key: key), to: id, field: .fieldRemove) { openFieldKey = nil }
    }

    /// Deletes the open type once the person has agreed, while no item and no setting uses it. Where the server says something
    /// does, the sheet that asks what happens to them opens instead. Any other refusal is told in words.
    func deleteType() async {
        guard let id = openID, let type = record(id), isEditable(type), !isDeleting else { return }
        isDeleting = true
        deleteFailure = nil
        defer { isDeleting = false }
        let took = await enqueue { () async -> Bool in
            do throws(TypeFailure) {
                try await self.calls.delete(id, force: false)
                return true
            } catch {
                if case .owner(let failure) = error { await self.context.learn(from: failure) }
                if case .inUse(let items, let settings) = error {
                    self.beginDelete(use: (items, settings))
                } else {
                    self.deleteFailure = self.deleteLine(for: error, type: id)
                }
                return false
            }
        }
        guard took else { return }
        await reread()
        deleted = id
    }

    func acknowledgeDeleted() { deleted = nil }

    // MARK: Deleting a type in use

    /// What happens to the items and settings that use a type being deleted.
    enum DeleteChoice: Hashable {
        /// They move to another type first, and the settings name it.
        case move
        /// The type is deleted with them as they are: the items can be read, and edited only once the type exists again.
        case leave
    }

    /// Opens the sheet that asks what happens to what uses the open type. A type that others are based on can't be deleted
    /// either way, so that is said on the row instead.
    func beginDelete(use: (items: Int?, settings: Int)? = nil) {
        guard let id = openID, let type = record(id), isEditable(type) else { return }
        guard children(of: id).isEmpty else {
            deleteFailure = deleteLine(for: .hasSubtypes(children(of: id).map(\.id)), type: id)
            return
        }
        deleteFailure = nil
        deleteSheetFailure = nil
        refusedUse = use
        deleteChoice = .move
        let choices = moveChoices(for: id)
        moveTarget = type.parent.flatMap { parent in choices.first { $0.id == parent }?.id } ?? choices.first?.id
        movePreview = nil
        movePreviewFailure = nil
        isConfirmingDelete = true
        Task { await readMove() }
    }

    /// The types the items can move to: every listed type that is not the one deleted or below it.
    func moveChoices(for id: String) -> [TypeRecord] { basedOnChoices(for: id) }

    func setMoveTarget(_ target: String?) {
        guard target != moveTarget else { return }
        moveTarget = target
        movePreview = nil
        movePreviewFailure = nil
        Task { await readMove() }
    }

    /// Reads what moving to the chosen type would do. An answer for a type no longer chosen is dropped.
    func readMove() async {
        guard let id = openID, let target = moveTarget else { return }
        do {
            let preview = try await calls.previewMove(of: id, to: target)
            guard moveTarget == target, openID == id else { return }
            movePreview = preview
        } catch {
            guard moveTarget == target, openID == id else { return }
            if case .owner(let failure) = error { await context.learn(from: failure) }
            movePreviewFailure = OwnerWording.line(Self.owner(error), on: .types)
        }
    }

    func cancelDelete() {
        guard !isDeleting else { return }
        isConfirmingDelete = false
        deleteSheetFailure = nil
    }

    /// The settings a move can't change, which hold it back until they are changed.
    var blockedSettings: [TypeSettingRecord] { movePreview?.settings.filter { $0.blocked != nil } ?? [] }

    var canConfirmDelete: Bool {
        guard !isDeleting else { return false }
        switch deleteChoice {
        case .move: return moveTarget != nil && movePreview != nil && blockedSettings.isEmpty
        case .leave: return true
        }
    }

    /// Moves the items and then deletes the type, or deletes it and leaves them, as the person chose. The type is deleted
    /// only once the move has left no item of it; otherwise the sheet says what is left and the type stays.
    func confirmDelete() async {
        guard let id = openID, canConfirmDelete else { return }
        let choice = deleteChoice
        let target = moveTarget
        isDeleting = true
        deleteSheetFailure = nil
        defer { isDeleting = false }
        let took = await enqueue { () async -> Bool in
            do throws(TypeFailure) {
                if choice == .move, let target {
                    let result = try await self.calls.move(id, to: target)
                    guard result.isDone else {
                        self.deleteSheetFailure = self.moveLine(result, type: id)
                        return false
                    }
                }
                try await self.calls.delete(id, force: choice == .leave)
                return true
            } catch {
                if case .owner(let failure) = error { await self.context.learn(from: failure) }
                self.deleteSheetFailure = self.deleteLine(for: error, type: id)
                return false
            }
        }
        await reread()
        guard took else {
            await readMove()
            return
        }
        isConfirmingDelete = false
        deleted = id
    }

    private func moveLine(_ result: TypeMoveResult, type id: String) -> String {
        let name = title(of: id)
        if let problem = result.problem { return String(localized: "\(problem) \(name) was kept.") }
        if result.remaining > 0 {
            return String(AttributedString(localized: "^[\(result.remaining) item](inflect: true) couldn’t move, so \(name) was kept.").characters)
        }
        return String(localized: "Items this sign-in can’t see are still of this type, so \(name) was kept.")
    }

    private func deleteLine(for failure: TypeFailure, type id: String) -> String {
        let name = title(of: id)
        switch failure {
        case .inUse(let items, let settings):
            if let items, items > 0 {
                return String(AttributedString(localized: "\(name) still holds ^[\(items) item](inflect: true), in the bin too. Move them to another type first.").characters)
            }
            if settings > 0 { return String(localized: "A folder, view or webhook still uses \(name). Change it first.") }
            return String(localized: "Something still uses \(name), so it was kept.")
        case .moveBlocked(let message): return String(localized: "\(message) Nothing moved.")
        case .hasSubtypes(let ids):
            let names = ids.map { title(of: $0) }.formatted(.list(type: .and))
            return ids.isEmpty
                ? String(localized: "Types are based on \(name), so it was kept.")
                : String(localized: "Types are based on \(name): \(names). Change or delete those first.")
        case .changedOnServer: return OwnerWording.line(.conflict, on: .types)
        default: return OwnerWording.line(Self.owner(failure), on: .types)
        }
    }

    /// How many items the open type holds, as the delete's line says, without those of the types below it.
    func ownItemCount(of id: String) -> Int { access.ownItems(id) }

    // MARK: The icon

    var markSets: [MarfaMarkSet] { access.markSets }
    var iconChoices: [String] { Array(access.marks(iconSearch, iconSet).prefix(60)) }
    var currentIcon: String? { isChoosingChildIcon ? childIcon : iconTarget.flatMap(access.currentIcon) }

    /// Opens the icon sheet for the type being made, over the New Type sheet.
    func beginChildIcon() {
        isChoosingChildIcon = true
        iconSearch = ""
        iconFailure = nil
        iconSet = childIcon.flatMap { icon in access.markSets.first { icon.hasPrefix($0.id + ":") } } ?? access.markSets.first ?? iconSet
    }

    func beginIcon(of id: String) {
        iconTarget = id
        iconSearch = ""
        iconFailure = nil
        iconSet = access.currentIcon(id).flatMap { icon in access.markSets.first { icon.hasPrefix($0.id + ":") } } ?? access.markSets.first ?? iconSet
    }

    func closeIcon() {
        guard !isChangingIcon else { return }
        iconTarget = nil
        isChoosingChildIcon = false
        iconFailure = nil
    }

    /// Sets the icon, or with nil takes the owner's icon away so the type shows its maker's. It waits behind the changes queued
    /// before it, which would otherwise read the type before it and write the old icon back.
    func chooseIcon(_ icon: String?) async {
        if isChoosingChildIcon {
            childIcon = icon
            isChoosingChildIcon = false
            return
        }
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

    // MARK: A new type

    /// Opens the sheet that makes a type: from a type's page based on that type, from the list based on nothing until the
    /// person picks a base.
    func beginChild(of parent: String?) {
        childParent = parent
        childName = ""
        childPlural = ""
        childIcon = nil
        fieldErrors[.newType] = nil
        isMakingChild = true
    }

    func cancelChild() {
        guard !isWorking else { return }
        isMakingChild = false
        isChoosingChildIcon = false
        fieldErrors[.newType] = nil
    }

    var trimmedChildName: String { childName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedChildPlural: String { childPlural.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canMakeChild: Bool { !isWorking && !trimmedChildName.isEmpty }

    /// The plural the server makes from a label where the type names none (`types/plural`): `y` after a lowercase
    /// consonant takes `ies`, `s`, `x`, `z`, `ch` and `sh` take `es`, and any other ending takes `s`.
    static func regularPlural(of label: String) -> String {
        guard let last = label.last else { return label }
        let stem = label.dropLast()
        if last == "y", let before = stem.last, before.isLowercase, !"aeiou".contains(before) { return stem + "ies" }
        if "sxz".contains(last) || label.hasSuffix("ch") || label.hasSuffix("sh") { return label + "es" }
        return label + "s"
    }

    /// Whether a sheet is open: the icon's, a new type's, a field's, a word's meaning or the delete's.
    var hasSheet: Bool {
        iconTarget != nil || isChoosingChildIcon || isMakingChild || meaningWord != nil || isAddingField || isRenamingField || isConfirmingDelete
    }

    func closeSheet() {
        if iconTarget != nil || isChoosingChildIcon {
            closeIcon()
        } else if isConfirmingDelete {
            cancelDelete()
        } else if isMakingChild {
            cancelChild()
        } else if isAddingField {
            cancelField()
        } else if isRenamingField {
            cancelRename()
        } else {
            cancelMeaning()
        }
    }

    /// The identifier a new type gets under `user.`: the name in lowercase letters, digits and underscores, made unique among
    /// the types listed. The server judges the rest.
    func identifier(forNamed text: String) -> String {
        let slug = Self.slug(of: text, prefix: "type_")
        let held = Set(records.map(\.id))
        var id = "user." + slug
        var number = 2
        while held.contains(id) {
            id = "user.\(slug)_\(number)"
            number += 1
        }
        return id
    }

    /// Lowercase letters, digits and underscores from `text`, starting with a letter (after `prefix` where it does not).
    static func slug(of text: String, prefix: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var slug = String(folded.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "_" })
        while slug.contains("__") { slug = slug.replacingOccurrences(of: "__", with: "_") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if slug.isEmpty || !(slug.first?.isLetter ?? false) { slug = prefix + slug }
        return slug
    }

    func makeChild() async {
        guard canMakeChild else { return }
        fieldErrors[.newType] = nil
        let new = NewTypeRecord(
            id: identifier(forNamed: trimmedChildName), label: trimmedChildName, plural: trimmedChildPlural, icon: childIcon, parent: childParent)
        _ = await enqueue { await self.addType(new) }
    }

    private func addType(_ new: NewTypeRecord) async -> Bool {
        let id = new.id
        do {
            try await calls.addType(new)
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
        childPlural = ""
        childIcon = nil
        records = ((try? await calls.types().types) ?? records).filter { !Self.isHidden($0.id) }
        made = id
        return true
    }

    func acknowledgeMade() { made = nil }

    // MARK: Drafts

    func collectDrafts() -> [OwnerDraft] {
        var drafts: [OwnerDraft] = []
        if isMakingChild {
            if !trimmedChildName.isEmpty { drafts.append(.typed(title: String(localized: "Type Name Not Kept"), text: trimmedChildName)) }
            if !trimmedChildPlural.isEmpty { drafts.append(.typed(title: String(localized: "Type Plural Not Kept"), text: trimmedChildPlural)) }
            isMakingChild = false
            isChoosingChildIcon = false
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
            let guidance = guidanceText.trimmingCharacters(in: .whitespacesAndNewlines)
            if guidance != (type.guidance ?? "").trimmingCharacters(in: .whitespacesAndNewlines) {
                drafts.append(.typed(title: String(localized: "Type Guidance Not Kept"), text: guidance))
                guidanceText = type.guidance ?? ""
                guidanceNeedsCommand = false
            }
        }
        if meaningWord != nil, !meaningDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drafts.append(.typed(title: String(localized: "Word Meaning Not Kept"), text: meaningDraft.trimmingCharacters(in: .whitespacesAndNewlines)))
            meaningWord = nil
        }
        if isAddingField {
            if !newFieldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                drafts.append(.typed(title: String(localized: "Field Name Not Kept"), text: newFieldName))
            }
            let choices = newFieldChoices.trimmingCharacters(in: .whitespacesAndNewlines)
            if !choices.isEmpty { drafts.append(.typed(title: String(localized: "New Field Choices Not Kept"), text: choices)) }
            isAddingField = false
        }
        if let id = openID, let key = openFieldKey, let field = ownFields(of: id).first(where: { $0.key == key }) {
            let meaning = fieldMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
            if meaning != (field.meaning ?? "") {
                drafts.append(.typed(title: String(localized: "Field Meaning Not Kept"), text: meaning))
                fieldMeaning = field.meaning ?? ""
            }
            let longest = fieldLongest.trimmingCharacters(in: .whitespacesAndNewlines)
            if longest != (field.longest.map(String.init) ?? "") {
                drafts.append(.typed(title: String(localized: "Field Longest Not Kept"), text: longest))
                fieldLongest = field.longest.map(String.init) ?? ""
            }
            let renamed = fieldNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if isRenamingField, !renamed.isEmpty, renamed != Self.title(of: field) {
                drafts.append(.typed(title: String(localized: "Field Name Change Not Kept"), text: renamed))
            }
            let choice = choiceDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if isAddingChoice, !choice.isEmpty { drafts.append(.typed(title: String(localized: "Choice Not Kept"), text: choice)) }
        }
        isRenamingField = false
        isAddingChoice = false
        choiceDraft = ""
        if !wordDraft.isEmpty {
            drafts.append(.typed(title: String(localized: "Status Word Not Kept"), text: wordDraft))
            wordDraft = ""
            addingGroup = nil
        }
        return drafts
    }
}
