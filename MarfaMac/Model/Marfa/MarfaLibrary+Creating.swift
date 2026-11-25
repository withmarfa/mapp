import Foundation

extension MarfaLibrary {
    func createItem(
        typeID: String, title: String, body: String, properties: [String: PropertyValue], tags: [String], parentID: ItemID?,
        tier: Tier, undoManager: UndoManager?
    ) -> ItemID? {
        createItem(
            as: .mint(at: now()), typeID: typeID, title: title, body: body, properties: properties, tags: tags,
            parentID: parentID, tier: tier, undoManager: undoManager)
    }

    func createItem(
        as id: ItemID, typeID: String, title: String, body: String, properties: [String: PropertyValue], tags: [String],
        parentID: ItemID?, tier: Tier, undoManager: UndoManager?
    ) -> ItemID? {
        let type = TypeID(typeID)
        let title = NameText.trimmed(title)
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : body
        let cantCreate = String(localized: "Can’t Create Item")
        guard let info = catalogue.itemTypes[type] else {
            notices.tell(cantCreate, String(localized: "Choose a kind of item."))
            return nil
        }
        // Marfa lets a type leave its title out (a bookmark's), but an item with nothing in it is never written.
        let titleRequired = info.fields.contains { $0.key == info.titleKey && $0.required }
        let holdsMore = !text.isEmpty || properties.values.contains { $0 != .null }
        guard !title.isEmpty || (!titleRequired && holdsMore) else {
            notices.tell(cantCreate, String(localized: "Give the item a title."))
            return nil
        }
        let draft = ItemDraft(
            type: type, title: title, body: text, properties: properties, tags: Set(tags), tier: tier, parent: parentID)
        do {
            _ = try MarfaEngine.creationProperties(draft, catalogue: catalogue)
        } catch {
            notices.tell(cantCreate, error.problem.message ?? cantCreate)
            return nil
        }
        submitCreate(id, draft, failing: cantCreate)
        registerNewItemUndo(id, undoManager: undoManager)
        return id
    }

    func registerNewItemUndo(_ id: ItemID, undoManager: UndoManager?) {
        let name = String(localized: "New Item")
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.gatheringSkips(failing: name) {
                library.setStates([id: (from: .active, to: .trashed)], name: name, undoManager: undoManager)
            }
        }
    }

}
