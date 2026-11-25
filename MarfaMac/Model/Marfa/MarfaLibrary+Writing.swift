import Foundation

/// Each write goes to the source, which applies it to its copy at once. An undo is the write that puts back what
/// was changed, registered with the pair it reverses, so it does the same however soon after the write it runs.
extension MarfaLibrary {
    // MARK: Text

    func updateBody(of id: ItemID, to body: String, readAt: ItemVersion) {
        // A page can hand over text for an item another device purged meanwhile, which no queue takes.
        guard let item = item(id) else { return notices.notKept(String(localized: "Couldn’t Save Item"), text: body, reason: Self.cantChange) }
        guard self.body(of: id)?.text != body else { return }
        let title = String(localized: "Couldn’t Save “\(item.displayTitle)”")
        // A save that arrives after the row stopped being writable, such as text typed as the copy found it could not
        // read the row, is kept nowhere, so the person gets the text back. Text that waits is checked again as it goes.
        guard item.allows(.text) else { return notices.notKept(title, text: body, reason: Self.cantChange) }
        takeTyped(body, of: id, readAt: readAt, failing: title)
    }

    /// Sends the text that waits (`TextPause`), then waits only until the source holds every write in its queue on
    /// this Mac, never for the server, so quitting or leaving the library offline keeps every write without waiting
    /// on the network.
    ///
    /// A relationship change whose check the core has not answered is waited for first, since the check is made on this
    /// Mac and answers at once; if it has not within `Self.relationshipWait`, the person is told it was not made. An
    /// archive still waiting for its restore's answer is dropped and told (`dropWaitingArchives`).
    func finish() async {
        let deadline = ContinuousClock.now + Self.relationshipWait
        while relationshipChangesInFlight > 0 {
            guard ContinuousClock.now < deadline else {
                notices.tell(
                    String(localized: "Can’t Change This Relationship"),
                    String(localized: "A change to a connection was still being checked, so it may not have been made. Check it and change it again."))
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        dropWaitingArchives()
        // A page can report again while the queue is waited on, so the wait ends only with nothing typed left waiting.
        repeat {
            sendWaitingText()
            await source.queueSubmitted()
        } while hasWaitingText
    }

    /// The longest `finish` waits for a relationship change to be checked.
    static let relationshipWait = Duration.seconds(2)

    var engineActivity: EngineActivity? { source.engineActivity }

    // MARK: Properties

    /// A title is the property the type keeps it in, which the views name `title` whatever it is.
    @discardableResult
    func setItemProperty(_ id: ItemID, key: String, value: PropertyValue?, undoManager: UndoManager?) -> Bool {
        guard let item = item(id) else { return false }
        let cantEdit = String(localized: "Can’t Edit This Property")
        var key = key
        if key == "title" || item.titleRule == .property(key) {
            guard item.allows(.title) else { return false }
            guard case .property(let field) = item.titleRule else {
                notices.tell(cantEdit, String(localized: "This item’s title is the first line of its text."))
                return false
            }
            guard let title = value?.string.map(NameText.trimmed), !title.isEmpty else { return false }
            key = field
            return editProperty(id, key: key, to: .string(title), undoManager: undoManager)
        }
        // The text is the page's to write, never a property's.
        guard item.obstacle(toField: key) == nil, let type = catalogue.itemTypes[item.type], key != MarfaMapping.bodyField(of: type),
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
        // A value equal to the stored one still goes while an edit of the item is on its way, since it reverses that
        // edit: skipping it would leave the edit in flight as the value stored.
        if item.value(of: key) != value || isWritingProperties(of: id) {
            editProperties(id, to: [key: value], actionName: String(localized: "Edit Property"), undoManager: undoManager)
        }
        return true
    }

    @discardableResult
    func setItemProperties(_ id: ItemID, changes: [String: PropertyValue?], actionName: String, undoManager: UndoManager?) -> Bool {
        guard let item = item(id), item.allows(.fields), let type = catalogue.itemTypes[item.type] else { return false }
        for (key, value) in changes {
            guard item.obstacle(toField: key) == nil, key != MarfaMapping.bodyField(of: type), let field = type.fields.first(where: { $0.key == key }) else { return false }
            if let value, !field.accepts(value) {
                notices.tell(String(localized: "Invalid Property"), String(localized: "The value does not match this property's type."))
                return false
            }
        }
        // A value equal to the stored one still goes while an edit of the item is on its way, since it may reverse that
        // edit: leaving it out would let the edit in flight land as the value kept.
        let sent = isWritingProperties(of: id) ? changes : changes.filter { item.value(of: $0.key) != $0.value }
        guard !sent.isEmpty else { return true }
        editProperties(id, to: sent, actionName: actionName, undoManager: undoManager)
        return true
    }

    /// Made at the version held when it runs, so an undo goes on top of whatever came after the edit.
    private func editProperties(_ id: ItemID, to changes: [String: PropertyValue?], actionName: String, undoManager: UndoManager?) {
        guard let version = item(id)?.version,
            let edit = submitPropertyEdit(id, changes, base: version, failing: String(localized: "Can’t Edit This Property"))
        else { return }
        registerUndo(of: edit, name: actionName, undoManager: undoManager)
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
            let fields = plan.missing.map(\.label).joined(separator: ", ")
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
            sendWaitingText()
            guard kept else {
                return notices.tell(title, String(localized: "Finish editing the current item, then try again."))
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
                notices.tell(Self.cantChangeType, String(localized: "“\(item.displayTitle)” has changed since, and can’t go back to its type."))
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
        guard let item = item(id), item.allows(.text) else {
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
                submit(.editProperties(id, [key: .string(title)], base: item.version), failing: Self.cantRestore)
                wrote = true
            } else {
                changedSince = true
            }
        }
        if changedSince {
            notices.tell(
                Self.cantRestore,
                String(localized: "“\(item.displayTitle)” has changed since, so that can’t be put back here. Earlier versions are in Version History."))
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

    // MARK: Favorites

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
        let changing = Set(ids.filter { id in item(id).map { $0.allows(.tags) && $0.tags.contains(tag) != on } ?? false })
        guard !changing.isEmpty else { return }
        let name = on ? String(localized: "Add Tag") : String(localized: "Remove Tag")
        let title = on ? String(localized: "Can’t Add Tag") : String(localized: "Can’t Remove Tag")
        for id in changing { submit(.tag(id, tag, on: on), failing: title) }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.setTag(tag, on: !on, changing, undoManager: undoManager)
        }
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
