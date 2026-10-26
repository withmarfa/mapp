import Foundation

/// Where the page puts the caret in a new item's text: after the source the person typed before it in quick add, or
/// at the end, where that text is too long to send the page.
enum PageCaret: Equatable {
    case after(String)
    case end

    /// The most source sent to the page to place the caret; past it, the caret goes to the end.
    static let limit = 2_000

    /// The caret `offset` characters into `body`.
    init(offset: Int?, in body: String) {
        let offset = min(offset ?? body.count, body.count)
        self = offset == body.count || offset > Self.limit ? .end : .after(String(body.prefix(offset)))
    }
}

/// An item quick add made, which the window opens once its library holds it. A Marfa library holds an item only
/// when its source says so, which may take a moment, so the window waits for it.
struct NewItem {
    let id: ItemID
    let typeID: String
    /// The library the create was sent to; another one that has loaded without the item never will hold it.
    let library: any ItemLibrary
    /// Where the page puts the caret in the text the person typed. Nil gives the title the keyboard, or nothing for
    /// a file.
    let caret: PageCaret?
    let isFile: Bool
}

extension Browser {
    /// Whether an item quick add made is now held by the library, or was refused, and so is to be shown, or given
    /// up.
    func isNewItemSettled(in library: any ItemLibrary) -> Bool {
        guard let newItem else { return false }
        return library.item(newItem.id) != nil || isRefused(newItem, in: library)
    }

    /// Refused once queued, so the refusal is in the problems the library shows, or refused before it was queued.
    /// A create sent to another library counts as refused once this one has loaded without it, since it will not
    /// come.
    private func isRefused(_ entry: NewItem, in library: any ItemLibrary) -> Bool {
        if entry.library !== library { return library.isLoaded }
        return library.wasRefused(creating: entry.id) || library.syncReport.problems.contains { $0.itemID == entry.id }
    }

    /// Opens the item quick add made once the library holds it. A create the library refused is given up; the
    /// library tells the person why, with the text they typed.
    func finishNewItem(in library: any ItemLibrary) {
        guard let entry = newItem else { return }
        guard library.item(entry.id) != nil else {
            if isRefused(entry, in: library) { newItem = nil }
            return
        }
        newItem = nil
        leaveSettings()
        isCollectionItemPresented = usesCollection
        searchText = ""
        isSearchExpanded = false
        if !library.items(in: item).contains(where: { $0.id == entry.id }) {
            sidebarItem = entry.isFile ? .files : .itemType(entry.typeID)
        }
        selection = [entry.id]
        if entry.isFile {
            focusRequest = .list
        } else if let caret = entry.caret {
            focusCaret = caret
            focusRequest = .page
        } else {
            focusRequest = .title
        }
    }
}
