import Foundation
import Observation

extension Browser {
    /// The one way files from outside become items: dropped from Finder on the list, the sidebar or the window, dropped
    /// on a collection, or taken from a nearby device. Each file is added as an item of its own, of the type its kind
    /// calls for (as quick add's file is), in the place the window shows. Where the window shows a collection, or the
    /// drop was on one (`collection`), the items join it. A file that cannot be read, and one the library refuses,
    /// are told, and the rest are still added. Returns the items made.
    @discardableResult
    func importFiles(
        _ urls: [URL], unreadable: Int = 0, into collection: ItemID? = nil, in library: any ItemLibrary, order: NoteOrder,
        undoManager: UndoManager?
    ) async -> [ItemID] {
        var files: [QuickAdd.File] = []
        var notRead: [String] = []
        for url in urls {
            if let file = QuickAdd.File(url) { files.append(file) } else { notRead.append("“\(url.lastPathComponent)”") }
        }
        QuickAdd.File.tellUnreadable(notRead, unreadable: unreadable, to: library.notices)
        var added: [ItemID] = []
        for file in files {
            if let id = await library.addFile(file.url, title: nil, parentID: nil, in: item) { added.append(id) }
        }
        guard !added.isEmpty else { return [] }
        let target = collection ?? shownCollection
        var joined = false
        if let target {
            await library.waitUntilHolding(added)
            joined = library.addToCollection(Set(added.filter { library.item($0) != nil }), target, undoManager: undoManager)
        }
        let shown = Set(placeItems(in: library).map(\.id))
        if (joined && target == shownCollection) || added.allSatisfy(shown.contains) {
            selection = Set(added)
        } else if collection == nil {
            await library.waitUntilHolding(added)
            if let first = library.item(added[0]) { reveal(first, in: library, order: order) }
        }
        return added
    }

    /// Imports what a drop or a nearby device handed over, through `FileIntake`, then removes any copy made of it.
    func importProviders(
        _ providers: [NSItemProvider], into collection: ItemID? = nil, in library: any ItemLibrary, order: NoteOrder,
        undoManager: UndoManager?
    ) {
        Task {
            let gathered = await FileIntake.files(from: providers)
            await importFiles(
                gathered.urls, unreadable: gathered.unreadable, into: collection, in: library, order: order, undoManager: undoManager)
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
