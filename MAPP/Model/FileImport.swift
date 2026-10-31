import Foundation
import Observation

extension Browser {
    /// Where an import puts what it adds, fixed when the files are dropped, since the person may move on while they
    /// are read and sent.
    struct ImportDestination {
        /// The place the files were dropped in, which decides their tier (the Inbox is the feed tier).
        let place: SidebarItem
        /// The collection the items join: the one dropped on, else the one the window showed.
        let collection: ItemID?
        /// Whether the drop was on a collection, rather than on the window.
        let isOnCollection: Bool
    }

    /// The destination for files dropped now, on the collection `collection` when there is one.
    func importDestination(into collection: ItemID? = nil) -> ImportDestination {
        ImportDestination(place: item, collection: collection ?? shownCollection, isOnCollection: collection != nil)
    }

    /// The one way files from outside become items: dropped from Finder on the list, the sidebar or the window, dropped
    /// on a collection, or taken from a nearby device. Each file is added as an item of its own, of the type its kind
    /// calls for (as quick add's file is), in the place the window showed when they were dropped (`destination`,
    /// which is that place when none is given). Where that was a collection, or the drop was on one, the items join
    /// it. A file that cannot be read, and one the library refuses, are told, and the rest are still added. When the
    /// window changes library meanwhile nothing more is written, and when the person moves to another place their
    /// selection is left alone. Returns the items made.
    @discardableResult
    func importFiles(
        _ urls: [URL], unreadable: Int = 0, into collection: ItemID? = nil, destination: ImportDestination? = nil,
        in library: any ItemLibrary, order: NoteOrder, undoManager: UndoManager?
    ) async -> [ItemID] {
        let destination = destination ?? importDestination(into: collection)
        guard isShowing(library) else { return [] }
        var files: [QuickAdd.File] = []
        var notRead: [String] = []
        for url in urls {
            if let file = QuickAdd.File(url) { files.append(file) } else { notRead.append("“\(url.lastPathComponent)”") }
        }
        QuickAdd.File.tellUnreadable(notRead, unreadable: unreadable, to: library.notices)
        var added: [ItemID] = []
        for file in files {
            if let id = await library.addFile(file.url, title: nil, parentID: nil, in: destination.place) { added.append(id) }
            guard isShowing(library) else { return added }
        }
        guard !added.isEmpty else { return [] }
        var joined = false
        if let target = destination.collection {
            await library.waitUntilHolding(added)
            guard isShowing(library) else { return added }
            joined = library.addToCollection(Set(added.filter { library.item($0) != nil }), target, undoManager: undoManager)
        }
        guard item == destination.place else { return added }
        let shown = Set(placeItems(in: library).map(\.id))
        if (joined && destination.collection == shownCollection) || added.allSatisfy(shown.contains) {
            selection = Set(added)
        } else if !destination.isOnCollection {
            await library.waitUntilHolding(added)
            if isShowing(library), item == destination.place, let first = library.item(added[0]) {
                reveal(first, in: library, order: order)
            }
        }
        return added
    }

    /// Imports what a drop or a nearby device handed over, through `FileIntake`, then removes any copy made of it.
    /// Where the files go is fixed now, before the providers are read.
    func importProviders(
        _ providers: [NSItemProvider], into collection: ItemID? = nil, in library: any ItemLibrary, order: NoteOrder,
        undoManager: UndoManager?
    ) {
        let destination = importDestination(into: collection)
        Task {
            let gathered = await FileIntake.files(from: providers)
            await importFiles(
                gathered.urls, unreadable: gathered.unreadable, destination: destination, in: library, order: order,
                undoManager: undoManager)
            gathered.remove()
        }
    }

    /// The collection the window shows.
    private var shownCollection: ItemID? {
        if case .collection(let id) = item { id } else { nil }
    }
}

extension ItemLibrary {
    /// Returns once the library holds every item in `ids`, which a library fed by a server does only when its source
    /// says so, or when `limit` has passed.
    func waitUntilHolding(_ ids: [ItemID], within limit: Duration = .seconds(10)) async {
        guard ids.contains(where: { item($0) == nil }) else { return }
        let watcher = Task {
            for await isHeld in Observations({ ids.allSatisfy { self.item($0) != nil } }) where isHeld { return }
        }
        let timeout = Task {
            try? await Task.sleep(for: limit)
            watcher.cancel()
        }
        await watcher.value
        timeout.cancel()
    }
}
