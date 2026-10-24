import Foundation

/// An item New made, which the window opens in the page at once and takes out again if the person leaves it
/// completely empty. It is followed from the moment it is made until the person leaves it, and from then on it is
/// an item like any other.
struct NewItem {
    let id: ItemID
    let typeID: String
    /// The title it was made with, which is all it holds until something is typed.
    let title: String
    let parentID: ItemID?
    /// The library the create was sent to; another one that has loaded without the item never will hold it.
    let library: any ItemLibrary
    /// What the library held of the item when it first showed it, to tell later whether anything else changed it.
    /// Nil while the create is awaited: a Marfa library shows the item when its source says so.
    var baseline: Item?

    var isAwaited: Bool { baseline == nil }

    /// Whether the item still holds nothing the person put there. Nothing counts as put there only if the library
    /// has made no write to it since it was made and nothing is connected to it, and what the library shows is still
    /// the title it was made with, no text, no tags, no other property or connection than it began with, and the
    /// parent it was made under or none. The writes are asked first because a library may show a write only later;
    /// what it shows catches a change made by anything else. An item the library no longer shows, or shows as
    /// deleted, holds nothing to remove.
    func isUntouched(in library: any ItemLibrary) -> Bool {
        guard let baseline, !library.wasTouched(id), let item = library.item(id), item.state == .active else { return false }
        guard item.title == baseline.title, item.tags == baseline.tags, item.properties == baseline.properties,
              item.tier == baseline.tier, item.container == baseline.container,
              item.parentID == nil || item.parentID == parentID,
              Self.connections(of: item) == Self.connections(of: baseline)
        else { return false }
        // A body the library has not read is one the person has not seen, so nothing was typed in it.
        return library.body(of: id)?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    /// The connections other than the parent, which the library may place after it shows the item.
    private static func connections(of item: Item) -> Set<String> {
        Set(item.edgesOut.filter { $0.type != "child-of" }.map { "\($0.type)|\($0.target)" })
    }
}

extension Browser {
    /// Whether a New is waiting for the library to show its item.
    var isAwaitingNewItem: Bool { newItems.values.contains { $0.isAwaited } }

    /// Makes an item at once, in the place being shown, and opens it in the page with its title ready to type.
    /// `typeID` is the type chosen in the New menu; without one the item is of the place's type, or a note. The
    /// item is made as any other is, so it is queued, undoable and told of like the rest. Nil where nothing was
    /// made, for which the library's `failure` says why. A second New while the first is awaited makes nothing more.
    @discardableResult
    func startNewItem(typeID: String? = nil, in library: any ItemLibrary, undoManager: UndoManager?) -> ItemID? {
        leaveSettings()
        guard library.isLoaded else { return nil }
        if let awaited = newItems.values.first(where: \.isAwaited) { return awaited.id }
        guard let typeID = newItemType(typeID, in: library) else { return nil }
        var title = String(localized: "Untitled")
        let untitled = title
        var suffix = 2
        while library.isItemTitleTaken(title) {
            title = "\(untitled) \(suffix)"
            suffix += 1
        }
        var parentID: ItemID?
        if case .collection(let id) = item, library.creationParentCandidates(typeID: typeID).contains(where: { $0.id == id }) {
            parentID = id
        }
        // A note needs a body to be made, so it is sent empty rather than left out.
        guard let id = library.createItem(typeID: typeID, title: title, body: "", parentID: parentID, in: item, undoManager: undoManager)
        else { return nil }
        newItems[id] = NewItem(id: id, typeID: typeID, title: title, parentID: parentID, library: library)
        finishNewItem(in: library)
        return id
    }

    private func newItemType(_ chosen: String?, in library: any ItemLibrary) -> String? {
        let creatable = library.creatableTypes.map(\.id.rawValue)
        let wanted: String
        if let chosen { wanted = chosen } else if case .itemType(let id) = item { wanted = id } else { wanted = "core.note" }
        if creatable.contains(wanted) { return wanted }
        return creatable.contains("core.note") ? "core.note" : creatable.first
    }

    /// Whether the item New made is now held by the library, or was refused, and so is to be shown, or given up.
    func isNewItemSettled(in library: any ItemLibrary) -> Bool {
        guard let awaited = newItems.values.first(where: \.isAwaited) else { return false }
        return library.item(awaited.id) != nil || isRefused(awaited, in: library)
    }

    /// Refused once queued, so the refusal is in the problems the library shows, or refused before it was queued.
    /// A create sent to another library counts as refused once this one has loaded without it, since it will not
    /// come.
    private func isRefused(_ entry: NewItem, in library: any ItemLibrary) -> Bool {
        if entry.library !== library { return library.isLoaded }
        return library.wasRefused(creating: entry.id) || library.syncReport.problems.contains { $0.itemID == entry.id }
    }

    /// Opens the item New made once the library holds it, with its title ready to type. A create the library
    /// refused is given up; the library tells the person why.
    func finishNewItem(in library: any ItemLibrary) {
        guard var entry = newItems.values.first(where: \.isAwaited) else { return }
        guard let held = library.item(entry.id) else {
            if isRefused(entry, in: library) { newItems[entry.id] = nil }
            return
        }
        entry.baseline = held
        newItems[entry.id] = entry
        isCollectionItemPresented = usesCollection
        searchText = ""
        isSearchExpanded = false
        if !library.items(in: item).contains(where: { $0.id == entry.id }) {
            sidebarItem = .itemType(entry.typeID)
        }
        selection = [entry.id]
        focusRequest = .title
    }

    /// The page is shown the item, so it has not been left.
    private func isShowing(_ id: ItemID) -> Bool {
        selection == [id] && !showsCollection && !showsSidebarIndex
    }

    /// The page has let go of an item, once its last edit was handed over. An item New made that holds nothing is
    /// moved to Recently Deleted, never erased; one with anything in it, or a title typed and not yet saved, stays
    /// as any item does. Where the page still shows the item, as when Settings or the table covers it for a
    /// moment, nothing is decided, unless the window or the app is going. Answers whether the item was removed.
    @discardableResult
    func leaveNewItem(_ id: ItemID, closing: Bool, hasUnsavedTitle: Bool = false, undoManager: UndoManager?) -> Bool {
        guard let entry = newItems[id], !entry.isAwaited else { return false }
        if !closing && isShowing(id) { return false }
        newItems[id] = nil
        guard !hasUnsavedTitle, entry.isUntouched(in: entry.library) else { return false }
        entry.library.delete([id], undoManager: undoManager)
        return true
    }
}
