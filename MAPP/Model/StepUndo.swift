import Foundation

/// The Undo a toast offers for one change, good only while that change is still the undo manager's latest step.
///
/// The change must be the first step of the undo manager's open group (`Browser.moveToRecentlyDeleted` checks that no
/// group was open before it), so `undo()` takes back that change and nothing else. From then on this watches the
/// manager: a step registered after it in a later group or a nested one opens a group, and an Undo or Redo changes the
/// stack, so any of them ends the claim at once and `onLapse` runs, which takes the toast away. A step is never found
/// by its name, since every delete is named the same.
///
/// A step registered in the same group before it closes, with no group opened, cannot be seen. No route that moves
/// items registers a second step in the same pass of the run loop, and `perform` refuses while the group is still open,
/// so the person's own press, which comes in a later pass, always finds the group closed.
@MainActor
final class StepUndo: NSObject {
    private weak var undoManager: UndoManager?
    private(set) var isCurrent = true
    /// Runs once, when the claim ends because the undo manager moved on.
    var onLapse: (() -> Void)?

    init(undoManager: UndoManager) {
        self.undoManager = undoManager
        super.init()
        for name in [Notification.Name.NSUndoManagerDidOpenUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(managerMoved), name: name, object: undoManager)
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func managerMoved() { lapse() }

    private func lapse() {
        guard isCurrent else { return }
        isCurrent = false
        NotificationCenter.default.removeObserver(self)
        let lapsed = onLapse
        onLapse = nil
        lapsed?()
    }

    /// Takes the change back, once, and only while it is still the manager's latest step and its group is closed.
    func perform() {
        guard isCurrent, let undoManager, undoManager.groupingLevel == 0, undoManager.canUndo else { return }
        lapse()
        undoManager.undo()
    }
}
