import Foundation

extension NoteLibrary {
    // MARK: Typed items

    func item(_ id: UUID) -> AppItem? {
        if let note = note(id) { return AppItem(projection: NoteProjection(note: note)) }
        return files.first { $0.id == id }.map(AppItem.init(file:))
    }

    var items: [AppItem] { notes.filter { !$0.isDeleted }.map { AppItem(projection: NoteProjection(note: $0)) } + files.map(AppItem.init(file:)) }

    var connectionIndex: NoteConnectionIndex {
        NoteConnectionIndex(records: notes.filter { !$0.isDeleted }.map(NoteProjection.init) + files.map { AppItem(file: $0).projection }, rulesByType: WorkbenchSchema.rulesByType)
    }

    func relationships(for id: UUID) -> [ItemRelationship] {
        guard let item = item(id) else { return [] }
        let index = connectionIndex
        var results = item.relationshipFields.map { field in
            let targets = index.references.filter { reference in
                reference.sourceID == id && reference.origin == .header(field)
            }.map { reference in
                let targetID: UUID? = if case .resolved(let target) = reference.resolution { target } else { nil }
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

    func relationshipCandidates(for id: UUID, field: String) -> [AppItem] {
        let candidates = notes.filter { note in
            guard note.id != id, !note.isDeleted else { return false }
            if field.hasPrefix("inverse:") {
                let ownerField = field == "inverse:parent-of" ? "child-of" : String(field.dropFirst("inverse:".count))
                return item(note.id)?.relationshipFields.contains(ownerField) == true && (ownerField != "child-of" || validParent(id, forType: item(note.id)?.type?.id ?? "core.note"))
            }
            return field != "child-of" || validParent(note.id, forType: item(id)?.type?.id ?? "core.note")
        }.map { AppItem(projection: NoteProjection(note: $0)) } + ((field == "about" || field == "derived-from") ? files.map(AppItem.init(file:)) : [])
        return candidates.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func bodyMentions(for id: UUID) -> [ItemRelationshipTarget] {
        connectionIndex.references.filter { $0.sourceID == id && $0.origin == .body }.map { reference in
            let targetID: UUID? = if case .resolved(let target) = reference.resolution { target } else { nil }
            return .init(title: reference.targetTitle, itemID: targetID, resolution: reference.resolution)
        }
    }

    @discardableResult
    func setItemProperty(_ id: UUID, key: String, value: NoteFieldValue?, undoManager: UndoManager? = nil) -> Bool {
        if key == "title" {
            guard let title = value?.string, let item = item(id), item.isEditable, !title.isEmpty,
                  NoteText.fileSafe(title) == title, !isNoteNameTaken(title, for: id) else { return false }
            renameNote(id, to: title, undoManager: undoManager)
            return true
        }
        guard let index = notes.firstIndex(where: { $0.id == id && !$0.isDeleted }),
              let item = item(id), item.isEditable,
              let definition = item.properties.first(where: { $0.key == key }) else { return false }
        if let value, !Self.valid(value, for: definition.kind) {
            failure = (String(localized: "Invalid Property"), String(localized: "The value does not match this property's type."))
            return false
        }
        var file = notes[index].file
        file.setField(key, value)
        applyItemFieldFiles([id: file], key: key, undoManager: undoManager, name: String(localized: "Edit Property"))
        return self.note(id)?.file == file
    }

    private static func valid(_ value: NoteFieldValue, for kind: ItemPropertyDefinition.Kind) -> Bool {
        switch (kind, value) {
        case (.text, .string): true
        case (.choice(let choices), .string(let string)): choices.contains(string)
        case (.date, .string(let string)):
            string.isEmpty || ISO8601DateFormatter().date(from: string) != nil || DateFormatter.itemDay.date(from: string) != nil
        case (.boolean, .bool), (.number, .number): true
        default: false
        }
    }

    private func reference(to targetID: UUID) -> String? {
        guard let target = item(targetID) else { return nil }
        let candidates = [target.title, target.projection.filePath, target.fields["marfa_id"]?.string].compactMap { $0 }
        for candidate in candidates {
            let spelling = "[[\(candidate)]]"
            var file = NoteFile(text: "")
            file.setProperty("type", "aic.agent.log")
            file.setProperty("about", spelling)
            let probeID = UUID()
            let probe = NoteProjection(id: probeID, file: file, fallbackTitle: probeID.uuidString)
            let records = notes.filter { !$0.isDeleted }.map(NoteProjection.init) + files.map { AppItem(file: $0).projection } + [probe]
            let index = NoteConnectionIndex(records: records, rulesByType: WorkbenchSchema.rulesByType)
            if index.references.contains(where: { $0.sourceID == probeID && $0.resolution == .resolved(targetID) }) { return spelling }
        }
        failure = (String(localized: "Can’t Link This Item"), String(localized: "The item's title and path cannot be represented as an unambiguous file link."))
        return nil
    }

    @discardableResult
    func createItem(typeID: String, title: String, parentID: UUID? = nil, in place: SidebarItem = .allNotes, undoManager: UndoManager? = nil) -> Note? {
        let title = NoteName.trimmed(title)
        guard let type = WorkbenchSchema.definition(typeID), !title.isEmpty,
              NoteText.fileSafe(title) == title,
              !notes.contains(where: { !$0.isDeleted && $0.title.caseInsensitiveCompare(title) == .orderedSame }) else {
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
        file.body = "\n"
        var note = Note(text: file.text, created: now())
        var directory = type.folder
        if case .folder(let id) = place, let folder = folder(id) { directory = folder.name; note.folderID = id }
        else {
            let top = directory.components(separatedBy: "/").first!
            if let folder = folders.first(where: { $0.name == top }) { note.folderID = folder.id }
            else { let folder = Folder(name: top); folders.append(folder); note.folderID = folder.id; perform(.createFolder(path: directory)) }
        }
        perform(.createFolder(path: directory))
        note.path = uniquePath(title, in: directory, except: nil)
        notes.append(note)
        perform(.create(path: note.path!, text: note.file.text))
        let id = note.id
        registerUndo(undoManager, name: String(localized: "New Item")) { [weak undoManager] library in library.delete([id], undoManager: undoManager) }
        return note
    }

    private func validParent(_ parentID: UUID, forType type: String) -> Bool {
        guard let parent = note(parentID), !parent.isDeleted else { return false }
        let parentType = NoteProjection(note: parent).declaredType
        return parentType == "aic.project" || (parentType == "aic.epic" && type.hasPrefix("aic.ticket."))
    }

    @discardableResult
    func setItemRelationship(_ id: UUID, field: String, targetIDs: [UUID], undoManager: UndoManager? = nil) -> Bool {
        if field.hasPrefix("inverse:") {
            let name = String(field.dropFirst("inverse:".count))
            let ownerField = name == "parent-of" ? "child-of" : name
            guard name != "supersedes" || targetIDs.count <= 1 else { return false }
            if name == "supersedes", let owner = targetIDs.first {
                var seen: Set<UUID> = [owner]
                var cursor: UUID? = id
                while let next = cursor {
                    guard seen.insert(next).inserted else { return false }
                    cursor = connectionIndex.edges.first { $0.name == "supersedes" && $0.sourceID == next }?.targetID
                }
            }
            let existing = relationships(for: id).first { $0.field == field }?.targets.compactMap(\.itemID) ?? []
            var files: [UUID: NoteFile] = [:]
            for ownerID in Set(existing + targetIDs) {
                guard let owner = item(ownerID), owner.isEditable, owner.relationshipFields.contains(ownerField), let source = note(ownerID) else { return false }
                if ownerField == "child-of" && targetIDs.contains(ownerID) && !validParent(id, forType: owner.type?.id ?? "core.note") { return false }
                if ownerField == "child-of", targetIDs.contains(ownerID) {
                    var seen: Set<UUID> = [ownerID]
                    var cursor: UUID? = id
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
                let values = references.map(NoteFieldValue.string)
                file.setField(ownerField, values.isEmpty ? nil : ownerField == "about" ? .array(values) : values.first)
                files[ownerID] = file
            }
            applyItemFieldFiles(files, key: ownerField, undoManager: undoManager, name: String(localized: "Edit Relationship"))
            return files.allSatisfy { self.note($0.key)?.file == $0.value }
        }
        guard let item = item(id), item.isEditable, item.relationshipFields.contains(field),
              let note = note(id), !note.isDeleted,
              Set(targetIDs).count == targetIDs.count,
              field == "about" || targetIDs.count <= 1 else { return false }
        for targetID in targetIDs {
            guard targetID != id, self.item(targetID) != nil, self.note(targetID)?.isDeleted != true else { return false }
            if field == "child-of" && !validParent(targetID, forType: item.type?.id ?? "core.note") { return false }
        }
        if field == "child-of", let parent = targetIDs.first {
            var seen: Set<UUID> = [id]
            var cursor: UUID? = parent
            let edges = connectionIndex.edges
            while let next = cursor {
                guard seen.insert(next).inserted else { return false }
                cursor = edges.first(where: { $0.name == "parent-of" && $0.targetID == next })?.sourceID
            }
        }
        if field == "supersedes", let target = targetIDs.first {
            let edges = connectionIndex.edges.filter { $0.name == "supersedes" }
            guard !edges.contains(where: { $0.targetID == target && $0.sourceID != id }) else { return false }
            var seen: Set<UUID> = [id]
            var cursor: UUID? = target
            while let next = cursor {
                guard seen.insert(next).inserted else { return false }
                cursor = edges.first { $0.sourceID == next }?.targetID
            }
        }
        var file = note.file
        let unresolved = connectionIndex.references.filter {
            $0.sourceID == id && $0.origin == .header(field) && { if case .resolved = $0.resolution { false } else { true } }($0)
        }.map { NoteFieldValue.string("[[\($0.targetTitle)]]") }
        guard unresolved.isEmpty || field == "about" else {
            failure = (String(localized: "Unresolved Relationship"), String(localized: "Resolve the existing target before replacing this relationship."))
            return false
        }
        let references = targetIDs.compactMap { reference(to: $0) }
        guard references.count == targetIDs.count else { return false }
        let targets = references.map(NoteFieldValue.string) + unresolved
        file.setField(field, targets.isEmpty ? nil : field == "about" ? .array(targets) : targets.first)
        applyItemFieldFiles([id: file], key: field, undoManager: undoManager, name: String(localized: "Edit Relationship"))
        return self.note(id)?.file == file
    }

    private func applyItemFieldFiles(_ files: [UUID: NoteFile], key: String, undoManager: UndoManager?, name: String) {
        let previous = Dictionary(uniqueKeysWithValues: files.keys.compactMap { id in note(id).map { (id, $0.file) } })
        guard files.allSatisfy({ id, file in
            let old = note(id).map(NoteProjection.init)?.fields ?? [:]
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
            var restored: [UUID: NoteFile] = [:]
            for (id, original) in previous {
                guard var current = library.note(id)?.file else { continue }
                current.restoreField(key, from: original)
                restored[id] = current
            }
            library.applyItemFieldFiles(restored, key: key, undoManager: undoManager, name: name)
        }
    }

    func creationParentCandidates(typeID: String) -> [AppItem] {
        notes.filter { validParent($0.id, forType: typeID) }.map { AppItem(projection: NoteProjection(note: $0)) }
    }

    func applyItemFiles(_ files: [UUID: NoteFile], undoManager: UndoManager?, name: String) {
        var previous: [UUID: NoteFile] = [:]
        for index in notes.indices {
            guard let file = files[notes[index].id], !notes[index].isDeleted, file != notes[index].file else { continue }
            previous[notes[index].id] = notes[index].file
            notes[index].file = file
            notes[index].modified = now()
            if let path = notes[index].path { perform(.write(path: path, text: file.text)) }
        }
        guard !previous.isEmpty else { return }
        registerUndo(undoManager, name: name) { [weak undoManager] library in library.applyItemFiles(previous, undoManager: undoManager, name: name) }
    }

}

private extension DateFormatter {
    static var itemDay: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}
