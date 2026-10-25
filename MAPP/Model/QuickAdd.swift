import Foundation
import Observation

/// A window's quick-add panel: the kind of item being made, what the person typed, and where it goes. The draft
/// outlives the panel being put away, so nothing typed is lost until it is added or handed to the clipboard.
@Observable
final class QuickAdd {
    struct File: Equatable {
        var name: String
        var data: Data
    }

    struct Draft: Equatable {
        var typeID: String
        var title = ""
        var body = ""
        /// How many characters of the body come before the caret, so the page can put it back there.
        var caret: Int?
        var properties: [String: PropertyValue] = [:]
        var parentID: ItemID?
        var file: File?

        /// Whether the person put anything in it worth keeping: text or a file. A property chosen alone is not.
        var hasContent: Bool { !NoteName.trimmed(title).isEmpty || !isBlank(body) || file != nil }

        /// What the clipboard is given when the draft cannot be added: the title, then the body.
        var text: String? {
            let parts = [NoteName.trimmed(title), isBlank(body) ? "" : body].filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }

        /// Where the page puts the caret, or nil where no body was typed.
        var pageCaret: PageCaret? {
            isBlank(body) ? nil : PageCaret(offset: caret, in: body)
        }

        /// Clears what was typed for the next item, keeping its kind and place.
        mutating func clearForNext() {
            title = ""
            body = ""
            caret = nil
            properties = [:]
            file = nil
        }

        private func isBlank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var draft: Draft?
    var isPresented = false
    /// Create More: adding an item clears the panel for the next instead of opening the item.
    var createsMore = false
    /// While a file is being added, so the panel does not add it twice.
    private(set) var isSaving = false

    init() { Self.open.add(self) }

    /// Every window's quick add, so a quit can hand each draft to the clipboard.
    private static let open = NSHashTable<QuickAdd>.weakObjects()

    /// Gives every window's draft to the clipboard through `notices`, as the app quits.
    static func handOffAll(to notices: Notices) {
        for quickAdd in open.allObjects { quickAdd.handOff(to: notices) }
    }

    /// Gives a draft with anything in it to the clipboard through `notices`, which tells the person, as the window
    /// closes or the app quits, since nothing else would keep it.
    func handOff(to notices: Notices) {
        defer {
            draft = nil
            isPresented = false
        }
        guard let draft, draft.hasContent else { return }
        notices.notKept(
            String(localized: "Item Not Added"), text: draft.text,
            reason: draft.text == nil
                ? String(localized: "Quick add closed before the item was added. Add it again.")
                : String(localized: "Quick add closed before the item was added."))
    }

    /// The window shows another library, whose items and fields the draft's place and properties do not name.
    func libraryChanged() {
        draft?.parentID = nil
        draft?.properties = [:]
    }

    fileprivate func saving(_ value: Bool) { isSaving = value }

    // MARK: What is remembered

    /// The defaults key for the kind last added, which a new draft starts with.
    static let lastTypeKey = "quickAddLastType"
    /// The defaults key for the fields kept showing in the panel, for each library and kind.
    static let pinsKey = "quickAddPinnedFields"

    /// The fields kept showing, by library then kind, as the defaults hold them.
    typealias Pins = [String: [String: [String]]]

    static func pins(from text: String) -> Pins {
        (try? JSONDecoder().decode(Pins.self, from: Data(text.utf8))) ?? [:]
    }

    static func text(of pins: Pins) -> String {
        (try? JSONEncoder().encode(pins)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// The pins with `key` kept showing, or no longer, for `typeID` in `library`.
    static func pinning(_ key: String, _ pinned: Bool, typeID: String, library: String, in pins: Pins) -> Pins {
        var pins = pins
        var keys = pins[library]?[typeID] ?? []
        keys.removeAll { $0 == key }
        if pinned { keys.append(key) }
        pins[library, default: [:]][typeID] = keys.isEmpty ? nil : keys
        if pins[library]?.isEmpty == true { pins[library] = nil }
        return pins
    }

    /// The sidebar's types in its order, groups opened.
    static func typeIDs(of nodes: [TypeNode]) -> [TypeID] {
        nodes.flatMap { node in (node.type.map { [$0] } ?? []) + typeIDs(of: node.children) }
    }

    // MARK: Kinds and fields

    /// The kinds of item the panel offers, by label, with File after them where the catalogue has files.
    static func types(in library: any ItemLibrary) -> [ItemTypeOption] {
        let catalogue = library.catalogue
        var types = library.creatableTypes
        if catalogue.itemTypes[.file] != nil {
            types.append(ItemTypeOption(id: .file, label: TypeSymbol.label(for: .file, in: catalogue), symbol: TypeSymbol.name(for: .file, in: catalogue)))
        }
        return types
    }

    /// The kinds shown as chips, the sidebar's own first in its order, then File; the rest sit behind More. The
    /// chosen kind is always shown.
    static func chips(_ types: [ItemTypeOption], shown: [TypeID], chosen: String?) -> (chips: [ItemTypeOption], more: [ItemTypeOption]) {
        var chips = shown.compactMap { id in types.first { $0.id == id } }
        if chips.isEmpty, let note = types.first(where: { $0.id == TypeID("core.note") }) { chips.append(note) }
        if let file = types.first(where: { $0.id == .file }), !chips.contains(file) { chips.append(file) }
        if let chosen, let option = types.first(where: { $0.id.rawValue == chosen }), !chips.contains(option) {
            chips.append(option)
        }
        return (chips, types.filter { !chips.contains($0) })
    }

    /// The fields the panel offers for a kind: those the person can set, not its title or text.
    static func fields(of typeID: String, in catalogue: Catalogue) -> [ItemTypeInfo.Field] {
        guard let info = catalogue.itemTypes[TypeID(typeID)] else { return [] }
        return info.fields.filter { field in
            guard field.key != info.titleKey, field.key != info.bodyKey else { return false }
            if case .other = field.kind { return false }
            return true
        }
    }

    /// Whether the kind keeps text, so the panel offers a body.
    static func hasBody(_ typeID: String, in catalogue: Catalogue) -> Bool {
        catalogue.itemTypes[TypeID(typeID)]?.bodyKey != nil
    }

    static func isFile(_ typeID: String, in catalogue: Catalogue) -> Bool {
        catalogue.isFileType(TypeID(typeID))
    }

    /// Whether the draft can be added: a title, or a file for a file, and a value for every required field.
    static func canSave(_ draft: Draft, in catalogue: Catalogue) -> Bool {
        if isFile(draft.typeID, in: catalogue) { return draft.file != nil }
        guard !NoteName.trimmed(draft.title).isEmpty else { return false }
        return fields(of: draft.typeID, in: catalogue).allSatisfy { field in
            !field.required || draft.properties[field.key].map { $0 != .null } == true
        }
    }
}

extension Browser {
    /// Shows quick add, with `typeID` chosen where one is given. A draft put away comes back as it was left;
    /// otherwise the kind is `remembered`, the last one added, then the place's own type, then a note, and the
    /// item goes under the collection being shown where its kind can.
    func openQuickAdd(typeID: String? = nil, remembered: String? = nil, in library: any ItemLibrary) {
        leaveSettings()
        palette = nil
        let types = QuickAdd.types(in: library).map(\.id.rawValue)
        func offered(_ id: String?) -> String? { id.flatMap { types.contains($0) ? $0 : nil } }
        if quickAdd.draft == nil {
            var placeType: String?
            if case .itemType(let id) = item { placeType = id }
            guard let kind = offered(typeID) ?? offered(remembered) ?? offered(placeType) ?? offered("core.note") ?? types.first
            else { return }
            var draft = QuickAdd.Draft(typeID: kind)
            if case .collection(let id) = item { draft.parentID = id }
            quickAdd.draft = draft
            chooseQuickAddType(kind, in: library)
        } else if let typeID = offered(typeID) {
            chooseQuickAddType(typeID, in: library)
        }
        quickAdd.isPresented = true
    }

    /// Changes the kind of item, keeping what was typed. A place or property the new kind cannot take is dropped.
    func chooseQuickAddType(_ typeID: String, in library: any ItemLibrary) {
        guard var draft = quickAdd.draft else { return }
        draft.typeID = typeID
        let keys = Set(QuickAdd.fields(of: typeID, in: library.catalogue).map(\.key))
        draft.properties = draft.properties.filter { keys.contains($0.key) }
        if let parent = draft.parentID {
            let canHold = !QuickAdd.isFile(typeID, in: library.catalogue)
                && library.creationParentCandidates(typeID: typeID).contains { $0.id == parent }
            if !canHold { draft.parentID = nil }
        }
        quickAdd.draft = draft
    }

    /// Puts quick add away without adding anything; the draft waits for the panel to come back.
    func putAwayQuickAdd() {
        quickAdd.isPresented = false
        if quickAdd.draft?.hasContent == false { quickAdd.draft = nil }
    }

    /// Adds the draft as an item of its kind, with its properties and under its place, in one create. Then the
    /// panel clears for the next item with Create More, and otherwise closes and the window opens the item. Where
    /// the library cannot make it, everything stays as typed and the library tells the person why. Nothing empty
    /// is ever written.
    @discardableResult
    func saveQuickAdd(in library: any ItemLibrary, undoManager: UndoManager?) async -> ItemID? {
        guard let draft = quickAdd.draft, !quickAdd.isSaving, QuickAdd.canSave(draft, in: library.catalogue) else { return nil }
        let isFile = QuickAdd.isFile(draft.typeID, in: library.catalogue)
        let id: ItemID?
        if isFile, let file = draft.file {
            quickAdd.saving(true)
            let title = NoteName.trimmed(draft.title)
            id = await library.addFile(
                named: file.name, data: file.data, title: title.isEmpty ? nil : title, parentID: draft.parentID, in: item)
            quickAdd.saving(false)
        } else {
            let properties = draft.properties.filter { $0.value != .null }
            id = library.createItem(
                typeID: draft.typeID, title: draft.title, body: draft.body, properties: properties, parentID: draft.parentID,
                in: item, undoManager: undoManager)
        }
        guard let id else { return nil }
        // The person may have changed the draft while a file was sent; only the file sent is taken from it.
        guard quickAdd.draft == draft else {
            quickAdd.draft?.file = nil
            return id
        }
        if quickAdd.createsMore {
            quickAdd.draft?.clearForNext()
        } else {
            quickAdd.isPresented = false
            quickAdd.draft = nil
            let caret = QuickAdd.hasBody(draft.typeID, in: library.catalogue) ? draft.pageCaret : nil
            newItem = NewItem(id: id, typeID: draft.typeID, library: library, caret: caret, isFile: isFile)
            finishNewItem(in: library)
        }
        return id
    }
}
