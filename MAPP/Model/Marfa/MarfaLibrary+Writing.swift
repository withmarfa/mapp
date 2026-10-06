import Foundation

/// Each write goes to the source, which applies it to its copy at once. An undo is the write that puts back what
/// was changed, registered with the pair it reverses, so it does the same however soon after the write it runs.
extension MarfaLibrary {
    // MARK: Creating

    func createItem(
        typeID: String, title: String, body: String, parentID: ItemID?, in place: SidebarItem, undoManager: UndoManager?
    ) -> ItemID? {
        let type = TypeID(typeID)
        let title = NoteName.trimmed(title)
        let cantCreate = String(localized: "Can’t Create Item")
        guard catalogue.itemTypes[type] != nil, !title.isEmpty else {
            failure = (cantCreate, String(localized: "Choose a kind of item and give it a title."))
            return nil
        }
        let id = ItemID.mint(at: now())
        if let parentID {
            let draft = EdgeDraft(type: MarfaMapping.parentEdge, source: parentID, target: id)
            if let problem = linkProblem(draft, sourceType: item(parentID)?.type, targetType: type) {
                failure = (cantCreate, problem)
                return nil
            }
        }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : body
        // The Inbox is the feed tier, so an item made there stays where it was made.
        let draft = ItemDraft(type: type, title: title, body: text, tier: place == .inbox ? .feed : nil, parent: parentID)
        submit(.create(id: id, draft), failing: cantCreate)
        let name = String(localized: "New Item")
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.setStates([id: (from: .active, to: .trashed)], name: name, undoManager: undoManager)
        }
        return id
    }

    // MARK: Text

    /// Edited from the version of the text the page was given; the source sends it as an update when the copy is
    /// still at that version, and otherwise asks the server to merge it against what was read.
    func updateBody(of id: ItemID, to body: String) {
        guard let item = item(id), item.isWritable else { return }
        let held = self.body(of: id)
        guard held?.text != body else { return }
        let base = held?.version ?? item.version
        let write = submit(
            .editBody(id, body, base: base, merge: .asRead), failing: String(localized: "Couldn’t Save “\(item.title)”"))
        holdText(body, of: id, base: base, write: write)
    }

    func leave(_ id: ItemID) {
        source.endEditing(id)
    }

    func finish() {
        Task { [source] in await source.flush() }
    }

    // MARK: Properties

    /// A title is the property the type keeps it in, which the views name `title` whatever it is.
    @discardableResult
    func setItemProperty(_ id: ItemID, key: String, value: PropertyValue?, undoManager: UndoManager?) -> Bool {
        guard let item = item(id), item.isEditable else { return false }
        let cantEdit = String(localized: "Can’t Edit This Property")
        var key = key
        if key == "title" || item.titleRule == .property(key) {
            guard case .property(let field) = item.titleRule else {
                failure = (cantEdit, String(localized: "This item’s title is the first line of its text."))
                return false
            }
            guard let title = value?.string.map(NoteName.trimmed), !title.isEmpty else { return false }
            key = field
            return editProperty(id, key: key, to: .string(title), undoManager: undoManager)
        }
        // The text is the page's to write, never a property's.
        guard let type = catalogue.itemTypes[item.type], key != MarfaMapping.bodyField(of: type),
            let field = type.fields.first(where: { $0.key == key })
        else { return false }
        if let value, !field.kind.accepts(value) {
            failure = (
                String(localized: "Invalid Property"), String(localized: "The value does not match this property's type.")
            )
            return false
        }
        return editProperty(id, key: key, to: value, undoManager: undoManager)
    }

    private func editProperty(_ id: ItemID, key: String, to value: PropertyValue?, undoManager: UndoManager?) -> Bool {
        guard let item = item(id) else { return false }
        let old = item.value(of: key)
        if old != value { editProperty(id, key: key, from: old, to: value, undoManager: undoManager) }
        return true
    }

    /// Made at the version held when it runs, so an undo goes on top of whatever came after the edit.
    private func editProperty(
        _ id: ItemID, key: String, from old: PropertyValue?, to value: PropertyValue?, undoManager: UndoManager?
    ) {
        guard let version = item(id)?.version else { return }
        submit(.editProperties(id, [key: value], base: version, undoing: nil), failing: String(localized: "Can’t Edit This Property"))
        let name = String(localized: "Edit Property")
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.editProperty(id, key: key, from: value, to: old, undoManager: undoManager)
        }
    }

    // MARK: Favorites and the bin

    /// Items in the bin keep their tags, since Recently Deleted shows no favorites.
    func setFavorite(_ ids: Set<ItemID>, _ isFavorite: Bool, undoManager: UndoManager?) {
        let changing = Set(ids.filter { id in item(id).map { $0.state == .active && $0.isFavorite != isFavorite } ?? false })
        tag(changing, favorite: isFavorite, undoManager: undoManager)
    }

    private func tag(_ ids: Set<ItemID>, favorite: Bool, undoManager: UndoManager?) {
        guard !ids.isEmpty else { return }
        let name = favorite ? String(localized: "Add to Favorites") : String(localized: "Remove from Favorites")
        let title = favorite ? String(localized: "Can’t Add to Favorites") : String(localized: "Can’t Remove from Favorites")
        for id in ids { submit(.tag(id, ItemTag.favorite, on: favorite), failing: title) }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.tag(ids, favorite: !favorite, undoManager: undoManager)
        }
    }

    func delete(_ ids: Set<ItemID>, undoManager: UndoManager?) {
        var changes: [ItemID: (from: ItemState, to: ItemState)] = [:]
        for id in ids { if let item = item(id), item.state != .trashed { changes[id] = (item.state, .trashed) } }
        let name = changes.count == 1 ? String(localized: "Delete Note") : String(localized: "Delete Notes")
        setStates(changes, name: name, undoManager: undoManager)
    }

    /// The copy restores only what it still holds: a delete the server has taken leaves the copy, and is back
    /// in Marfa's bin there.
    func recover(_ ids: Set<ItemID>, undoManager: UndoManager?) {
        var changes: [ItemID: (from: ItemState, to: ItemState)] = [:]
        for id in ids { if item(id)?.state == .trashed { changes[id] = (.trashed, .active) } }
        setStates(changes, name: String(localized: "Recover"), undoManager: undoManager)
    }

    /// A delete the server has taken leaves the copy, and the copy cannot bring an item back from the server's
    /// bin yet, so an undo that would is refused here, in the person's words.
    func setStates(_ changes: [ItemID: (from: ItemState, to: ItemState)], name: String, undoManager: UndoManager?) {
        var changes = changes
        let binned = changes.filter { $0.value.from == .trashed && item($0.key) == nil }.map(\.key)
        let cantRecover = String(localized: "Can’t Recover")
        let inTheBin = String(localized: "It’s in the Marfa server’s bin, which this Mac can’t bring items back from yet.")
        if !binned.isEmpty {
            for id in binned { changes[id] = nil }
            failure = (cantRecover, inTheBin)
        }
        guard !changes.isEmpty else { return }
        for (id, change) in changes {
            if change.from == .trashed {
                submit(.transition(id, change.to), failing: cantRecover, notHeld: inTheBin)
            } else {
                submit(.transition(id, change.to), failing: String(localized: "Couldn’t Make This Change"))
            }
        }
        let reversed = changes.mapValues { (from: $0.to, to: $0.from) }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.setStates(reversed, name: name, undoManager: undoManager)
        }
    }

    /// Only where `capabilities` has `purge`, which the source does not offer yet; the person is told rather than
    /// left to wonder.
    func deletePermanently(_ ids: Set<ItemID>) {
        notesToPurge.subtract(ids)
        let trashed = ids.filter { item($0)?.state == .trashed }
        guard capabilities.contains(.purge) else {
            failure = (String(localized: "Can’t Delete Immediately"), MarfaEngine.notYet)
            return
        }
        for id in trashed { submit(.purge(id), failing: String(localized: "Can’t Delete Immediately")) }
    }

    // MARK: What only files have

    func move(_ ids: Set<ItemID>, to folderID: ItemID?, undoManager: UndoManager?) { notYet() }
    func renameNote(_ id: ItemID, to name: String, undoManager: UndoManager?) { notYet() }
    func importFiles(_ sources: [URL], folderID: ItemID?, requestID: UUID) { notYet() }
    func consumeImportCompletion(_ requestID: UUID) {}

    /// The views offer folders only where `capabilities` has them, so this answers a folder the library never
    /// holds.
    @discardableResult
    func newFolder(undoManager: UndoManager?) -> Folder {
        notYet()
        return Folder(name: "")
    }

    func rename(_ id: ItemID, to name: String, undoManager: UndoManager?) { notYet() }
    func deleteFolder(_ id: ItemID, undoManager: UndoManager?) { notYet() }
    func moveFolders(_ ids: [ItemID], before target: ItemID?, undoManager: UndoManager?) { notYet() }

    private func notYet() {
        failure = (String(localized: "Couldn’t Make This Change"), MarfaEngine.notYet)
    }

    /// The files go to the source's embeds as files of their own, which it removes once they are taken.
    func attach(_ files: [(name: String, data: Data)], to id: ItemID) async throws -> [Embed] {
        let directory = URL.temporaryDirectory.appending(path: "MAPP-attach-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var urls: [URL] = []
        for file in files {
            let url = directory.appending(path: NoteLibrary.attachmentName(file.name))
            try file.data.write(to: url)
            urls.append(url)
        }
        return try await source.embeds.attach(urls, to: id)
    }

    // MARK: Undo

    func registerUndo(_ undoManager: UndoManager?, name: String, _ handler: @escaping (MarfaLibrary) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self, handler: handler)
        undoManager.setActionName(name)
    }
}
