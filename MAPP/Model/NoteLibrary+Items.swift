import Foundation

extension NoteLibrary {
    // MARK: Typed items

    /// The fields the item's type names its relationships under, in the schema's order.
    func relationshipFields(of item: Item) -> [String] {
        WorkbenchSchema.definition(item.type.rawValue)?.relationshipFields ?? []
    }

    func relationships(for id: ItemID) -> [ItemRelationship] {
        guard let item = item(id) else { return [] }
        let index = connectionIndex
        var results = relationshipFields(of: item).map { field in
            let targets = (index.referencesBySource[id] ?? []).filter { $0.origin == .header(field) }.map { reference in
                let targetID: ItemID? = if case .resolved(let target) = reference.resolution { target } else { nil }
                return ItemRelationshipTarget(title: targetID.flatMap { self.item($0)?.title } ?? reference.targetTitle, itemID: targetID, resolution: reference.resolution)
            }
            return ItemRelationship(field: field, label: WorkbenchSchema.label(for: field), targets: targets, isEditable: item.isEditable, allowsMultiple: field == "about")
        }
        let inverse = index.edges.filter { ($0.name == "parent-of" && $0.sourceID == id) || ($0.name != "parent-of" && $0.targetID == id) }
        for name in Set(inverse.map(\.name)).sorted() {
            let targets = inverse.filter { $0.name == name }.compactMap { edge -> ItemRelationshipTarget? in
                let targetID = name == "parent-of" ? edge.targetID : edge.sourceID
                guard let target = self.item(targetID) else { return nil }
                return .init(title: target.title, itemID: targetID, resolution: .resolved(targetID))
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            results.append(.init(field: "inverse:" + name, label: name == "parent-of" ? "Children" : name == "about" ? "Items About This" : "Incoming " + WorkbenchSchema.label(for: name), targets: targets, isEditable: item.isEditable, allowsMultiple: name != "supersedes"))
        }
        return results
    }

    func relationshipCandidates(for id: ItemID, field: String) -> [Item] {
        let type = item(id)?.type.rawValue ?? "core.note"
        let candidates = allItems.filter { candidate in
            guard candidate.id != id, candidate.state == .active else { return false }
            if candidate.isFile { return field == "about" || field == "derived-from" }
            if field.hasPrefix("inverse:") {
                let ownerField = field == "inverse:parent-of" ? "child-of" : String(field.dropFirst("inverse:".count))
                return relationshipFields(of: candidate).contains(ownerField)
                    && (ownerField != "child-of" || validParent(id, forType: candidate.type.rawValue))
            }
            return field != "child-of" || validParent(candidate.id, forType: type)
        }
        return candidates.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func bodyMentions(for id: ItemID) -> [ItemRelationshipTarget] {
        (connectionIndex.referencesBySource[id] ?? []).filter { $0.origin == .body }.map { reference in
            let targetID: ItemID? = if case .resolved(let target) = reference.resolution { target } else { nil }
            return .init(title: reference.targetTitle, itemID: targetID, resolution: reference.resolution)
        }
    }

    @discardableResult
    func setItemProperty(_ id: ItemID, key: String, value: PropertyValue?, undoManager: UndoManager? = nil) -> Bool {
        if key == "title" {
            guard let title = value?.string, let item = item(id), item.isEditable, !title.isEmpty,
                  NoteText.fileSafe(title) == title, !isNoteNameTaken(title, for: id) else { return false }
            renameNote(id, to: title, undoManager: undoManager)
            return self.note(id)?.title == title
        }
        guard let index = notes.firstIndex(where: { $0.id == id && !$0.isDeleted }),
              let item = item(id), item.isEditable,
              let definition = catalogue.itemTypes[item.type]?.fields.first(where: { $0.key == key }) else { return false }
        if let value, !definition.kind.accepts(value) {
            failure = (String(localized: "Invalid Property"), String(localized: "The value does not match this property's type."))
            return false
        }
        var file = notes[index].file
        file.setField(key, value)
        applyItemFieldFiles([id: file], key: key, undoManager: undoManager, name: String(localized: "Edit Property"))
        return self.note(id)?.file == file
    }

    /// The link whose spelling the connection index resolves to this note alone: its title, else its path, else the
    /// identity its file declares. Nil when none does, as when another note goes by the same title and path form.
    func bodyLink(to id: ItemID, in source: ItemID?) -> String? {
        guard let target = item(id), !target.isFile else { return nil }
        let index = connectionIndex
        let candidates = [target.title, path(of: id), target.value(of: "marfa_id")?.string].compactMap { $0 }
        guard let spelling = candidates.first(where: { NoteLinks.canSpell($0) && index.resolution(of: $0) == .resolved(id) })
        else { return nil }
        // An identity shows the title, as a link by identity does everywhere.
        return NoteLinks.looksLikeIdentity(spelling)
            ? NoteLinks.identityLink(to: spelling, titled: target.title, readsBrackets: false) : NoteLinks.link(to: spelling)
    }

    /// A link reads as the connection index does: its title, else its path, else the identity its file declares.
    /// A name holding `|` or `#` is a link's alias or heading, never part of the name, so the index cannot read it.
    func resolveLink(_ name: String, in source: ItemID) -> NoteReferenceResolution {
        let name = NoteName.trimmed(name)
        guard !name.isEmpty, !name.contains(where: { $0 == "|" || $0 == "#" }) else { return .missing }
        return connectionIndex.resolution(of: name)
    }

    private func reference(to targetID: ItemID) -> String? {
        guard let target = item(targetID) else { return nil }
        let candidates = [target.title, path(of: targetID), target.value(of: "marfa_id")?.string].compactMap { $0 }
        for candidate in candidates {
            let spelling = "[[\(candidate)]]"
            var file = NoteFile(text: "")
            file.setProperty("type", "aic.agent.log")
            file.setProperty("about", spelling)
            let probeID = ItemID.mint()
            let probe = NoteProjection(id: probeID, file: file, fallbackTitle: probeID.rawValue)
            let records = connectionRecords() + [probe]
            let index = NoteConnectionIndex(records: records, rulesByType: WorkbenchSchema.rulesByType)
            if index.references.contains(where: { $0.sourceID == probeID && $0.resolution == .resolved(targetID) }) { return spelling }
        }
        failure = (String(localized: "Can’t Link This Item"), String(localized: "The item's title and path cannot be represented as an unambiguous file link."))
        return nil
    }

    /// Whether a note not deleted already goes by the title, ignoring case, which a new item may not take.
    func isItemTitleTaken(_ title: String) -> Bool {
        notes.contains { !$0.isDeleted && $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }

    @discardableResult
    func createItem(typeID: String, title: String, body: String = "\n", parentID: ItemID? = nil, in place: SidebarItem = .allNotes, undoManager: UndoManager? = nil) -> ItemID? {
        let title = NoteName.trimmed(title)
        guard let type = WorkbenchSchema.definition(typeID), !title.isEmpty,
              NoteText.fileSafe(title) == title,
              !isItemTitleTaken(title) else {
            failure = (String(localized: "Can’t Create Item"), String(localized: "Choose a unique title without characters that cannot be used in a file name."))
            return nil
        }
        if let parentID, !validParent(parentID, forType: typeID) { return nil }
        var file = NoteFile(text: "")
        file.setProperty("type", typeID)
        file.setProperty("title", title)
        if type.properties.contains(where: { $0.key == "status" }) {
            file.setProperty("description", "")
            file.setProperty("status", "pending")
            file.setProperty("priority", "medium")
        }
        if let parentID { guard let parentReference = reference(to: parentID) else { return nil }; file.setProperty("child-of", parentReference) }
        if typeID == "aic.decision" { file.setProperty("occurred_at", DateFormatter.itemDay.string(from: now())) }
        if typeID == "aic.agent.session" { file.setProperty("starts_at", ISO8601DateFormatter().string(from: now())); file.setProperty("ends_at", "") }
        file.body = body
        var directory = type.folder
        let folderID: ItemID
        if case .folder(let id) = place, let folder = folder(id) { directory = folder.name; folderID = id }
        else {
            let top = directory.components(separatedBy: "/").first!
            if let folder = folders.first(where: { $0.name == top }) { folderID = folder.id }
            else { let folder = Folder(name: top); folders.append(folder); folderID = folder.id; perform(.createFolder(path: top, id: folder.id)) }
        }
        let note = Note(path: uniquePath(title, in: directory, except: nil), text: file.text, created: now(), folderID: folderID)
        notes.append(note)
        perform(.create(path: note.path, text: note.file.text, id: note.id))
        let id = note.id
        registerUndo(undoManager, name: String(localized: "New Item")) { [weak undoManager] library in library.delete([id], undoManager: undoManager) }
        return id
    }

    private func validParent(_ parentID: ItemID, forType type: String) -> Bool {
        guard let parent = note(parentID), !parent.isDeleted else { return false }
        let parentType = itemProjection(parent).declaredType
        if parentType == "aic.project" { return true }
        if type == "aic.project" || type == "aic.epic" { return false }
        if parentType == "aic.epic" { return true }
        return !type.hasPrefix("aic.ticket.") && parentType?.hasPrefix("aic.ticket.") == true
    }

    @discardableResult
    func setItemRelationship(_ id: ItemID, field: String, targetIDs: [ItemID], undoManager: UndoManager? = nil) -> Bool {
        if field.hasPrefix("inverse:") {
            let name = String(field.dropFirst("inverse:".count))
            let ownerField = name == "parent-of" ? "child-of" : name
            guard name != "supersedes" || targetIDs.count <= 1 else { return false }
            if name == "supersedes", let owner = targetIDs.first {
                var seen: Set<ItemID> = [owner]
                var cursor: ItemID? = id
                while let next = cursor {
                    guard seen.insert(next).inserted else { return false }
                    cursor = connectionIndex.edges.first { $0.name == "supersedes" && $0.sourceID == next }?.targetID
                }
            }
            let existing = relationships(for: id).first { $0.field == field }?.targets.compactMap(\.itemID) ?? []
            var files: [ItemID: NoteFile] = [:]
            for ownerID in Set(existing + targetIDs) {
                guard let owner = item(ownerID), owner.isEditable, relationshipFields(of: owner).contains(ownerField), let source = note(ownerID) else { return false }
                if ownerField == "child-of" && targetIDs.contains(ownerID) && !validParent(id, forType: owner.type.rawValue) { return false }
                if ownerField == "child-of", targetIDs.contains(ownerID) {
                    var seen: Set<ItemID> = [ownerID]
                    var cursor: ItemID? = id
                    while let next = cursor {
                        guard seen.insert(next).inserted else { return false }
                        cursor = connectionIndex.edges.first { $0.name == "parent-of" && $0.targetID == next }?.sourceID
                    }
                }
                let current = relationships(for: ownerID).first { $0.field == ownerField }?.targets ?? []
                guard current.allSatisfy({ $0.itemID != nil }) else { return false }
                var targets = current.compactMap(\.itemID).filter { $0 != id }
                if targetIDs.contains(ownerID) {
                    if ownerField != "about" { targets = [] }
                    targets.append(id)
                }
                var file = source.file
                let references = targets.compactMap { reference(to: $0) }
                guard references.count == targets.count else { return false }
                let values = references.map(PropertyValue.string)
                file.setField(ownerField, values.isEmpty ? nil : ownerField == "about" ? .array(values) : values.first)
                files[ownerID] = file
            }
            applyItemFieldFiles(files, key: ownerField, undoManager: undoManager, name: String(localized: "Edit Relationship"))
            return files.allSatisfy { self.note($0.key)?.file == $0.value }
        }
        guard let item = item(id), item.isEditable, relationshipFields(of: item).contains(field),
              let note = note(id), !note.isDeleted,
              Set(targetIDs).count == targetIDs.count,
              field == "about" || targetIDs.count <= 1 else { return false }
        for targetID in targetIDs {
            guard targetID != id, self.item(targetID) != nil, self.note(targetID)?.isDeleted != true else { return false }
            if field == "child-of" && !validParent(targetID, forType: item.type.rawValue) { return false }
        }
        if field == "child-of", let parent = targetIDs.first {
            var seen: Set<ItemID> = [id]
            var cursor: ItemID? = parent
            let edges = connectionIndex.edges
            while let next = cursor {
                guard seen.insert(next).inserted else { return false }
                cursor = edges.first(where: { $0.name == "parent-of" && $0.targetID == next })?.sourceID
            }
        }
        if field == "supersedes", let target = targetIDs.first {
            let edges = connectionIndex.edges.filter { $0.name == "supersedes" }
            guard !edges.contains(where: { $0.targetID == target && $0.sourceID != id }) else { return false }
            var seen: Set<ItemID> = [id]
            var cursor: ItemID? = target
            while let next = cursor {
                guard seen.insert(next).inserted else { return false }
                cursor = edges.first { $0.sourceID == next }?.targetID
            }
        }
        var file = note.file
        let unresolved = connectionIndex.references.filter {
            $0.sourceID == id && $0.origin == .header(field) && { if case .resolved = $0.resolution { false } else { true } }($0)
        }.map { PropertyValue.string("[[\($0.targetTitle)]]") }
        guard unresolved.isEmpty || field == "about" else {
            failure = (String(localized: "Unresolved Relationship"), String(localized: "Resolve the existing target before replacing this relationship."))
            return false
        }
        let references = targetIDs.compactMap { reference(to: $0) }
        guard references.count == targetIDs.count else { return false }
        let targets = references.map(PropertyValue.string) + unresolved
        file.setField(field, targets.isEmpty ? nil : field == "about" ? .array(targets) : targets.first)
        applyItemFieldFiles([id: file], key: field, undoManager: undoManager, name: String(localized: "Edit Relationship"))
        return self.note(id)?.file == file
    }

    private func applyItemFieldFiles(_ files: [ItemID: NoteFile], key: String, undoManager: UndoManager?, name: String) {
        let previous = Dictionary(uniqueKeysWithValues: files.keys.compactMap { id in note(id).map { (id, $0.file) } })
        guard files.allSatisfy({ id, file in
            let old = note(id).map(itemProjection)?.fields ?? [:]
            let projection = NoteProjection(id: id, file: file, fallbackTitle: "")
            if case .invalid = projection.frontMatter { return false }
            let proposed = projection.fields ?? [:]
            return old.filter { $0.key != key } == proposed.filter { $0.key != key }
        }) else {
            failure = (String(localized: "Can’t Edit This Property"), String(localized: "This metadata uses a form that cannot be safely changed. Your file has been left unchanged."))
            return
        }
        applyItemFiles(files, undoManager: nil, name: name)
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            var restored: [ItemID: NoteFile] = [:]
            for (id, original) in previous {
                guard var current = library.note(id)?.file else { continue }
                current.restoreField(key, from: original)
                restored[id] = current
            }
            library.applyItemFieldFiles(restored, key: key, undoManager: undoManager, name: name)
        }
    }

    func creationParentCandidates(typeID: String) -> [Item] {
        notes.filter { validParent($0.id, forType: typeID) }.compactMap { item($0.id) }
    }

    func applyItemFiles(_ files: [ItemID: NoteFile], undoManager: UndoManager?, name: String) {
        var previous: [ItemID: NoteFile] = [:]
        for index in notes.indices {
            guard let file = files[notes[index].id], !notes[index].isDeleted, file != notes[index].file else { continue }
            previous[notes[index].id] = notes[index].file
            notes[index].file = file
            notes[index].modified = now()
            perform(.write(path: notes[index].path, text: file.text))
        }
        guard !previous.isEmpty else { return }
        registerUndo(undoManager, name: name) { [weak undoManager] library in library.applyItemFiles(previous, undoManager: undoManager, name: name) }
    }

}
