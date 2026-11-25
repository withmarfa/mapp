import Foundation

extension Browser {
    /// Moves the live items among `ids` to Recently Deleted, which undoes; more than one is handed to `confirm`
    /// where there is one, which asks the person first and then moves them. A selection with a live item in it never
    /// erases anything: the items already in Recently Deleted stay there and are counted as skipped, since erasing
    /// cannot be undone and a command that also moves other items must not do it. Only a selection made entirely of
    /// items already there asks to erase them for good, and only where the library can; otherwise the person is told
    /// why not.
    static func delete(
        _ ids: Set<ItemID>, in library: any ItemLibrary, undoManager: UndoManager?, toasts: ToastPresenter? = nil,
        naming title: String? = nil, asking confirm: ((Set<ItemID>) -> Void)? = nil
    ) {
        let binned = Set(ids.filter { library.item($0)?.state == .trashed })
        if !binned.isEmpty, binned.count == ids.count {
            if library.reachesServer { library.itemsToPurge = binned } else { library.tellCannotPurge() }
            return
        }
        // Told here, before anything asks the person to confirm items that would be left alone.
        let plan = library.deletePlan(ids)
        let moving = plan.moving
        library.tellSkipped(plan.skips, didChange: !moving.isEmpty, failing: String(localized: "Can’t Delete"))
        if moving.count > 1, let confirm {
            confirm(moving)
        } else if !moving.isEmpty {
            moveToRecentlyDeleted(moving, in: library, undoManager: undoManager, toasts: toasts, naming: title)
        }
    }

    /// Moves `ids` to Recently Deleted, then says so in the window's toast with an Undo that takes back that move.
    /// The toast's Undo is bound to the step (`StepUndo`), not to its name: any step registered, undone or redone
    /// after it takes the toast away. It is offered only where no undo group was open before the move, since the move
    /// would then share that group and `undo()` would take back the other steps in it too. A manager that does not
    /// group by event has none open, so the move gets a group of its own, closed at once. A `title` names the one item
    /// moved, for an item the library may no longer return once moved.
    static func moveToRecentlyDeleted(
        _ ids: Set<ItemID>, in library: any ItemLibrary, undoManager: UndoManager?, toasts: ToastPresenter?, naming title: String? = nil
    ) {
        let moving = library.deletePlan(ids).moving
        let name = moving.count == 1 ? title ?? moving.first.flatMap { library.item($0)?.name } : nil
        let startsGroup = undoManager?.groupingLevel == 0
        let opensGroup = startsGroup && undoManager?.groupsByEvent == false
        if opensGroup { undoManager?.beginUndoGrouping() }
        library.delete(ids, undoManager: undoManager)
        if opensGroup { undoManager?.endUndoGrouping() }
        guard !moving.isEmpty, let toasts else { return }
        let message = DeletionWords.movedMessage(count: moving.count, title: name)
        guard startsGroup, let undoManager, undoManager.canUndo else {
            toasts.show(message, symbol: "trash")
            return
        }
        let step = StepUndo(undoManager: undoManager)
        let id = toasts.show(message, symbol: "trash", undo: { step.perform() })
        step.onLapse = { [weak toasts] in toasts?.dismiss(ifShowing: id) }
    }
}
