import Foundation
import Observation

extension Browser {
    /// The one way files from outside become items: dropped from Finder on a list or on a collection's row or card, or
    /// taken from a nearby device. Each file is added as an item of its own, of the type its kind calls for (as quick
    /// add's file is), where `target` says, which is the place the window showed when they were dropped when none is
    /// given. Where that is a collection, the items join it. A folder, a file that cannot be read and one the library
    /// refuses are told, and the rest are still added; a file named twice is added once. The drop is one undo step
    /// and one toast, made once the library holds what was added. Where it does not within `waiting`, the toast has no
    /// Undo, the items it holds are still joined to the collection, and the person is told. The files are written to `library` whatever the window does meanwhile, since a write there is
    /// safe and a drop cut short would lose the rest; only the window's own steps (selecting what was added,
    /// revealing it) stop once the window has changed library, and once the person has moved to another place their
    /// selection is left alone. Before anything is added, the files already in Marfa are asked about once
    /// (`AlreadyInMarfa`): Add Anyway adds every file, Skip Duplicates adds only the files with no match, and Cancel
    /// adds nothing. The choice is final then. Where files were skipped, the toast says so and offers Show, which
    /// opens the matches and changes nothing that was added. The files, and any copy made of them, stay until the
    /// check has ended. Returns the items made.
    @discardableResult
    func importFiles(
        _ urls: [URL], unreadable: Int = 0, to target: FileDropTarget? = nil,
        in library: any ItemLibrary, order: ItemOrder, undoManager: UndoManager?, toasts: ToastPresenter? = nil,
        waiting: Duration = .seconds(10), releaseCopies: @escaping @MainActor () -> Void = {}
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
        let lifetime = AlreadyInMarfa.FileLifetime()
        defer { lifetime.afterLookup { [files] in withExtendedLifetime(files, releaseCopies) } }
        let plan = await AlreadyInMarfa.check(files.map(\.url), in: library, asking: alreadyInMarfa, lifetime: lifetime)
        guard !plan.isCancelled else { return [] }
        let skipped = files.count - plan.adding.count
        let show: (@MainActor () -> Void)?
        if plan.show.isEmpty {
            show = nil
        } else {
            show = { [weak self] in
                guard let self else { return }
                showMatches(plan.show, in: library, order: order)
            }
        }
        var added: [ItemID] = []
        for index in plan.adding {
            let file = files[index]
            if let id = await library.addFile(file.url, title: nil, parentID: nil, tier: QuickAdd.startingTier(in: target.place), tags: []) {
                added.append(id)
            }
        }
        guard !added.isEmpty else {
            if skipped > 0 {
                say(AlreadyInMarfa.skippedMessage(skipped), symbol: "arrow.down.doc", step: nil, showMatches: show, toasts: toasts)
            }
            return []
        }
        // A drop is told, joined and given its Undo only for what the library holds: a source that has not shown an
        // item cannot move it to Recently Deleted or give it an edge.
        let holdsAll = await library.waitUntilHolding(added, within: waiting)
        let held = added.filter { library.item($0) != nil }
        let undoManager = holdsAll ? undoManager : nil
        let run = DropStep(undoManager)
        // Registered first, so Undo takes the items out of the collection before it trashes them, and Redo restores
        // them before it joins them again: a source refuses an edge write on an item in the bin.
        if holdsAll { registerUndoOfAdding(added, in: library, undoManager: undoManager) }
        var joined = false
        if let collection = target.collection, !held.isEmpty {
            joined = library.addToCollection(Set(held), collection, undoManager: undoManager)
        }
        let step = run.finish(named: String(localized: "Add Files"))
        if !holdsAll {
            library.notices.tell(
                String(localized: "Drop Can’t Be Undone"),
                String(localized: "\(added.count - held.count) of the \(added.count) files added have not reached the library yet, so this drop has no Undo."))
        }
        let asked = files.count + notRead.count + unreadable
        let leftOut = target.collection == nil ? 0 : added.count - (joined ? held.count : 0)
        say(addedMessage(
            added.count, of: asked, to: target.isOnCollection ? target.name : nil, leftOut: leftOut, from: target.name,
            skipped: skipped), symbol: "arrow.down.doc", step: step, showMatches: skipped > 0 ? show : nil, toasts: toasts)
        guard isShowing(library), shown.isSame(target.shown), let first = held.first else { return added }
        let listed = Set(placeItems(in: library).map(\.id))
        if (joined && target.collection == shownCollection) || held.allSatisfy(listed.contains) {
            selection = Set(held)
        } else if !target.isOnCollection, let item = library.item(first) {
            reveal(item, in: library, order: order)
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
                undoManager: undoManager, toasts: toasts, releaseCopies: gathered.remove)
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
    /// collection they joined where the drop was on one. Where `leftOut` of them did not join the collection, it
    /// says so instead.
    private func addedMessage(_ count: Int, of asked: Int, to collection: String?, leftOut: Int, from place: String, skipped: Int = 0) -> String {
        let added = count == asked
            ? AttributedString(localized: "^[Added \(count) File](inflect: true)").text
            : String(localized: "Added \(count) of \(asked) Files")
        let placed = if leftOut > 0 {
            String(localized: "\(added), \(leftOut) not in \(place)")
        } else {
            collection.map { String(localized: "\(added) to \($0)") } ?? added
        }
        guard skipped > 0 else { return placed }
        return String(localized: "\(placed) \(AlreadyInMarfa.alreadyCounted(skipped))")
    }

    /// The collection the window shows.
    private var shownCollection: ItemID? {
        if shown.view == .own, case .collection(let id) = shown.place { id } else { nil }
    }
}

extension ItemLibrary {
    /// Returns once the library holds every item in `ids`, which a library fed by a server does only when its source
    /// says so, or when `limit` has passed. Says whether it holds them all.
    @discardableResult
    func waitUntilHolding(_ ids: [ItemID], within limit: Duration = .seconds(10)) async -> Bool {
        guard ids.contains(where: { item($0) == nil }) else { return true }
        let watcher = Task {
            for await isHeld in Observations({ ids.allSatisfy { self.item($0) != nil } }) where isHeld { return }
        }
        let timeout = Task {
            try? await Task.sleep(for: limit)
            watcher.cancel()
        }
        await watcher.value
        timeout.cancel()
        return ids.allSatisfy { item($0) != nil }
    }
}
