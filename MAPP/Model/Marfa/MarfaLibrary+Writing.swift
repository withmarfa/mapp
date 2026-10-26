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

    /// Each item moves in one edit, its title and text going to the new type's keys (`TypeChange`), and all of them
    /// in one undo step. An item that cannot become `type`, or cannot be changed, is left out and the person told
    /// how many and why. Nothing is sent while a required value is missing.
    @discardableResult
    func changeType(_ ids: Set<ItemID>, to type: TypeID, filling: [String: PropertyValue], undoManager: UndoManager?) -> Bool {
        guard let planned = plannedTypeChange(ids, to: type, filling: filling) else { return false }
        guard !planned.isEmpty else { return true }
        let undos = TypeUndos()
        undos.items = sendTypeChange(planned, to: type)
        registerTypeChangeUndo(undos, ids: Set(planned.map(\.item.id)), to: type, filling: filling, undoManager: undoManager)
        return true
    }

    private static var cantChangeType: String { String(localized: "Can’t Change Type") }

    /// Nil, and the person told why, where nothing can be sent: a required value is missing, or every item is left
    /// out. Otherwise the items to send, empty where each already has the type, and the person told of those left out.
    private func plannedTypeChange(
        _ ids: Set<ItemID>, to type: TypeID, filling: [String: PropertyValue]
    ) -> [TypeChangePlan.Entry]? {
        let plan = typeChangePlan(ids, to: type, filling: filling)
        guard plan.missing.isEmpty else {
            let fields = plan.missing.map(\.displayLabel).joined(separator: ", ")
            notices.tell(Self.cantChangeType, String(localized: "Enter a value for: \(fields)."))
            return nil
        }
        tellSkipped(plan.skips, didChange: !plan.items.isEmpty, failing: Self.cantChangeType)
        return plan.items.isEmpty && !plan.skips.isEmpty ? nil : plan.items
    }

    private func sendTypeChange(_ planned: [TypeChangePlan.Entry], to type: TypeID) -> [TypeUndo] {
        planned.map { entry in
            let item = entry.item, plan = entry.plan
            submit(.retype(item.id, type, plan.changes, base: item.version), failing: Self.cantChangeType)
            return TypeUndo(
                id: item.id, from: item.type, to: type,
                before: Dictionary(uniqueKeysWithValues: plan.changes.keys.map { ($0, entry.values[$0]) }), after: plan.changes)
        }
    }

    /// Undo and redo each register their opposite at once, while the undo manager is undoing or redoing, and make
    /// their writes only once the open pages have handed over their last edit, as the change itself does. So the
    /// redo's own undo is filled in when its writes are made.
    private func registerTypeChangeUndo(
        _ undos: TypeUndos, ids: Set<ItemID>, to type: TypeID, filling: [String: PropertyValue], undoManager: UndoManager?
    ) {
        registerUndo(undoManager, name: String(localized: "Change Type")) { [weak undoManager] library in
            library.registerUndo(undoManager, name: String(localized: "Change Type")) { [weak undoManager] library in
                let redone = TypeUndos()
                library.registerTypeChangeUndo(redone, ids: ids, to: type, filling: filling, undoManager: undoManager)
                library.afterHandingOverEdits {
                    guard let planned = library.plannedTypeChange(ids, to: type, filling: filling), !planned.isEmpty else { return }
                    redone.items = library.sendTypeChange(planned, to: type)
                }
            }
            library.afterHandingOverEdits { library.undoTypeChange(undos.items) }
        }
    }

    private func afterHandingOverEdits(failing title: String = MarfaLibrary.cantChangeType, _ action: @escaping () -> Void) {
        let run = undoRun
        handOverEdits { [weak self] kept in
            guard let self else { return }
            guard kept else {
                return notices.tell(title, String(localized: "Finish editing the current note, then try again."))
            }
            // The writes belong to the undo or redo that waited for the pages, so the copy may hold them too.
            within(run, action)
        }
    }

    /// An item untouched since the change gets back exactly the values it had. One changed since, as by typing in
    /// its text or changing its type again, is moved back from what it is now like any change of type, so what was
    /// typed is kept and no text is left under a key the old type does not read.
    private func undoTypeChange(_ undos: [TypeUndo]) {
        for undo in undos {
            guard let item = item(undo.id), item.type != undo.from, let values = typeChangeValues(of: undo.id) else { continue }
            let untouched = item.type == undo.to && undo.after.allSatisfy { key, value in
                values[key] == value || values[key] == undo.before[key] ?? nil
            }
            if untouched {
                submit(.retype(undo.id, undo.from, undo.before, base: item.version), failing: Self.cantChangeType)
            } else if let plan = typeChange(of: undo.id, to: undo.from), plan.missing.isEmpty {
                submit(.retype(undo.id, undo.from, plan.changes, base: item.version), failing: Self.cantChangeType)
            } else {
                notices.tell(Self.cantChangeType, String(localized: "“\(item.title)” has changed since, and can’t go back to its type."))
            }
        }
    }

    // MARK: Versions

    private static var cantRestore: String { String(localized: "Can’t Restore Version") }

    /// The text and title of an earlier version go on the item as new edits, the text through the same save as typing,
    /// so it is made on the version the library holds and a text another device has changed since is merged or kept
    /// apart, never overwritten. What it replaces stays in the item's history. Undo and Redo register their opposite
    /// at once and make their writes once the open pages have handed over their last edit, as a change of type does.
    @discardableResult
    func restoreVersion(_ snapshot: ItemSnapshot, of id: ItemID, undoManager: UndoManager?) -> Bool {
        switch restoreCheck(of: snapshot, for: id) {
        case .unchanged:
            return true
        case .unavailable(let reason):
            notices.tell(Self.cantRestore, reason)
            return false
        case .ready(let plan):
            guard let item = item(id) else { return false }
            let before = RestorePlan(text: plan.text == nil ? nil : body(of: id)?.text, title: plan.title == nil ? nil : item.title)
            let change = RestoreChange(from: before, to: plan)
            guard writeRestore(change, of: id) else { return false }
            registerRestoreUndo(change, of: id, undoManager: undoManager)
            return true
        }
    }

    /// A restore's two ends: what the item holds before it and what it holds after.
    private struct RestoreChange {
        var from: RestorePlan
        var to: RestorePlan
        var reversed: RestoreChange { RestoreChange(from: to, to: from) }
    }

    /// Writes `change.to` over an item that still holds `change.from`; a part the item no longer holds is left alone
    /// and told, since writing over it would replace what was typed after. False where nothing was written.
    private func writeRestore(_ change: RestoreChange, of id: ItemID) -> Bool {
        guard let item = item(id), item.isWritable else {
            notices.tell(Self.cantRestore, String(localized: "This item can’t be changed right now."))
            return false
        }
        var wrote = false
        var changedSince = false
        if let text = change.to.text {
            if let body = body(of: id), body.text == change.from.text {
                saveText(text, of: id, readAt: body.version, failing: Self.cantRestore)
                wrote = true
            } else {
                changedSince = true
            }
        }
        if let title = change.to.title, case .property(let key) = item.titleRule {
            if item.title == change.from.title {
                submit(.editProperties(id, [key: .string(title)], base: item.version, undoing: nil), failing: Self.cantRestore)
                wrote = true
            } else {
                changedSince = true
            }
        }
        if changedSince {
            notices.tell(
                Self.cantRestore,
                String(localized: "“\(item.title)” has changed since, so that can’t be put back here. Earlier versions are in Version History."))
        }
        return wrote
    }

    private func registerRestoreUndo(_ change: RestoreChange, of id: ItemID, undoManager: UndoManager?) {
        let name = String(localized: "Restore Version")
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.registerRestoreUndo(change.reversed, of: id, undoManager: undoManager)
            library.afterHandingOverEdits(failing: Self.cantRestore) {
                // The page has handed over what was typed, so the item is judged as it now is.
                _ = library.writeRestore(change.reversed, of: id)
            }
        }
    }

    // MARK: Favorites and the bin

    /// Items in the bin keep their tags, since Recently Deleted shows no favorites.
    func setFavorite(_ ids: Set<ItemID>, _ isFavorite: Bool, undoManager: UndoManager?) {
        let plan = favoritePlan(ids, isFavorite)
        tag(plan.changing, favorite: isFavorite, undoManager: undoManager)
        tellSkipped(
            plan.skips, didChange: !plan.changing.isEmpty,
            failing: isFavorite ? String(localized: "Can’t Add to Favorites") : String(localized: "Can’t Remove from Favorites"))
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

    // MARK: Tags

    @discardableResult
    func addTag(_ tag: String, to ids: Set<ItemID>, undoManager: UndoManager?) -> ItemTag.Refusal? {
        switch checkedTag(tag, adding: ids) {
        case .failure(let refusal): return refusal
        case .success(let (tag, changing, skips)):
            setTag(tag, on: true, changing, undoManager: undoManager)
            tellSkipped(skips, didChange: true, failing: String(localized: "Can’t Add Tag"))
            return nil
        }
    }

    func removeTag(_ tag: String, from ids: Set<ItemID>, undoManager: UndoManager?) {
        guard !reservedTags.contains(tag) else { return }
        setTag(tag, on: false, ids, undoManager: undoManager)
    }

    /// Each item that can take the change and does not already show it. An item that lost the tag on another device
    /// meanwhile is not sent a remove for it, which the server would answer as it answers any change that changes
    /// nothing. Undo and redo run this again, so they act on what the items hold then.
    private func setTag(_ tag: String, on: Bool, _ ids: Set<ItemID>, undoManager: UndoManager?) {
        let changing = Set(ids.filter { id in item(id).map { $0.canEditTags && $0.tags.contains(tag) != on } ?? false })
        guard !changing.isEmpty else { return }
        let name = on ? String(localized: "Add Tag") : String(localized: "Remove Tag")
        let title = on ? String(localized: "Can’t Add Tag") : String(localized: "Can’t Remove Tag")
        for id in changing { submit(.tag(id, tag, on: on), failing: title) }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.setTag(tag, on: !on, changing, undoManager: undoManager)
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

    func attach(file: URL, to id: ItemID) async throws -> Embed {
        guard let embed = try await source.embeds.attach([file], to: id).first else {
            throw SourceFailure(kind: .failed, message: String(localized: "The file couldn’t be attached."))
        }
        return embed
    }

    func addFile(_ file: URL, title: String?, parentID: ItemID?, in place: SidebarItem) async -> ItemID? {
        let cantAdd = String(localized: "Can’t Add File")
        do {
            // The Inbox is the feed tier, so a file added there stays where it was added.
            return try await source.embeds.addFile(file, title: title, tier: place == .inbox ? .feed : nil, parent: parentID)
        } catch let failure as SourceFailure {
            notices.tell(cantAdd, failure.message)
        } catch {
            notices.tell(cantAdd, error.localizedDescription)
        }
        return nil
    }

}

/// What a change of type wrote, filled in when its writes are made.
private final class TypeUndos {
    var items: [TypeUndo] = []
}

/// What a change of type wrote to one item, for its undo. A nil value is a key the item did not hold.
private struct TypeUndo {
    let id: ItemID
    let from: TypeID
    let to: TypeID
    let before: [String: PropertyValue?]
    let after: [String: PropertyValue?]
}
