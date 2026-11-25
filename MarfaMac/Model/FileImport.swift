import Foundation
import Observation

extension Browser {
    /// The one way files from outside become items: dropped from Finder on a list or on a collection's row or card, or
    /// taken from a nearby device. Each file is added as an item of its own, of the type its kind calls for (as quick
    /// add's file is), where `target` says, which is the place the window showed when they were dropped when none is
    /// given. Where that is a collection, the items join it. A folder, a file that cannot be read and one the library
    /// refuses are told, and the rest are still added; a file named twice is added once. The drop is one undo step
    /// and one toast. The files are written to `library` whatever the window does meanwhile, since a write there is
    /// safe and a drop cut short would lose the rest; only the window's own steps (selecting what was added,
    /// revealing it) stop once the window has changed library, and once the person has moved to another place their
    /// selection is left alone. Returns the items made.
    @discardableResult
    func importFiles(
        _ urls: [URL], unreadable: Int = 0, to target: FileDropTarget? = nil,
        in library: any ItemLibrary, order: ItemOrder, undoManager: UndoManager?, toasts: ToastPresenter? = nil
    ) async -> [ItemID] {
        let target = target ?? fileDropTarget(in: library)
        var files: [QuickAdd.File] = []
        var notRead: [String] = []
        for url in urls {
            if let file = QuickAdd.File(url) {
                if !files.contains(file) { files.append(file) }
            } else {
                notRead.append("“\(url.lastPathComponent)”")
            }
        }
        QuickAdd.File.tellUnreadable(notRead, unreadable: unreadable, to: library.notices)
        var added: [ItemID] = []
        for file in files {
            if let id = await library.addFile(file.url, title: nil, parentID: nil, tier: QuickAdd.startingTier(in: target.place), tags: []) { added.append(id) }
        }
        guard !added.isEmpty else { return [] }
        if target.collection != nil { await library.waitUntilHolding(added) }
        let run = DropStep(undoManager)
        var joined = false
        if let collection = target.collection {
            joined = library.addToCollection(Set(added.filter { library.item($0) != nil }), collection, undoManager: undoManager)
        }
        registerUndoOfAdding(added, in: library, undoManager: undoManager)
        let step = run.finish(named: String(localized: "Add Files"))
        let asked = files.count + notRead.count + unreadable
        say(addedMessage(added.count, of: asked, to: target.isOnCollection ? target.name : nil),
            symbol: "arrow.down.doc", step: step, toasts: toasts)
        guard isShowing(library), shown.isSame(target.shown) else { return added }
        let listed = Set(placeItems(in: library).map(\.id))
        if (joined && target.collection == shownCollection) || added.allSatisfy(listed.contains) {
            selection = Set(added)
        } else if !target.isOnCollection {
            await library.waitUntilHolding(added)
            if isShowing(library), shown.isSame(target.shown), let first = library.item(added[0]) {
                reveal(first, in: library, order: order)
            }
        }
        return added
    }

    /// Imports what a drop or a nearby device handed over, through `FileIntake`, then removes any copy made of it.
    /// Where the files go is fixed now, before the providers are read.
    func importProviders(
        _ providers: [NSItemProvider], to target: FileDropTarget? = nil, in library: any ItemLibrary, order: ItemOrder,
        undoManager: UndoManager?, toasts: ToastPresenter?
    ) {
        let target = target ?? fileDropTarget(in: library)
        Task {
            let gathered = await FileIntake.files(from: providers)
            await importFiles(
                gathered.urls, unreadable: gathered.unreadable, to: target, in: library, order: order,
                undoManager: undoManager, toasts: toasts)
            gathered.remove()
        }
    }

    /// Takes the added items back to Recently Deleted, as one step of the undo manager; its redo restores them.
    private func registerUndoOfAdding(_ ids: [ItemID], in library: any ItemLibrary, undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { [weak library, weak undoManager] _ in
            MainActor.assumeIsolated { library?.delete(Set(ids), undoManager: undoManager) }
        }
    }

    /// What the toast says of a drop: how many files were added, of how many asked for where some were not, and the
    /// collection they joined where the drop was on one.
    private func addedMessage(_ count: Int, of asked: Int, to collection: String?) -> String {
        let added = count == asked
            ? AttributedString(localized: "^[Added \(count) File](inflect: true)").text
            : String(localized: "Added \(count) of \(asked) Files")
        return collection.map { String(localized: "\(added) to \($0)") } ?? added
    }

    /// The collection the window shows.
    private var shownCollection: ItemID? {
        if shown.view == .own, case .collection(let id) = shown.place { id } else { nil }
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
