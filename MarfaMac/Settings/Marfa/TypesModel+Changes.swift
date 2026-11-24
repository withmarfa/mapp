import Foundation
import Marfa

extension TypesModel {
    // MARK: Removing

    /// Removes the open field. Each item keeps the value it holds under the field's name (`types/field-removed`).
    func removeField() async {
        guard let id = openID, let key = openFieldKey else { return }
        if await apply(.removeField(key: key), to: id, field: .fieldRemove) { openFieldKey = nil }
    }

    /// Deletes the open type, which Marfa allows only while no item and no other type holds it. Its refusal is told in words.
    func deleteType() async {
        guard let id = openID, let type = record(id), isEditable(type), !isDeleting else { return }
        isDeleting = true
        deleteFailure = nil
        defer { isDeleting = false }
        do {
            try await calls.delete(id)
        } catch {
            if case .owner(let failure) = error { await context.learn(from: failure) }
            deleteFailure = deleteLine(for: error, type: id)
            return
        }
        await reread()
        deleted = id
    }

    func acknowledgeDeleted() { deleted = nil }

    private func deleteLine(for failure: TypeFailure, type id: String) -> String {
        let name = title(of: id)
        switch failure {
        case .inUse(let items, let settings):
            if let items, items > 0 {
                return String(AttributedString(localized: "\(name) still holds ^[\(items) item](inflect: true), in the bin too. Move them to another type first.").characters)
            }
            if settings > 0 { return String(localized: "A folder, view or webhook still uses \(name). Change it first.") }
            return String(localized: "Something still uses \(name), so it was kept.")
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
    var hasSheet: Bool { iconTarget != nil || isMakingChild || meaningWord != nil || isAddingField || isRenamingField }

    func closeSheet() {
        if iconTarget != nil {
            closeIcon()
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

    func collectDrafts() -> [OwnerDraft] {
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
