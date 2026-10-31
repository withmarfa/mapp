import Foundation
import Observation
import UniformTypeIdentifiers

/// A window's quick-add panel: the kind of item being made, what the person typed, and where it goes. The draft
/// outlives the panel being put away, so nothing typed is lost until it is added or handed to the clipboard.
@Observable
final class QuickAdd {
    /// A file the person chose, dropped or pasted, read from where it is when the item is added rather than held
    /// in memory. The app may read it for as long as any draft or new item holds it.
    struct File: Equatable, Identifiable {
        let url: URL
        let byteCount: Int64?
        let contentType: UTType?
        private let access: FileAccess

        /// Nil for a folder, a package or anything else that is not one file that can be read.
        init?(_ url: URL) {
            access = FileAccess(url)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey]),
                  values.isRegularFile == true, FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false))
            else { return nil }
            self.url = url
            byteCount = values.fileSize.map(Int64.init)
            contentType = values.contentType
        }

        var id: URL { url }
        var name: String { url.lastPathComponent }
        /// Whether the file is still where it was taken from, since it is read only when the item is added.
        var isOnDisk: Bool { FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) }

        static func == (lhs: File, rhs: File) -> Bool { lhs.url == rhs.url }

        /// The files' names in a sentence: “a.pdf” and “b.png”.
        static func names(_ files: [File]) -> String {
            files.map { "“\($0.name)”" }.formatted(.list(type: .and))
        }

        /// The sentence that tells the person these files were not added.
        static func notAdded(_ files: [File]) -> String {
            files.count == 1
                ? String(localized: "\(names(files)) wasn’t added.")
                : String(localized: "\(names(files)) weren’t added.")
        }
    }

    /// Holds a sandbox extension to a file the person gave, so the file can be read later, and gives it up once
    /// nothing holds the file.
    nonisolated final class FileAccess: Sendable {
        private let url: URL
        private let scoped: Bool

        init(_ url: URL) {
            self.url = url
            scoped = url.startAccessingSecurityScopedResource()
        }

        deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
    }

    /// A detail of the item the panel shows as a chip under its text: its parent, or one of its kind's fields.
    enum Chip: Hashable {
        case parent
        case field(String)
    }

    struct Draft: Equatable {
        var typeID: String
        var title = ""
        var body = ""
        /// How many characters of the body come before the caret, so the page can put it back there.
        var caret: Int?
        var properties: [String: PropertyValue] = [:]
        var parentID: ItemID?
        /// The chips the person added, in the order they were added, whether or not they hold a value yet. A
        /// required field is always shown, so it is not listed here.
        var chips: [Chip] = []
        /// For a file, the file; for any other kind, the files attached to the item once it is made.
        var files: [File] = []

        /// Whether the person put anything in it worth keeping: text, a file, a parent, a value or a chip they added.
        var hasContent: Bool {
            !NoteName.trimmed(title).isEmpty || !isBlank(body) || !files.isEmpty || parentID != nil
                || properties.values.contains { $0 != .null } || !chips.isEmpty
        }

        /// What the clipboard is given when the draft cannot be added: the title, then the body, then the values and
        /// the parent, named. Without a library, the values go by their keys and the parent by its ID.
        func text(in library: (any ItemLibrary)?) -> String? {
            var details: [String] = []
            if let library {
                for field in QuickAdd.fields(of: typeID, in: library.catalogue) {
                    guard let value = properties[field.key], value != .null else { continue }
                    details.append("\(field.displayLabel): \(QuickAdd.valueText(value, in: field))")
                }
                if let parentID {
                    details.append("\(String(localized: "Parent")): \(library.item(parentID)?.title ?? String(localized: "Item not found"))")
                }
            } else {
                for (key, value) in properties.sorted(by: { $0.key < $1.key }) where value != .null {
                    details.append("\(key): \(ItemValueText.string(value))")
                }
                if let parentID { details.append("\(String(localized: "Parent")): \(parentID.rawValue)") }
            }
            let parts = [NoteName.trimmed(title), isBlank(body) ? "" : body, details.joined(separator: "\n")].filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }

        /// Where the page puts the caret, or nil where no body was typed.
        var pageCaret: PageCaret? {
            isBlank(body) ? nil : PageCaret(offset: caret, in: body)
        }

        private func isBlank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        /// Shows a chip, after the ones already shown.
        mutating func add(_ chip: Chip) {
            if !chips.contains(chip) { chips.append(chip) }
        }

        /// Puts the item under `parent` and shows the chip for it.
        mutating func setParent(_ parent: ItemID) {
            parentID = parent
            add(.parent)
        }

        /// Takes a chip away with the value it holds. A required field stays, since the item cannot be added
        /// without it.
        mutating func remove(_ chip: Chip, in catalogue: Catalogue) {
            guard QuickAdd.isRemovable(chip, typeID: typeID, in: catalogue) else { return }
            chips.removeAll { $0 == chip }
            switch chip {
            case .parent: parentID = nil
            case .field(let key): properties[key] = nil
            }
        }
    }

    var draft: Draft?
    var isPresented = false
    /// The work on each list field's entries, by key: an entry being added, or a member's text not yet in the draft.
    /// Kept here, not by the popover that edits it, so closing the popover keeps it. Observed, so the panel's word on
    /// an unfinished entry and its Add button follow it.
    var listDrafts: [String: ItemPropertyDraft] = [:]

    /// The work on the entries of list field `key`, made on first use. Make it before a view reads it, as the popover
    /// opens, since making it changes what the panel observes.
    func listDraft(for key: String) -> ItemPropertyDraft {
        if let draft = listDrafts[key] { return draft }
        let draft = ItemPropertyDraft()
        listDrafts[key] = draft
        return draft
    }

    /// The list fields holding text not yet in the draft, which holds the draft back until it is finished or removed.
    var unfinishedLists: [ItemTypeInfo.Field] {
        listDrafts.sorted { $0.key < $1.key }.compactMap { $0.value.holdsUnsavedList ? $0.value.field : nil }
    }

    /// The text of each list field not yet in the draft, named, for the clipboard.
    private var unfinishedListText: [String] {
        listDrafts.sorted { $0.key < $1.key }.compactMap { _, draft in
            guard let field = draft.field, case .list(let shape) = field.kind, let text = draft.list.unsavedText(in: shape) else { return nil }
            return "\(field.displayLabel): \(text)"
        }
    }

    /// Ends the draft once it is added or given up.
    func clearDraft() {
        draft = nil
        listDrafts = [:]
    }

    /// Whether the draft, or a list field's entries, hold anything worth keeping.
    var holdsContent: Bool { draft?.hasContent == true || !unfinishedLists.isEmpty }
    /// The draft as it was when its file was sent, while the file is being added, so the panel does not add it
    /// twice and a closing window does not hand off what is already on its way.
    private var sending: Draft?
    var isSaving: Bool { sending != nil }

    /// Why a draft leaves the window before it is added.
    enum Departure {
        /// The window closed, or the app quit.
        case closed
        /// The window went on to another library, whose items and fields the draft's place and properties do not name.
        case libraryChanged
    }

    init() { Self.open.add(self) }

    /// Every window's quick add, so a quit can hand each draft to the clipboard.
    private static let open = NSHashTable<QuickAdd>.weakObjects()

    /// Gives every window's draft to the clipboard through `notices`, as the app quits. `library` is the one the
    /// windows read, which names the values and the parent.
    static func handOffAll(to notices: Notices, in library: (any ItemLibrary)?) {
        for quickAdd in open.allObjects { quickAdd.handOff(to: notices, because: .closed, in: library) }
    }

    /// Gives a draft with anything in it to the clipboard through `notices`, which tells the person, as it leaves
    /// the window, since nothing else would keep it, and names the files it held, which the clipboard cannot. A
    /// file being added, and the title sent with it, are on their way already, so only what was typed or given
    /// besides them is handed off. `library` is the one the draft was made in, which names its values and parent.
    func handOff(to notices: Notices, because departure: Departure, in library: (any ItemLibrary)?) {
        let lists = unfinishedListText
        defer {
            clearDraft()
            isPresented = false
        }
        guard var draft else { return }
        if let sending {
            draft.files.removeAll { sending.files.contains($0) }
            if NoteName.trimmed(draft.title) == NoteName.trimmed(sending.title) { draft.title = "" }
            if draft.parentID == sending.parentID { draft.parentID = nil }
            draft.properties = draft.properties.filter { sending.properties[$0.key] != $0.value }
            draft.chips.removeAll { sending.chips.contains($0) }
        }
        guard draft.hasContent || !lists.isEmpty else { return }
        var reason = switch departure {
        case .closed: String(localized: "Quick add closed before the item was added.")
        case .libraryChanged: String(localized: "The window changed to another library before the item was added.")
        }
        if !draft.files.isEmpty { reason += " " + File.notAdded(draft.files) }
        let typed = [draft.text(in: library), lists.isEmpty ? nil : lists.joined(separator: "\n")].compactMap { $0 }
        let text = typed.isEmpty ? nil : typed.joined(separator: "\n\n")
        notices.notKept(
            String(localized: "Item Not Added"), text: text,
            reason: text == nil ? String(localized: "\(reason) Add it again.") : reason)
    }

    fileprivate func saving(_ draft: Draft?) { sending = draft }

    // MARK: What is remembered

    /// The defaults key for the kind last added, which a new draft starts with.
    static let lastTypeKey = "quickAddLastType"

    /// The sidebar's types in its order, groups opened.
    static func typeIDs(of nodes: [TypeNode]) -> [TypeID] {
        nodes.flatMap { node in (node.type.map { [$0] } ?? []) + typeIDs(of: node.children) }
    }

    // MARK: Kinds and fields

    /// Whether New Item can open the panel: the library is read and offers a kind to make.
    static func isAvailable(in library: any ItemLibrary) -> Bool {
        guard library.isLoaded else { return false }
        let catalogue = library.catalogue
        return catalogue.itemTypes[.file] != nil || catalogue.itemTypes.keys.contains(where: catalogue.isCreatable)
    }

    /// The kinds of item the panel offers, by label, with File after them where the catalogue has files.
    static func types(in library: any ItemLibrary) -> [ItemTypeOption] {
        let catalogue = library.catalogue
        var types = library.creatableTypes
        if catalogue.itemTypes[.file] != nil {
            types.append(ItemTypeOption(id: .file, label: catalogue.label(for: .file), icon: catalogue.icon(for: .file)))
        }
        return types
    }

    /// The kinds as the kind menu lists them: first the sidebar's own in its order, then File, which Tab and
    /// Shift-Tab move through; then, after a divider, the rest. The chosen kind is always among the first.
    static func kindMenu(_ types: [ItemTypeOption], shown: [TypeID], chosen: String?) -> (first: [ItemTypeOption], rest: [ItemTypeOption]) {
        var first = shown.compactMap { id in types.first { $0.id == id } }
        if first.isEmpty, let note = types.first(where: { $0.id == TypeID("core.note") }) { first.append(note) }
        if let file = types.first(where: { $0.id == .file }), !first.contains(file) { first.append(file) }
        if let chosen, let option = types.first(where: { $0.id.rawValue == chosen }), !first.contains(option) {
            first.append(option)
        }
        return (first, types.filter { !first.contains($0) })
    }

    /// The fields the panel offers for a kind: those the person can set, not its title or text. A file has none,
    /// since a file is added from its URL and the library takes no values with it.
    static func fields(of typeID: String, in catalogue: Catalogue) -> [ItemTypeInfo.Field] {
        guard !isFile(typeID, in: catalogue), let info = catalogue.itemTypes[TypeID(typeID)] else { return [] }
        return info.fields.filter { field in
            guard field.key != info.titleKey, field.key != info.bodyKey else { return false }
            if case .other = field.kind { return false }
            return true
        }
    }

    /// The chips the panel shows for a draft: the kind's required fields first, then what the person added in the
    /// order added, then any value or parent the draft holds that was not added by hand. A field the kind does
    /// not have is never shown.
    static func shownChips(_ draft: Draft, in catalogue: Catalogue) -> [Chip] {
        let fields = fields(of: draft.typeID, in: catalogue)
        let keys = Set(fields.map(\.key))
        var shown = fields.filter(\.required).map { Chip.field($0.key) }
        for chip in draft.chips where !shown.contains(chip) {
            switch chip {
            case .parent: if draft.parentID != nil { shown.append(chip) }
            case .field(let key): if keys.contains(key) { shown.append(chip) }
            }
        }
        if draft.parentID != nil, !shown.contains(.parent) { shown.append(.parent) }
        for field in fields where draft.properties[field.key].map({ $0 != .null }) == true && !shown.contains(.field(field.key)) {
            shown.append(.field(field.key))
        }
        return shown
    }

    /// What the add menu lists besides attaching a file: the parent, where the kind can have one and the draft
    /// has none, then the kind's fields that are not shown, in the catalogue's order.
    static func offeredChips(_ draft: Draft, in catalogue: Catalogue, canHaveParent: Bool) -> [Chip] {
        let shown = shownChips(draft, in: catalogue)
        var offered: [Chip] = []
        if canHaveParent, !shown.contains(.parent) { offered.append(.parent) }
        offered += fields(of: draft.typeID, in: catalogue).map { Chip.field($0.key) }.filter { !shown.contains($0) }
        return offered
    }

    /// Whether the person can take a chip away: all but a required field.
    static func isRemovable(_ chip: Chip, typeID: String, in catalogue: Catalogue) -> Bool {
        switch chip {
        case .parent: true
        case .field(let key): fields(of: typeID, in: catalogue).first { $0.key == key }?.required != true
        }
    }

    /// Whether the kind keeps text, so the panel offers a body.
    static func hasBody(_ typeID: String, in catalogue: Catalogue) -> Bool {
        catalogue.itemTypes[TypeID(typeID)]?.bodyKey != nil
    }

    static func isFile(_ typeID: String, in catalogue: Catalogue) -> Bool {
        catalogue.isFileType(TypeID(typeID))
    }

    /// Whether the draft holds text its kind does not keep, as when a note's text stays after the kind changes to
    /// a file. The text stays in sight and holds the draft back until it is removed or the kind changes back, so
    /// none is dropped.
    static func holdsTextItCannotKeep(_ draft: Draft, in catalogue: Catalogue) -> Bool {
        let keepsText = !isFile(draft.typeID, in: catalogue) && hasBody(draft.typeID, in: catalogue)
        return !keepsText && !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the panel shows the text: for a kind that keeps it, or while it holds text the kind cannot keep.
    static func showsBody(_ draft: Draft, in catalogue: Catalogue) -> Bool {
        (!isFile(draft.typeID, in: catalogue) && hasBody(draft.typeID, in: catalogue))
            || holdsTextItCannotKeep(draft, in: catalogue)
    }

    /// Whether a file draft holds more than the one file a file item keeps, as when a note's attachments stay
    /// after the kind changes to File. The files stay in sight and hold the draft back until all but one are
    /// removed or the kind changes back.
    static func holdsFilesItCannotKeep(_ draft: Draft, in catalogue: Catalogue) -> Bool {
        isFile(draft.typeID, in: catalogue) && draft.files.count > 1
    }

    /// A value as its chip shows it: a choice by its label, a Boolean as Yes or No, anything else as written.
    static func valueText(_ value: PropertyValue, in field: ItemTypeInfo.Field) -> String {
        if field.kind == .boolean, case .bool(let flag) = value { return flag ? String(localized: "Yes") : String(localized: "No") }
        if case .list(let shape) = field.kind { return shape.display(of: value) }
        if field.isPicked, let option = value.string { return ItemTypeInfo.Field.label(ofOption: option) }
        return ItemValueText.string(value)
    }

    /// Whether the draft names a parent the library no longer holds. The chip says so and can be removed, and the
    /// draft is not added while it stays, so a parent the library does not hold is never sent.
    static func holdsMissingParent(_ draft: Draft, in library: any ItemLibrary) -> Bool {
        draft.parentID.map { library.item($0) == nil } ?? false
    }

    /// Whether the draft can be added: a title, or one file for a file, a value for every required field, no text
    /// its kind cannot keep, and no parent the library lacks.
    static func canSave(_ draft: Draft, in library: any ItemLibrary) -> Bool {
        let catalogue = library.catalogue
        if holdsMissingParent(draft, in: library) || holdsTextItCannotKeep(draft, in: catalogue) { return false }
        if isFile(draft.typeID, in: catalogue) { return draft.files.count == 1 }
        guard !NoteName.trimmed(draft.title).isEmpty else { return false }
        return fields(of: draft.typeID, in: catalogue).allSatisfy { field in
            !field.required || draft.properties[field.key].map { $0 != .null } == true
        }
    }
}

extension Browser {
    /// Shows quick add, with `typeID` chosen where one is given. A draft put away comes back as it was left;
    /// otherwise the kind is `remembered`, the last one added, then the place's own type (a collection type in the
    /// Collections index), then a note.
    func openQuickAdd(typeID: String? = nil, remembered: String? = nil, in library: any ItemLibrary) {
        let interval = Telemetry.begin(.navigation, "quickAdd.open")
        defer { interval.end() }
        leaveSettings()
        palette = nil
        let types = QuickAdd.types(in: library).map(\.id.rawValue)
        func offered(_ id: String?) -> String? { id.flatMap { types.contains($0) ? $0 : nil } }
        if quickAdd.draft == nil {
            var placeType: String?
            if case .itemType(let id) = item { placeType = id }
            // The Collections index offers a new collection first.
            if item == .collections { placeType = types.first { library.catalogue.isCollection(TypeID($0)) } }
            guard let kind = offered(typeID) ?? offered(remembered) ?? offered(placeType) ?? offered("core.note") ?? types.first
            else { return }
            quickAdd.draft = QuickAdd.Draft(typeID: kind)
            chooseQuickAddType(kind, in: library)
        } else if let typeID = offered(typeID) {
            chooseQuickAddType(typeID, in: library)
        }
        quickAdd.isPresented = true
    }

    /// Changes the kind of item, keeping what was typed and the files given. A place, property or chip the new
    /// kind cannot take is dropped.
    func chooseQuickAddType(_ typeID: String, in library: any ItemLibrary) {
        guard var draft = quickAdd.draft else { return }
        draft.typeID = typeID
        let keys = Set(QuickAdd.fields(of: typeID, in: library.catalogue).map(\.key))
        draft.properties = draft.properties.filter { keys.contains($0.key) }
        if let parent = draft.parentID, !library.creationParentCandidates(typeID: typeID).contains(where: { $0.id == parent }) {
            draft.parentID = nil
        }
        draft.chips = draft.chips.filter { chip in
            switch chip {
            case .parent: draft.parentID != nil
            case .field(let key): keys.contains(key)
            }
        }
        // A list field the new kind lacks gives back any entry still being typed into it.
        for (key, list) in quickAdd.listDrafts where !keys.contains(key) {
            if let field = list.field, case .list(let shape) = field.kind, let text = list.list.unsavedText(in: shape) {
                library.notices.notKept(
                    String(localized: "Property Not Saved"), text: "\(field.displayLabel): \(text)",
                    reason: String(localized: "The new kind of item doesn’t have this property."))
            }
            quickAdd.listDrafts[key] = nil
        }
        quickAdd.draft = draft
    }

    /// Puts quick add away without adding anything; the draft waits for the panel to come back.
    func putAwayQuickAdd() {
        quickAdd.isPresented = false
        if quickAdd.draft != nil, !quickAdd.holdsContent { quickAdd.clearDraft() }
    }

    /// Puts an empty quick add away once its window has stopped being the one in front, as a menu closes when the
    /// person moves on. A draft with anything in it stays, since the person meant to come back to it. Nothing the
    /// panel opens itself counts as leaving: its file importer and popovers (`usesOwnSurface`), and any other
    /// window it opened, such as a sheet or a popover's window (`keyWindowIsOwn`), take the key for a moment.
    /// Returns whether it put the panel away.
    @discardableResult
    func putAwayQuickAddLeftEmpty(usesOwnSurface: Bool, keyWindowIsOwn: Bool) -> Bool {
        guard quickAdd.isPresented, quickAdd.draft != nil, !quickAdd.holdsContent, !usesOwnSurface, !keyWindowIsOwn else { return false }
        putAwayQuickAdd()
        return true
    }

    /// Adds the draft as an item of its kind, with its properties and under its place, in one create. Then the
    /// panel closes and the window opens the item, adds it to the collection being shown, and attaches the draft's
    /// files to it (`finishNewItem`). Where
    /// the library cannot make it, everything stays as typed and the library tells the person why. A file no
    /// longer where it was is taken out of the draft and named, and nothing is added until the person has seen
    /// that. Nothing empty is ever written.
    @discardableResult
    func saveQuickAdd(in library: any ItemLibrary, undoManager: UndoManager?) async -> ItemID? {
        guard let draft = quickAdd.draft, !quickAdd.isSaving, QuickAdd.canSave(draft, in: library), quickAdd.unfinishedLists.isEmpty
        else { return nil }
        let missing = draft.files.filter { !$0.isOnDisk }
        guard missing.isEmpty else {
            quickAdd.draft?.files.removeAll { missing.contains($0) }
            let names = QuickAdd.File.names(missing)
            if missing.count == 1 {
                library.notices.tell(
                    String(localized: "File Not Found"),
                    String(localized: "\(names) is no longer where it was, so it was taken out of the new item. Add it again, or add the item without it."))
            } else {
                library.notices.tell(
                    String(localized: "Files Not Found"),
                    String(localized: "\(names) are no longer where they were, so they were taken out of the new item. Add them again, or add the item without them."))
            }
            return nil
        }
        let interval = Telemetry.begin(.navigation, "quickAdd.save")
        defer { interval.end() }
        let catalogue = library.catalogue
        let isFile = QuickAdd.isFile(draft.typeID, in: catalogue)
        let id: ItemID?
        if isFile, let file = draft.files.first {
            quickAdd.saving(draft)
            let title = NoteName.trimmed(draft.title)
            id = await library.addFile(
                file.url, title: title.isEmpty ? nil : title, parentID: draft.parentID, in: item)
            quickAdd.saving(nil)
            guard let id else { return nil }
            // The person may have changed the draft while the file was sent; only the file sent is taken from it.
            guard quickAdd.draft == draft else {
                quickAdd.draft?.files.removeAll { $0 == file }
                return id
            }
        } else {
            let properties = draft.properties.filter { $0.value != .null }
            id = library.createItem(
                typeID: draft.typeID, title: draft.title, body: draft.body, properties: properties, parentID: draft.parentID,
                in: item, undoManager: undoManager)
        }
        guard let id else { return nil }
        quickAdd.isPresented = false
        quickAdd.clearDraft()
        let keepsText = !isFile && QuickAdd.hasBody(draft.typeID, in: catalogue)
        var collection: ItemID?
        if case .collection(let id) = item { collection = id }
        newItem = NewItem(
            id: id, typeID: draft.typeID, library: library, caret: keepsText ? draft.pageCaret : nil, isFile: isFile,
            attachments: isFile ? [] : draft.files, embedsInText: keepsText, collection: collection, undoManager: undoManager)
        finishNewItem(in: library)
        return id
    }
}
