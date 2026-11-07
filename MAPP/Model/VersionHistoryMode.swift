import Foundation
import Observation

/// Version History open in a window: the item it shows, the versions read for it, and the restore under way. A window
/// holds at most one, in its `DetailsPresentation`, so the toolbar, the menu bar and the palette all reach the same one.
@Observable final class VersionHistoryMode {
    let item: ItemID
    let thread: ItemHistoryModel
    /// Whether a restore is waiting for the open pages to hand over their last edit, or for the library to take it.
    private(set) var isRestoring = false

    init(item: ItemID, source: (any ItemHistorySource)?) {
        self.item = item
        thread = ItemHistoryModel(id: item, source: source)
    }

    private struct ListKey: Hashable {
        let snapshots: Int
        let isComplete: Bool
        let revision: Int
    }

    @ObservationIgnored private var cached: (key: ListKey, list: VersionList)?

    /// The thread as it stands: the versions read so far and the item now. Nil while the library no longer holds the
    /// item. Made again only when a version arrives or the library's items change, not for each change of selection.
    func list(in library: any ItemLibrary) -> VersionList? {
        guard let current = library.item(item) else { return nil }
        let key = ListKey(snapshots: thread.snapshots.count, isComplete: thread.isComplete, revision: library.contentRevision)
        if let cached, cached.key == key { return cached.list }
        let list = VersionList(
            snapshots: thread.snapshots, current: current, currentText: library.body(of: item)?.text,
            isComplete: thread.isComplete, in: library.catalogue)
        cached = (key, list)
        return list
    }

    /// The version to show when the person has chosen none: the newest one before the item as it is now, which is the
    /// one most often wanted back, else the item as it is.
    func defaultSelection(in list: VersionList) -> String? {
        list.entries.dropFirst().first?.id ?? list.current?.id
    }

    func start() {
        guard thread.phase == .idle else { return }
        thread.load()
    }

    func stop() { thread.cancel() }

    /// What restoring a version would do now, judged on the item as the library holds it. The version the item holds
    /// now is the same as itself, so it can't be restored. Nil until the version is one of those read.
    func restoreCheck(of id: String?, in library: any ItemLibrary) -> RestoreCheck? {
        guard thread.phase == .loaded, let id else { return nil }
        if id == VersionEntry.currentID { return .unchanged }
        guard let snapshot = thread.snapshots.first(where: { $0.id == id }) else { return nil }
        return library.restoreCheck(of: snapshot, for: item)
    }

    /// The same for the version chosen.
    func restoreCheck(in library: any ItemLibrary) -> RestoreCheck? {
        restoreCheck(of: thread.selection, in: library)
    }

    func canRestore(in library: any ItemLibrary) -> Bool {
        !isRestoring && restoreCheck(in: library)?.isReady == true
    }

    /// Chooses the version to show when none is chosen yet.
    func chooseDefault(in list: VersionList) {
        guard thread.selection == nil || list.entry(thread.selection) == nil else { return }
        thread.selection = defaultSelection(in: list)
    }

    /// Why Restore Version is dimmed, in words.
    static func reason(for check: RestoreCheck?) -> String? {
        switch check {
        case nil, .ready?: nil
        case .unchanged?: String(localized: "The item already has this version’s text and title.")
        case .unavailable(let reason)?: reason
        }
    }

    /// Restores the chosen version once every open page has handed over what was just typed. `done` says whether it
    /// was sent; a refusal is told by the library and leaves the history open.
    func restore(in library: any ItemLibrary, undoManager: UndoManager?, then done: @escaping (Bool) -> Void) {
        guard canRestore(in: library), let snapshot = thread.selected else { return done(false) }
        isRestoring = true
        library.restoreVersionAfterSaving(snapshot, of: item, undoManager: undoManager) { [self] restored in
            isRestoring = false
            done(restored)
        }
    }
}

extension ItemLibrary {
    /// Restores the version once every open page has handed over what was just typed, so the restore is based on the
    /// text the person sees. `done` says whether it was sent.
    func restoreVersionAfterSaving(
        _ snapshot: ItemSnapshot, of id: ItemID, undoManager: UndoManager?, then done: @escaping (Bool) -> Void
    ) {
        EditorController.flushAll(leaving: false) { [self] kept in
            guard kept else {
                notices.tell(String(localized: "Can’t Restore Version"), String(localized: "Finish editing the current note, then try again."))
                return done(false)
            }
            done(restoreVersion(snapshot, of: id, undoManager: undoManager))
        }
    }
}
