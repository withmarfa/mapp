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
    /// Files to attach to the item once the library holds it.
    var attachments: [QuickAdd.File] = []
    /// Whether the item keeps text, so the page writes the attached files into it.
    var embedsInText = false
    /// The collection whose place the item was added in, which it joins once the library holds it.
    var collection: ItemID?
    /// The window's, so the item's joining the collection is undone there.
    weak var undoManager: UndoManager?
}

/// What the page writes at the end of a new item's text for the files quick add attached to it.
struct NewEmbeds: Equatable {
    let id: ItemID
    let embeds: [Embed]
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
            if isRefused(entry, in: library) { giveUpNewItem(because: .refused) }
            return
        }
        newItem = nil
        let joined = join(entry, in: library)
        if !entry.attachments.isEmpty {
            Task { await attachFiles(of: entry, in: library) }
        }
        leaveSettings()
        isCollectionItemPresented = usesCollection
        searchText = ""
        isSearchExpanded = false
        // The edge is queued, so the collection's list may not hold the item yet; it soon will.
        let joinedShown = joined && entry.collection.map { item == .collection($0) } == true
        if !joinedShown, !placeItems(in: library).contains(where: { $0.id == entry.id }) {
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

    /// Files the new item in the collection whose place it was added in, through the edge queue as any link is
    /// added, and says whether it did. An item whose type can't be in a collection, such as another collection, is
    /// left out of it; one the library refuses stays where it is, and the library tells the person why.
    private func join(_ entry: NewItem, in library: any ItemLibrary) -> Bool {
        guard let collection = entry.collection, let held = library.item(entry.id), library.canJoinCollection(held)
        else { return false }
        return library.addToCollection([entry.id], collection, undoManager: entry.undoManager)
    }

    /// Why the window stops waiting for the item quick add made.
    enum NewItemDeparture {
        /// The library refused the create.
        case refused
        /// The window closed, or went on to another library, before the library held the item.
        case windowLeft
    }

    /// Stops waiting for the item quick add made. Files that were to be attached to it are named, since nothing
    /// else keeps them.
    func giveUpNewItem(because departure: NewItemDeparture) {
        guard let entry = newItem else { return }
        newItem = nil
        guard !entry.attachments.isEmpty else { return }
        let reason = switch departure {
        case .refused: String(localized: "The item wasn’t added, so its files weren’t attached.")
        case .windowLeft: String(localized: "The window closed or changed library before the item’s files were attached.")
        }
        entry.library.notices.tell(String(localized: "Files Not Attached"), "\(reason) \(QuickAdd.File.notAdded(entry.attachments))")
    }

    /// Attaches the files quick add held to the item it made, one at a time, so one that fails leaves the others
    /// and the item as they are. The person is told which failed, once; what the page writes for the rest goes to
    /// the page for the end of the item's text.
    private func attachFiles(of entry: NewItem, in library: any ItemLibrary) async {
        var embeds: [Embed] = []
        var failed: [QuickAdd.File] = []
        var reasons: [String] = []
        for file in entry.attachments {
            guard file.isOnDisk else {
                failed.append(file)
                continue
            }
            do {
                embeds.append(try await library.attach(file: file.url, to: entry.id))
            } catch {
                failed.append(file)
                let reason = (error as? SourceFailure)?.message ?? error.localizedDescription
                if !reasons.contains(reason) { reasons.append(reason) }
            }
        }
        if !failed.isEmpty {
            let title = failed.count == 1 ? String(localized: "File Not Attached") : String(localized: "Files Not Attached")
            library.notices.tell(title, ([QuickAdd.File.notAdded(failed)] + reasons).joined(separator: " "))
        }
        if entry.embedsInText, !embeds.isEmpty { newEmbeds = NewEmbeds(id: entry.id, embeds: embeds) }
    }
}
