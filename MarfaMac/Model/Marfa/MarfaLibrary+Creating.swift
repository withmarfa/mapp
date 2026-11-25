import Foundation

extension MarfaLibrary {
    func createItem(
        typeID: String, title: String, body: String, properties: [String: PropertyValue], parentID: ItemID?,
        in place: SidebarItem, undoManager: UndoManager?
    ) -> ItemID? {
        let type = TypeID(typeID)
        let title = NameText.trimmed(title)
        let cantCreate = String(localized: "Can’t Create Item")
        guard catalogue.itemTypes[type] != nil, !title.isEmpty else {
            notices.tell(cantCreate, String(localized: "Choose a kind of item and give it a title."))
            return nil
        }
        let id = ItemID.mint(at: now())
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
            library.gatheringSkips(failing: name) {
                library.setStates([id: (from: .active, to: .trashed)], name: name, undoManager: undoManager)
            }
        }
        return id
    }

    func wasRefused(creating id: ItemID) -> Bool {
        refusedCreations.contains(id)
    }
}
