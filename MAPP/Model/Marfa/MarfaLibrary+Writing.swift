import Foundation

/// Each write goes to the source, which applies it to its copy at once. An undo is the write that puts back what
/// was changed, registered with the pair it reverses, so it does the same however soon after the write it runs.
extension MarfaLibrary {
    // MARK: Creating

    func createItem(
        typeID: String, title: String, body: String, properties: [String: PropertyValue], parentID: ItemID?,
        in place: SidebarItem, undoManager: UndoManager?
    ) -> ItemID? {
        let type = TypeID(typeID)
        let title = NoteName.trimmed(title)
        let cantCreate = String(localized: "Can’t Create Item")
        guard catalogue.itemTypes[type] != nil, !title.isEmpty else {
            notices.tell(cantCreate, String(localized: "Choose a kind of item and give it a title."))
            return nil
        }
        let id = ItemID.mint(at: now())
        if let parentID {
            let draft = EdgeDraft(type: MarfaMapping.parentEdge, source: parentID, target: id)
            if let problem = linkProblem(draft, sourceType: item(parentID)?.type, targetType: type) {
                notices.tell(cantCreate, problem)
                return nil
            }
        }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : body
        // The Inbox is the feed tier, so an item made there stays where it was made.
        let draft = ItemDraft(
            type: type, title: title, body: text, properties: properties, tier: place == .inbox ? .feed : nil, parent: parentID)
        do {
            _ = try MarfaEngine.creationProperties(draft, catalogue: catalogue)
        } catch {
            notices.tell(cantCreate, error.problem.message ?? cantCreate)
            return nil
        }
        submitCreate(id, draft, failing: cantCreate)
        let name = String(localized: "New Item")
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.setStates([id: (from: .active, to: .trashed)], name: name, undoManager: undoManager)
        }
        return id
    }

    // MARK: Text

    func updateBody(of id: ItemID, to body: String, readAt: ItemVersion) {
        // A page can hand over text for an item another device purged meanwhile, which no queue takes.
        guard let item = item(id) else { return notices.notKept(String(localized: "Couldn’t Save Note"), text: body, reason: Self.cantChange) }
        guard self.body(of: id)?.text != body else { return }
        let title = String(localized: "Couldn’t Save “\(item.title)”")
        // A save that arrives after the row stopped being writable, such as a debounced edit over a row the copy
        // could not read, is kept nowhere, so the person gets the text back.
        guard item.isWritable else { return notices.notKept(title, text: body, reason: Self.cantChange) }
        saveText(body, of: id, readAt: readAt, failing: title)
    }

    /// Waits only until the source holds every write in its queue on this Mac, never for the server, so quitting
    /// or leaving the library offline keeps every write without waiting on the network.
    func finish() async {
        await source.queueSubmitted()
    }

    func wasRefused(creating id: ItemID) -> Bool {
        refusedCreations.contains(id)
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
                notices.tell(cantEdit, String(localized: "This item’s title is the first line of its text."))
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
            notices.tell(
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

    // MARK: Types

    /// Each item moves in one edit, its title and text going to the new type's keys (`TypeChange`). The views
    /// offer only the types every item can become, so a set that cannot is refused whole, before anything is sent.
    func changeType(_ ids: Set<ItemID>, to type: TypeID, filling: [String: PropertyValue], undoManager: UndoManager?) {
        let cantChange = String(localized: "Can’t Change Type")
        let changing = ids.filter { item($0).map { $0.type != type } ?? true }
        guard !changing.isEmpty else { return }
        var planned: [(item: Item, plan: TypeChange, values: [String: PropertyValue])] = []
        for id in changing.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let item = item(id), let values = typeChangeValues(of: id),
                  let plan = typeChange(of: id, to: type, filling: filling)
            else {
                return notices.tell(cantChange, String(localized: "One or more of these items can’t become this type."))
            }
            guard plan.missing.isEmpty else {
                let fields = plan.missing.map(\.displayLabel).joined(separator: ", ")
                return notices.tell(cantChange, String(localized: "Enter a value for: \(fields)."))
            }
            planned.append((item, plan, values))
        }
        var undos: [TypeUndo] = []
        for (item, plan, values) in planned {
            submit(.retype(item.id, type, plan.changes, base: item.version), failing: cantChange)
            undos.append(TypeUndo(
                id: item.id, from: item.type, to: type,
                before: Dictionary(uniqueKeysWithValues: plan.changes.keys.map { ($0, values[$0]) }), after: plan.changes))
        }
        let name = String(localized: "Change Type")
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.undoTypeChange(undos, filling: filling, undoManager: undoManager)
        }
    }

    /// An item untouched since the change gets back exactly the values it had. One changed since, as by typing in
    /// its text, is moved back like any change of type, so what was typed is kept.
    private func undoTypeChange(_ undos: [TypeUndo], filling: [String: PropertyValue], undoManager: UndoManager?) {
        let cantChange = String(localized: "Can’t Change Type")
        for undo in undos {
            guard let item = item(undo.id), let values = typeChangeValues(of: undo.id) else { continue }
            let untouched = undo.after.allSatisfy { key, value in
                values[key] == value || values[key] == undo.before[key] ?? nil
            }
            if untouched {
                submit(.retype(undo.id, undo.from, undo.before, base: item.version), failing: cantChange)
            } else if let plan = typeChange(of: undo.id, to: undo.from), plan.missing.isEmpty {
                submit(.retype(undo.id, undo.from, plan.changes, base: item.version), failing: cantChange)
            } else {
                notices.tell(cantChange, String(localized: "“\(item.title)” has changed since, and can’t go back to its type."))
            }
        }
        guard let type = undos.first?.to else { return }
        let ids = Set(undos.map(\.id))
        registerUndo(undoManager, name: String(localized: "Change Type")) { [weak undoManager] library in
            library.changeType(ids, to: type, filling: filling, undoManager: undoManager)
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

    /// An item whose delete the server has taken is in the server's bin, which the source lists with the items the
    /// copy still holds, so it is restored like any other.
    func recover(_ ids: Set<ItemID>, undoManager: UndoManager?) {
        var changes: [ItemID: (from: ItemState, to: ItemState)] = [:]
        for id in ids { if item(id)?.state == .trashed { changes[id] = (.trashed, .active) } }
        setStates(changes, name: String(localized: "Recover"), undoManager: undoManager)
    }

    func setStates(_ changes: [ItemID: (from: ItemState, to: ItemState)], name: String, undoManager: UndoManager?) {
        let changes = changes.filter { item($0.key) != nil }
        guard !changes.isEmpty else { return }
        for (id, change) in changes {
            if change.from == .trashed {
                submit(.transition(id, change.to), failing: String(localized: "Can’t Recover"))
            } else {
                submit(.transition(id, change.to), failing: String(localized: "Couldn’t Make This Change"))
            }
        }
        let reversed = changes.mapValues { (from: $0.to, to: $0.from) }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.setStates(reversed, name: name, undoManager: undoManager)
        }
    }

    /// Destroys items in the bin at the server, which only a server that can be reached does, so it is only where
    /// `canPurge`. It is sent at the version the person was shown.
    func deletePermanently(_ ids: Set<ItemID>) {
        notesToPurge.subtract(ids)
        guard canPurge else {
            notices.tell(
                String(localized: "Can’t Delete Immediately"),
                String(localized: "The Marfa server can’t be reached. The items are still in Recently Deleted."))
            return
        }
        for id in ids {
            guard let item = item(id), item.state == .trashed else { continue }
            submit(.purge(id, version: item.version), failing: String(localized: "Can’t Delete Immediately"))
        }
    }

    /// The files go to the source as files of their own, which this removes once it has taken them. Each is
    /// attached to the item by the package, which says what the page writes in the text to embed it.
    func attach(_ files: [(name: String, data: Data)], to id: ItemID) async throws -> [Embed] {
        let directory = URL.temporaryDirectory.appending(path: "MAPP-attach-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var urls: [URL] = []
        for file in files {
            let url = directory.appending(path: NoteText.attachmentName(file.name))
            try file.data.write(to: url)
            urls.append(url)
        }
        return try await source.embeds.attach(urls, to: id)
    }

    /// The file goes to the source from a file of its own, which this removes once the source has taken it.
    func addFile(named name: String, data: Data, title: String?, parentID: ItemID?, in place: SidebarItem) async -> ItemID? {
        let cantAdd = String(localized: "Can’t Add File")
        let directory = URL.temporaryDirectory.appending(path: "MAPP-add-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: NoteText.attachmentName(name))
            try data.write(to: url)
            // The Inbox is the feed tier, so a file added there stays where it was added.
            return try await source.embeds.addFile(url, title: title, tier: place == .inbox ? .feed : nil, parent: parentID)
        } catch let failure as SourceFailure {
            notices.tell(cantAdd, failure.message)
        } catch {
            notices.tell(cantAdd, error.localizedDescription)
        }
        return nil
    }

    // MARK: Undo

    func registerUndo(_ undoManager: UndoManager?, name: String, _ handler: @escaping (MarfaLibrary) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self, handler: handler)
        undoManager.setActionName(name)
    }
}

/// What a change of type wrote to one item, for its undo. A nil value is a key the item did not hold.
private struct TypeUndo {
    let id: ItemID
    let from: TypeID
    let to: TypeID
    let before: [String: PropertyValue?]
    let after: [String: PropertyValue?]
}
